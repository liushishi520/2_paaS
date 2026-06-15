#!/bin/bash
# AI CLI Tools - Shell 脚本版本，零编译，立即可用

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置目录
CONFIG_DIR="$HOME/.ai-cli"
PROMPTS_DIR="$CONFIG_DIR/prompts"
CACHE_DIR="$CONFIG_DIR/cache"

mkdir -p "$PROMPTS_DIR" "$CACHE_DIR"

# 显示帮助
show_help() {
    cat << EOF
${CYAN}AI CLI Tools Suite${NC}
Usage: ai-cli <command> [options]

Commands:
  llm      Call LLM with prompts
  embed    Generate text embeddings  
  rag      RAG-powered Q&A
  prompt   Manage prompt templates
  cache    Manage semantic cache
  config   Configuration management

Examples:
  ai-cli llm --prompt "Hello World"
  echo "text" | ai-cli embed --stdin
  ai-cli rag --question "What is Rust?"
  ai-cli prompt list
  ai-cli cache set mykey myvalue
  ai-cli config show
