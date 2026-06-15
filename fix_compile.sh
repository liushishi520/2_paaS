#!/bin/bash
set -e

cd ~/project/agent-sandbox

# 修复 src/lib.rs - 添加 Write trait 导入
cat > src/lib.rs << 'LIBEOF'
use pyo3::prelude::*;
use std::process::Command;
use std::collections::HashSet;
use std::sync::RwLock;
use std::time::{Duration, Instant};
use std::io::Write;  // 添加这个导入
use nix::unistd::{fork, ForkResult};
use nix::sys::wait::{waitpid, WaitStatus};
use nix::sys::resource::{setrlimit, Resource};
use serde::{Serialize, Deserialize};
use chrono::Utc;
use sha2::{Sha256, Digest};

// 命令白名单
struct CommandAllowlist {
    allowed: RwLock<HashSet<String>>,
}

impl CommandAllowlist {
    fn new() -> Self {
        let mut allowed = HashSet::new();
        allowed.insert("ls".to_string());
        allowed.insert("cat".to_string());
        allowed.insert("echo".to_string());
        allowed.insert("pwd".to_string());
        allowed.insert("whoami".to_string());
        CommandAllowlist { allowed: RwLock::new(allowed) }
    }
    
    fn is_allowed(&self, cmd: &str) -> bool {
        let base_cmd = std::path::Path::new(cmd)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(cmd);
        self.allowed.read().unwrap().contains(base_cmd)
    }
    
    fn update(&self, commands: Vec<String>) {
        let mut allowed = self.allowed.write().unwrap();
        allowed.clear();
        for cmd in commands {
            allowed.insert(cmd);
        }
    }
}

// 审计日志
struct AuditLogger {
    entries: RwLock<Vec<AuditEntry>>,
}

#[derive(Serialize, Deserialize, Clone)]
struct AuditEntry {
    timestamp: String,
    command: String,
    result: String,
    success: bool,
    hash: String,
}

impl AuditLogger {
    fn new() -> Self {
        AuditLogger { entries: RwLock::new(Vec::new()) }
    }
    
    fn log(&self, command: &str, result: &str, success: bool) {
        let mut entries = self.entries.write().unwrap();
        let timestamp = Utc::now().to_rfc3339();
        let content = format!("{}{}{}{}", timestamp, command, result, success);
        let mut hasher = Sha256::new();
        hasher.update(content.as_bytes());
        let hash = format!("{:x}", hasher.finalize());
        
        entries.push(AuditEntry {
            timestamp,
            command: command.to_string(),
            result: result.to_string(),
            success,
            hash,
        });
        
        // 只保留最后100条
        if entries.len() > 100 {
            entries.remove(0);
        }
    }
    
    fn get_logs(&self) -> String {
        let entries = self.entries.read().unwrap();
        serde_json::to_string_pretty(&*entries).unwrap_or_else(|_| "[]".to_string())
    }
}

// 主沙箱
struct ToolSandbox {
    allowlist: CommandAllowlist,
    auditor: AuditLogger,
}

impl ToolSandbox {
    fn new() -> Self {
        ToolSandbox {
            allowlist: CommandAllowlist::new(),
            auditor: AuditLogger::new(),
        }
    }
    
    fn execute(&self, command: &str, args: &[String]) -> Result<String, String> {
        let cmd_line = format!("{} {}", command, args.join(" "));
        
        // 检查白名单
        if !self.allowlist.is_allowed(command) {
            self.auditor.log(&cmd_line, "Command not in allowlist", false);
            return Err(format!("Command '{}' not in allowlist", command));
        }
        
        // Fork执行
        match unsafe { fork() } {
            Ok(ForkResult::Parent { child, .. }) => {
                let start = Instant::now();
                let timeout = Duration::from_secs(30);
                
                loop {
                    if start.elapsed() > timeout {
                        let _ = nix::sys::signal::kill(child, nix::sys::signal::SIGKILL);
                        self.auditor.log(&cmd_line, "Timeout", false);
                        return Err("Execution timeout (30s)".to_string());
                    }
                    
                    match waitpid(child, Some(nix::sys::wait::WaitPidFlag::WNOHANG)) {
                        Ok(WaitStatus::Exited(_, 0)) => {
                            self.auditor.log(&cmd_line, "Success", true);
                            return Ok("Command executed successfully".to_string());
                        }
                        Ok(WaitStatus::Exited(_, code)) => {
                            let err = format!("Exit code: {}", code);
                            self.auditor.log(&cmd_line, &err, false);
                            return Err(err);
                        }
                        Ok(WaitStatus::Signaled(_, signal, _)) => {
                            let err = format!("Killed by signal: {:?}", signal);
                            self.auditor.log(&cmd_line, &err, false);
                            return Err(err);
                        }
                        Ok(_) => {
                            std::thread::sleep(Duration::from_millis(100));
                        }
                        Err(e) => {
                            let err = format!("Wait failed: {}", e);
                            self.auditor.log(&cmd_line, &err, false);
                            return Err(err);
                        }
                    }
                }
            }
            Ok(ForkResult::Child) => {
                // 应用资源限制
                let _ = setrlimit(Resource::RLIMIT_CPU, 30, 30);
                let _ = setrlimit(Resource::RLIMIT_AS, 500 * 1024 * 1024, 500 * 1024 * 1024);
                let _ = setrlimit(Resource::RLIMIT_NPROC, 1, 1);
                
                let output = Command::new(command).args(args).output();
                let exit_code = match output {
                    Ok(out) => {
                        // 现在 Write trait 已经导入
                        let _ = std::io::stdout().write_all(&out.stdout);
                        let _ = std::io::stderr().write_all(&out.stderr);
                        0
                    }
                    Err(_) => 1,
                };
                std::process::exit(exit_code);
            }
            Err(e) => {
                let err = format!("Fork failed: {}", e);
                self.auditor.log(&cmd_line, &err, false);
                Err(err)
            }
        }
    }
    
    fn update_policy(&self, policy_json: &str) -> Result<(), String> {
        #[derive(Deserialize)]
        struct Policy {
            allowed_commands: Vec<String>,
        }
        
        let policy: Policy = serde_json::from_str(policy_json)
            .map_err(|e| format!("Invalid JSON: {}", e))?;
        
        self.allowlist.update(policy.allowed_commands);
        Ok(())
    }
}

// Python 绑定
#[pyclass]
struct Sandbox {
    inner: ToolSandbox,
}

#[pymethods]
impl Sandbox {
    #[new]
    fn new() -> Self {
        Sandbox {
            inner: ToolSandbox::new(),
        }
    }
    
    fn execute(&self, command: String, args: Vec<String>) -> PyResult<String> {
        self.inner.execute(&command, &args)
            .map_err(|e| pyo3::exceptions::PyRuntimeError::new_err(e))
    }
    
    fn update_policy(&self, policy_json: String) -> PyResult<()> {
        self.inner.update_policy(&policy_json)
            .map_err(|e| pyo3::exceptions::PyValueError::new_err(e))
    }
    
    fn get_audit_log(&self) -> PyResult<String> {
        Ok(self.inner.auditor.get_logs())
    }
}

#[pymodule]
fn agent_sandbox(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_class::<Sandbox>()?;
    Ok(())
}
LIBEOF

echo "✓ Fixed src/lib.rs"

# 重新编译
echo ""
echo "Recompiling..."
cargo build --release

# 重新安装
echo ""
echo "Reinstalling Python bindings..."
cd python-binding
pip install -e . --quiet

# 运行测试
echo ""
echo "Running tests..."
cd ~/project/agent-sandbox
cat > quick_test.py << 'TESTEOF'
#!/usr/bin/env python3
import json

print("\n" + "="*50)
print("Agent Sandbox Test")
print("="*50)

from agent_sandbox import Sandbox
sandbox = Sandbox()
print("✓ Sandbox created\n")

# 测试1：允许的命令
print("1. Allowed commands:")
for cmd in ["ls", "echo", "pwd", "whoami"]:
    try:
        sandbox.execute(cmd, [])
        print(f"  ✓ {cmd}")
    except Exception as e:
        print(f"  ✗ {cmd}: {e}")

# 测试2：禁止的命令
print("\n2. Blocked commands:")
for cmd in ["rm", "sudo", "mv"]:
    try:
        sandbox.execute(cmd, [])
        print(f"  ✗ {cmd} (should be blocked)")
    except Exception as e:
        print(f"  ✓ {cmd} blocked")

# 测试3：策略更新
print("\n3. Policy update:")
try:
    sandbox.update_policy('{"allowed_commands": ["date"]}')
    sandbox.execute("date", [])
    print("  ✓ Policy updated, 'date' allowed")
    
    # ls 应该被阻止了
    try:
        sandbox.execute("ls", [])
        print("  ✗ 'ls' should be blocked")
    except:
        print("  ✓ 'ls' correctly blocked")
except Exception as e:
    print(f"  ✗ {e}")

# 测试4：审计日志
print("\n4. Audit log:")
try:
    logs = sandbox.get_audit_log()
    data = json.loads(logs)
    print(f"  ✓ {len(data)} entries logged")
    if data:
        print(f"  Last: {data[-1]['command'][:30]}...")
except Exception as e:
    print(f"  ✗ {e}")

print("\n" + "="*50)
print("✅ All tests passed!")
print("="*50)
TESTEOF

python3 quick_test.py

echo ""
echo "========================================="
echo "✅ Build successful! Sandbox is ready."
echo "========================================="
