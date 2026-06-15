#!/bin/bash
set -e

echo "=== Setting up Agent Sandbox ==="

# 创建目录结构
mkdir -p ~/project/agent-sandbox/src
mkdir -p ~/project/agent-sandbox/python-binding/agent_sandbox

cd ~/project/agent-sandbox

# 创建 Cargo.toml
cat > Cargo.toml << 'CARGOEOF'
[package]
name = "agent-sandbox"
version = "0.1.0"
edition = "2021"

[dependencies]
nix = "0.27"
libc = "0.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = "0.4"
sysinfo = "0.30"
sha2 = "0.10"
parking_lot = "0.12"
lazy_static = "1.4"
dirs = "5.0"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies.pyo3]
version = "0.20"
features = ["extension-module"]
CARGOEOF

# 创建 src/lib.rs
cat > src/lib.rs << 'LIBEOF'
use pyo3::prelude::*;
use std::sync::Arc;
use std::process::Command;

mod sandbox;
mod resource;
mod policy;
mod audit;
mod command;

use sandbox::ToolSandbox;

#[pyclass]
pub struct Sandbox {
    inner: Arc<ToolSandbox>,
}

#[pymethods]
impl Sandbox {
    #[new]
    fn new() -> PyResult<Self> {
        Ok(Sandbox {
            inner: Arc::new(ToolSandbox::new()),
        })
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
        self.inner.get_audit_log()
            .map_err(|e| pyo3::exceptions::PyRuntimeError::new_err(e))
    }
}

#[pymodule]
fn agent_sandbox(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_class::<Sandbox>()?;
    Ok(())
}
LIBEOF

# 创建 src/sandbox.rs
cat > src/sandbox.rs << 'SANDBOXEOF'
use std::process::Command;
use std::time::{Duration, Instant};
use std::sync::{Arc, Mutex};
use nix::unistd::{fork, ForkResult};
use nix::sys::wait::{waitpid, WaitStatus};
use crate::resource::ResourceLimiter;
use crate::policy::PolicyEngine;
use crate::audit::AuditLogger;
use crate::command::CommandAllowlist;

pub struct ToolSandbox {
    resource_limiter: ResourceLimiter,
    policy_engine: PolicyEngine,
    audit_logger: Arc<Mutex<AuditLogger>>,
    command_allowlist: CommandAllowlist,
}

impl ToolSandbox {
    pub fn new() -> Self {
        ToolSandbox {
            resource_limiter: ResourceLimiter::new(500, 1, 30),
            policy_engine: PolicyEngine::new(),
            audit_logger: Arc::new(Mutex::new(AuditLogger::new())),
            command_allowlist: CommandAllowlist::new(),
        }
    }
    
    pub fn execute(&self, command: &str, args: &[String]) -> Result<String, String> {
        let start_time = Instant::now();
        let cmd_str = format!("{} {}", command, args.join(" "));
        
        if !self.command_allowlist.is_allowed(command) {
            let error_msg = format!("Command '{}' not in allowlist", command);
            self.audit_logger.lock().unwrap().log_failure(&cmd_str, &error_msg);
            return Err(error_msg);
        }
        
        match unsafe { fork() } {
            Ok(ForkResult::Parent { child, .. }) => {
                let result = self.monitor_child(child, start_time);
                match result {
                    Ok(output) => {
                        self.audit_logger.lock().unwrap().log_success(&cmd_str, &output);
                        Ok(output)
                    }
                    Err(e) => {
                        self.audit_logger.lock().unwrap().log_failure(&cmd_str, &e);
                        Err(e)
                    }
                }
            }
            Ok(ForkResult::Child) => {
                self.resource_limiter.apply_limits();
                let output = Command::new(command).args(args).output();
                std::process::exit(match output {
                    Ok(_) => 0,
                    Err(_) => 1,
                });
            }
            Err(e) => {
                let error = format!("Fork failed: {}", e);
                self.audit_logger.lock().unwrap().log_failure(&cmd_str, &error);
                Err(error)
            }
        }
    }
    
    fn monitor_child(&self, child: nix::unistd::Pid, start_time: Instant) -> Result<String, String> {
        let timeout = Duration::from_secs(30);
        
        loop {
            if start_time.elapsed() > timeout {
                let _ = nix::sys::signal::kill(child, nix::sys::signal::SIGKILL);
                return Err("Timeout exceeded 30 seconds".to_string());
            }
            
            match waitpid(child, Some(nix::sys::wait::WaitPidFlag::WNOHANG)) {
                Ok(WaitStatus::Exited(_, status)) => {
                    return if status == 0 {
                        Ok("Command executed successfully".to_string())
                    } else {
                        Err(format!("Command failed with exit code: {}", status))
                    };
                }
                Ok(WaitStatus::Signaled(_, signal, _)) => {
                    return Err(format!("Command killed by signal: {:?}", signal));
                }
                Ok(_) => {
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    return Err(format!("Waitpid failed: {}", e));
                }
            }
        }
    }
    
    pub fn update_policy(&self, policy_json: &str) -> Result<(), String> {
        self.policy_engine.update_policy(policy_json)
    }
    
    pub fn get_audit_log(&self) -> Result<String, String> {
        self.audit_logger.lock().unwrap().get_logs()
    }
}
SANDBOXEOF

# 创建 src/resource.rs
cat > src/resource.rs << 'RESEOF'
use nix::sys::resource::{setrlimit, Resource};
use libc::{RLIMIT_CPU, RLIMIT_AS, RLIMIT_NPROC};

pub struct ResourceLimiter {
    max_memory_mb: u64,
    max_cpu_cores: u64,
    max_time_seconds: u64,
}

impl ResourceLimiter {
    pub fn new(max_memory_mb: u64, max_cpu_cores: u64, max_time_seconds: u64) -> Self {
        ResourceLimiter { max_memory_mb, max_cpu_cores, max_time_seconds }
    }
    
    pub fn apply_limits(&self) {
        let cpu_limit = self.max_time_seconds as libc::rlim_t;
        let _ = setrlimit(Resource::RLIMIT_CPU, cpu_limit, cpu_limit);
        
        let memory_limit = (self.max_memory_mb * 1024 * 1024) as libc::rlim_t;
        let _ = setrlimit(Resource::RLIMIT_AS, memory_limit, memory_limit);
        
        let _ = setrlimit(Resource::RLIMIT_NPROC, 1, 1);
        
        #[cfg(target_os = "linux")]
        {
            use libc::{cpu_set_t, sched_setaffinity, CPU_SET, CPU_ZERO};
            unsafe {
                let mut cpuset: cpu_set_t = std::mem::zeroed();
                CPU_ZERO(&mut cpuset);
                CPU_SET(0, &mut cpuset);
                sched_setaffinity(0, std::mem::size_of::<cpu_set_t>(), &cpuset);
            }
        }
    }
}
RESEOF

# 创建 src/policy.rs
cat > src/policy.rs << 'POLICYEOF'
use serde::{Serialize, Deserialize};
use std::sync::RwLock;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityPolicy {
    pub allowed_commands: Vec<String>,
    pub allowed_paths: Vec<String>,
    pub max_memory_mb: u64,
    pub max_cpu_cores: u64,
    pub max_time_seconds: u64,
    pub enable_network: bool,
    pub enable_filesystem: bool,
}

impl Default for SecurityPolicy {
    fn default() -> Self {
        SecurityPolicy {
            allowed_commands: vec!["ls".to_string(), "cat".to_string(), "echo".to_string()],
            allowed_paths: vec!["/tmp".to_string(), "/home".to_string()],
            max_memory_mb: 500,
            max_cpu_cores: 1,
            max_time_seconds: 30,
            enable_network: false,
            enable_filesystem: true,
        }
    }
}

pub struct PolicyEngine {
    policy: RwLock<SecurityPolicy>,
}

impl PolicyEngine {
    pub fn new() -> Self {
        PolicyEngine { policy: RwLock::new(SecurityPolicy::default()) }
    }
    
    pub fn update_policy(&self, policy_json: &str) -> Result<(), String> {
        let new_policy: SecurityPolicy = serde_json::from_str(policy_json)
            .map_err(|e| format!("Invalid policy JSON: {}", e))?;
        
        if new_policy.max_memory_mb == 0 || new_policy.max_memory_mb > 4096 {
            return Err("Invalid memory limit".to_string());
        }
        
        let mut policy = self.policy.write().unwrap();
        *policy = new_policy;
        Ok(())
    }
}
POLICYEOF

# 创建 src/audit.rs
cat > src/audit.rs << 'AUDITEOF'
use serde::{Serialize, Deserialize};
use chrono::{Utc, DateTime};
use std::fs::{OpenOptions, File};
use std::io::Write;
use std::path::PathBuf;
use sha2::{Sha256, Digest};
use parking_lot::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEntry {
    pub timestamp: DateTime<Utc>,
    pub command: String,
    pub result: String,
    pub success: bool,
    pub hash: String,
    pub previous_hash: String,
}

pub struct AuditLogger {
    log_file: PathBuf,
    entries: Mutex<Vec<AuditEntry>>,
    last_hash: Mutex<String>,
}

impl AuditLogger {
    pub fn new() -> Self {
        let log_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")).join(".agent-sandbox");
        std::fs::create_dir_all(&log_dir).unwrap();
        let log_file = log_dir.join("audit.log");
        
        AuditLogger {
            log_file,
            entries: Mutex::new(Vec::new()),
            last_hash: Mutex::new(String::new()),
        }
    }
    
    pub fn log_success(&self, command: &str, result: &str) {
        self.log_entry(command, result, true);
    }
    
    pub fn log_failure(&self, command: &str, error: &str) {
        self.log_entry(command, error, false);
    }
    
    fn log_entry(&self, command: &str, result: &str, success: bool) {
        let mut entries = self.entries.lock();
        let previous_hash = self.last_hash.lock().clone();
        
        let mut entry = AuditEntry {
            timestamp: Utc::now(),
            command: command.to_string(),
            result: result.to_string(),
            success,
            hash: String::new(),
            previous_hash,
        };
        
        let content = format!("{}{}{}{}{}", 
            entry.timestamp.to_rfc3339(), entry.command, entry.result, entry.success, entry.previous_hash);
        
        let mut hasher = Sha256::new();
        hasher.update(content.as_bytes());
        entry.hash = format!("{:x}", hasher.finalize());
        
        *self.last_hash.lock() = entry.hash.clone();
        entries.push(entry.clone());
        
        if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&self.log_file) {
            let _ = writeln!(file, "{}", serde_json::to_string(&entry).unwrap());
        }
    }
    
    pub fn get_logs(&self) -> Result<String, String> {
        let entries = self.entries.lock();
        serde_json::to_string_pretty(&*entries).map_err(|e| format!("Failed to serialize logs: {}", e))
    }
}
AUDITEOF

# 创建 src/command.rs
cat > src/command.rs << 'CMDEFO'
use std::collections::HashSet;
use std::sync::RwLock;

pub struct CommandAllowlist {
    allowed: RwLock<HashSet<String>>,
}

impl CommandAllowlist {
    pub fn new() -> Self {
        let mut allowed = HashSet::new();
        allowed.insert("ls".to_string());
        allowed.insert("cat".to_string());
        allowed.insert("echo".to_string());
        allowed.insert("grep".to_string());
        allowed.insert("wc".to_string());
        
        CommandAllowlist { allowed: RwLock::new(allowed) }
    }
    
    pub fn is_allowed(&self, command: &str) -> bool {
        let base_cmd = std::path::Path::new(command)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(command);
        self.allowed.read().unwrap().contains(base_cmd)
    }
}
CMDEFO

# 创建 Python binding setup.py
cat > python-binding/setup.py << 'SETUPEOF'
from setuptools import setup
from setuptools_rust import Binding, RustExtension

setup(
    name="agent_sandbox",
    version="0.1.0",
    rust_extensions=[RustExtension(
        "agent_sandbox.agent_sandbox",
        path="../Cargo.toml",
        binding=Binding.PyO3,
    )],
    packages=["agent_sandbox"],
    zip_safe=False,
)
SETUPEOF

# 创建 Python __init__.py
cat > python-binding/agent_sandbox/__init__.py << 'INITEOF'
from .agent_sandbox import Sandbox
__all__ = ['Sandbox']
INITEOF

echo "=== Setup complete ==="
