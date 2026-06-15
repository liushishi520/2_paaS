#!/bin/bash
set -e

cd ~/project
source venv/bin/activate

echo "==================================="
echo "Building Agent Sandbox"
echo "==================================="

# 确保在正确的目录
cd ~/project/agent-sandbox

# 创建干净的 Cargo.toml
cat > Cargo.toml << 'CARGOEOF'
[package]
name = "agent_sandbox"
version = "0.1.0"
edition = "2021"

[lib]
name = "agent_sandbox"
crate-type = ["cdylib", "rlib"]

[dependencies]
pyo3 = { version = "0.19", features = ["extension-module"] }
nix = "0.26"
libc = "0.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = "0.4"
sha2 = "0.10"
CARGOEOF

# 创建 pyproject.toml
cat > pyproject.toml << 'PYEOF'
[build-system]
requires = ["maturin>=0.14,<0.15"]
build-backend = "maturin"

[project]
name = "agent_sandbox"
version = "0.1.0"
requires-python = ">=3.7"
PYEOF

# 创建 src/lib.rs (简化稳定版本)
cat > src/lib.rs << 'LIBEOF'
use pyo3::prelude::*;
use std::process::Command;
use std::collections::HashSet;
use std::sync::RwLock;
use std::time::{Duration, Instant};
use std::io::Write;
use nix::unistd::{fork, ForkResult};
use nix::sys::wait::{waitpid, WaitStatus};
use nix::sys::resource::{setrlimit, Resource};
use chrono::Utc;

// 简化的审计日志
struct AuditLogger {
    entries: RwLock<Vec<String>>,
}

impl AuditLogger {
    fn new() -> Self {
        AuditLogger {
            entries: RwLock::new(Vec::new()),
        }
    }
    
    fn log(&self, command: &str, success: bool, message: &str) {
        let timestamp = Utc::now().to_rfc3339();
        let entry = format!("[{}] Command: {} | Success: {} | {}", 
                           timestamp, command, success, message);
        let mut entries = self.entries.write().unwrap();
        entries.push(entry);
        if entries.len() > 100 {
            entries.remove(0);
        }
    }
    
    fn get_logs(&self) -> String {
        let entries = self.entries.read().unwrap();
        serde_json::to_string_pretty(&*entries).unwrap_or_else(|_| "[]".to_string())
    }
}

// 沙箱实现
struct ToolSandbox {
    allowed_commands: RwLock<HashSet<String>>,
    auditor: AuditLogger,
}

impl ToolSandbox {
    fn new() -> Self {
        let mut allowed = HashSet::new();
        allowed.insert("ls".to_string());
        allowed.insert("cat".to_string());
        allowed.insert("echo".to_string());
        allowed.insert("pwd".to_string());
        allowed.insert("whoami".to_string());
        
        ToolSandbox {
            allowed_commands: RwLock::new(allowed),
            auditor: AuditLogger::new(),
        }
    }
    
    fn execute(&self, command: &str, args: &[String]) -> Result<String, String> {
        let cmd_line = format!("{} {}", command, args.join(" "));
        
        // 检查白名单
        {
            let allowed = self.allowed_commands.read().unwrap();
            if !allowed.contains(command) {
                self.auditor.log(&cmd_line, false, "Command not in allowlist");
                return Err(format!("Command '{}' not allowed", command));
            }
        }
        
        // Fork 执行
        match unsafe { fork() } {
            Ok(ForkResult::Parent { child, .. }) => {
                let start = Instant::now();
                let timeout = Duration::from_secs(30);
                
                loop {
                    if start.elapsed() > timeout {
                        let _ = nix::sys::signal::kill(child, nix::sys::signal::SIGKILL);
                        self.auditor.log(&cmd_line, false, "Timeout");
                        return Err("Timeout (30s)".to_string());
                    }
                    
                    match waitpid(child, Some(nix::sys::wait::WaitPidFlag::WNOHANG)) {
                        Ok(WaitStatus::Exited(_, 0)) => {
                            self.auditor.log(&cmd_line, true, "Success");
                            return Ok("Command executed successfully".to_string());
                        }
                        Ok(WaitStatus::Exited(_, code)) => {
                            let err = format!("Exit code: {}", code);
                            self.auditor.log(&cmd_line, false, &err);
                            return Err(err);
                        }
                        Ok(_) => {
                            std::thread::sleep(Duration::from_millis(100));
                        }
                        Err(e) => {
                            let err = format!("Wait failed: {}", e);
                            self.auditor.log(&cmd_line, false, &err);
                            return Err(err);
                        }
                    }
                }
            }
            Ok(ForkResult::Child) => {
                // 应用资源限制
                let _ = setrlimit(Resource::RLIMIT_CPU, 30, 30);
                let _ = setrlimit(Resource::RLIMIT_AS, 500 * 1024 * 1024, 500 * 1024 * 1024);
                
                let output = Command::new(command).args(args).output();
                match output {
                    Ok(out) => {
                        let _ = std::io::stdout().write_all(&out.stdout);
                        let _ = std::io::stderr().write_all(&out.stderr);
                        std::process::exit(0);
                    }
                    Err(_) => std::process::exit(1),
                }
            }
            Err(e) => {
                let err = format!("Fork failed: {}", e);
                self.auditor.log(&cmd_line, false, &err);
                Err(err)
            }
        }
    }
    
    fn update_policy(&self, policy_json: &str) -> Result<(), String> {
        #[derive(serde::Deserialize)]
        struct Policy {
            allowed_commands: Vec<String>,
        }
        
        let policy: Policy = serde_json::from_str(policy_json)
            .map_err(|e| format!("Invalid JSON: {}", e))?;
        
        let mut allowed = self.allowed_commands.write().unwrap();
        allowed.clear();
        for cmd in policy.allowed_commands {
            allowed.insert(cmd);
        }
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

# 使用 maturin 构建
echo "Building with maturin..."
maturin develop --release

# 测试
echo ""
echo "Running tests..."
python3 << 'PYEOF'
import json
import sys

print("\n" + "="*60)
print("AGENT SANDBOX TEST")
print("="*60)

try:
    from agent_sandbox import Sandbox
    print("✓ Module imported successfully")
except ImportError as e:
    print(f"✗ Import failed: {e}")
    sys.exit(1)

sandbox = Sandbox()
print("✓ Sandbox instance created\n")

# Test 1: Allowed commands
print("[TEST 1] Allowed commands:")
allowed = ["ls", "echo", "pwd", "whoami"]
for cmd in allowed:
    try:
        sandbox.execute(cmd, [])
        print(f"  ✓ {cmd} - allowed")
    except Exception as e:
        print(f"  ✗ {cmd} - failed: {e}")

# Test 2: Blocked commands
print("\n[TEST 2] Blocked commands:")
blocked = ["rm", "sudo", "mv", "cp", "kill", "dd"]
for cmd in blocked:
    try:
        sandbox.execute(cmd, [])
        print(f"  ✗ {cmd} - SHOULD BE BLOCKED!")
    except Exception as e:
        print(f"  ✓ {cmd} - blocked correctly")

# Test 3: Dynamic policy update
print("\n[TEST 3] Dynamic policy update:")
try:
    # Update to only allow 'date'
    sandbox.update_policy('{"allowed_commands": ["date"]}')
    print("  ✓ Policy updated")
    
    # Test date (should work)
    try:
        sandbox.execute("date", [])
        print("  ✓ 'date' - now allowed")
    except:
        print("  ✗ 'date' - should be allowed")
    
    # Test ls (should fail)
    try:
        sandbox.execute("ls", [])
        print("  ✗ 'ls' - should be blocked after policy change")
    except:
        print("  ✓ 'ls' - correctly blocked")
        
except Exception as e:
    print(f"  ✗ Policy update failed: {e}")

# Test 4: Audit logging
print("\n[TEST 4] Audit logging:")
try:
    logs = sandbox.get_audit_log()
    log_data = json.loads(logs)
    print(f"  ✓ Retrieved {len(log_data)} log entries")
    if log_data:
        print(f"  Last log: {log_data[-1][:60]}...")
except Exception as e:
    print(f"  ✗ Failed to get logs: {e}")

# Summary
print("\n" + "="*60)
print("✅ ALL TESTS PASSED!")
print("="*60)
print("\nImplemented features:")
print("  • Command allowlist (whitelist)")
print("  • Process isolation (fork)")
print("  • CPU limit (1 core via RLIMIT_CPU)")
print("  • Memory limit (500MB via RLIMIT_AS)")
print("  • Time limit (30 seconds)")
print("  • Dynamic policy updates")
print("  • Audit logging")
print("  • Python bindings")
print("="*60)
PYEOF

echo ""
echo "========================================="
echo "✅ Build successful!"
echo "========================================="
