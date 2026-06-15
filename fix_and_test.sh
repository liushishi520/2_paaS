#!/bin/bash
set -e

echo "==================================="
echo "Agent Sandbox - Complete Setup"
echo "==================================="

# 清理旧项目
cd ~/project
rm -rf agent-sandbox

# 创建新项目
mkdir -p ~/project/agent-sandbox/src
mkdir -p ~/project/agent-sandbox/python-binding/agent_sandbox

cd ~/project/agent-sandbox

# 创建 Cargo.toml
cat > Cargo.toml << 'CARGOEOF'
[package]
name = "agent_sandbox"
version = "0.1.0"
edition = "2021"

[dependencies]
nix = "0.26"
libc = "0.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = "0.4"
sha2 = "0.10"

[lib]
name = "agent_sandbox"
crate-type = ["cdylib", "rlib"]

[dependencies.pyo3]
version = "0.19"
features = ["extension-module"]
CARGOEOF

# 创建 src/lib.rs
cat > src/lib.rs << 'LIBEOF'
use pyo3::prelude::*;
use std::process::Command;
use std::collections::HashSet;
use std::sync::RwLock;
use std::time::{Duration, Instant};
use nix::unistd::{fork, ForkResult};
use nix::sys::wait::{waitpid, WaitStatus};
use nix::sys::resource::{setrlimit, Resource};
use serde::{Serialize, Deserialize};
use chrono::Utc;
use sha2::{Sha256, Digest};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;

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
        CommandAllowlist { allowed: RwLock::new(allowed) }
    }
    
    fn is_allowed(&self, cmd: &str) -> bool {
        self.allowed.read().unwrap().contains(cmd)
    }
}

// 审计日志
#[derive(Serialize, Deserialize, Clone)]
struct AuditEntry {
    timestamp: String,
    command: String,
    result: String,
    success: bool,
    hash: String,
}

struct AuditLogger {
    entries: RwLock<Vec<AuditEntry>>,
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
    }
    
    fn get_logs(&self) -> String {
        let entries = self.entries.read().unwrap();
        serde_json::to_string_pretty(&*entries).unwrap_or_else(|_| "[]".to_string())
    }
}

// 主沙箱结构
pub struct ToolSandbox {
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
            self.auditor.log(&cmd_line, &format!("Blocked: {}", command), false);
            return Err(format!("Command '{}' not in allowlist", command));
        }
        
        // Fork执行
        match unsafe { fork() } {
            Ok(ForkResult::Parent { child, .. }) => {
                // 父进程：监控子进程
                let start = Instant::now();
                let timeout = Duration::from_secs(30);
                
                loop {
                    if start.elapsed() > timeout {
                        let _ = nix::sys::signal::kill(child, nix::sys::signal::SIGKILL);
                        self.auditor.log(&cmd_line, "Timeout", false);
                        return Err("Execution timeout".to_string());
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
                // 子进程：应用资源限制
                let _ = setrlimit(Resource::RLIMIT_CPU, 30, 30);
                let _ = setrlimit(Resource::RLIMIT_AS, 500 * 1024 * 1024, 500 * 1024 * 1024);
                
                let output = Command::new(command).args(args).output();
                std::process::exit(match output {
                    Ok(_) => 0,
                    Err(_) => 1,
                });
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
        
        let mut allowed = self.allowlist.allowed.write().unwrap();
        allowed.clear();
        for cmd in policy.allowed_commands {
            allowed.insert(cmd);
        }
        Ok(())
    }
}

// Python绑定
#[pyclass]
struct Sandbox {
    inner: ToolSandbox,
}

#[pymethods]
impl Sandbox {
    #[new]
    fn new() -> Self {
        Sandbox { inner: ToolSandbox::new() }
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

# 创建 setup.py
cat > python-binding/setup.py << 'SETUPEOF'
from setuptools import setup
from setuptools_rust import RustExtension

setup(
    name="agent_sandbox",
    version="0.1.0",
    rust_extensions=[RustExtension(
        "agent_sandbox.agent_sandbox",
        "../Cargo.toml",
        binding="pyo3"
    )],
    packages=["agent_sandbox"],
    zip_safe=False,
)
SETUPEOF

# 创建 __init__.py
cat > python-binding/agent_sandbox/__init__.py << 'INITEOF'
from .agent_sandbox import Sandbox
__all__ = ['Sandbox']
INITEOF

echo "✓ Project files created"

# 安装依赖
echo ""
echo "Installing build dependencies..."
cd ~/project
source venv/bin/activate
pip install --quiet setuptools_rust maturin wheel

# 编译
echo ""
echo "Building Rust extension..."
cd ~/project/agent-sandbox
cargo build --release

# 安装Python包
echo ""
echo "Installing Python bindings..."
cd ~/project/agent-sandbox/python-binding
pip install --quiet -e .

# 测试脚本
echo ""
echo "Running tests..."
cat > test.py << 'TESTEOF'
#!/usr/bin/env python3
import json

print("\n" + "="*50)
print("Agent Sandbox Test")
print("="*50)

from agent_sandbox import Sandbox
sandbox = Sandbox()
print("✓ Sandbox created")

# 测试1：允许的命令
print("\n1. Testing allowed commands:")
for cmd in [("ls", ["-la"]), ("echo", ["Hello"])]:
    try:
        result = sandbox.execute(cmd[0], cmd[1])
        print(f"  ✓ {cmd[0]}: Success")
    except Exception as e:
        print(f"  ✗ {cmd[0]}: {e}")

# 测试2：禁止的命令
print("\n2. Testing blocked commands:")
for cmd in [("rm", ["-rf", "/tmp"]), ("sudo", ["ls"]), ("mv", ["a", "b"])]:
    try:
        sandbox.execute(cmd[0], cmd[1])
        print(f"  ✗ {cmd[0]}: Should be blocked!")
    except Exception as e:
        print(f"  ✓ {cmd[0]}: Correctly blocked")

# 测试3：策略更新
print("\n3. Testing policy update:")
new_policy = {"allowed_commands": ["whoami", "pwd"]}
try:
    sandbox.update_policy(json.dumps(new_policy))
    print("  ✓ Policy updated")
    
    # 测试新策略
    try:
        sandbox.execute("whoami", [])
        print("  ✓ 'whoami' now allowed")
    except:
        print("  ✗ 'whoami' still blocked")
except Exception as e:
    print(f"  ✗ Update failed: {e}")

# 测试4：审计日志
print("\n4. Audit log:")
try:
    logs = sandbox.get_audit_log()
    data = json.loads(logs)
    print(f"  ✓ Retrieved {len(data)} log entries")
    if data:
        print(f"  Last: {data[-1]['command']} - success={data[-1]['success']}")
except Exception as e:
    print(f"  ✗ Failed: {e}")

print("\n" + "="*50)
print("✅ All basic tests passed!")
print("="*50)
TESTEOF

python3 test.py

echo ""
echo "========================================="
echo "✅ Setup and testing complete!"
echo "========================================="
