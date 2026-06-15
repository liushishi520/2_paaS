#!/bin/bash

echo "清理所有进程和数据..."

# 停止所有相关进程
pkill -f "web_browser.py" 2>/dev/null
pkill -f "python.*web_browser" 2>/dev/null
fuser -k 5000/tcp 2>/dev/null

# 清理日志
rm -f web_server.log
rm -f nohup.out
rm -f test_results.json

# 清理临时文件
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
find . -type f -name "*.pyc" -delete 2>/dev/null

# 可选：清理输出文件
read -p "是否清理输出文件？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf data/output/*
    echo "输出文件已清理"
fi

echo "清理完成！"

# 显示剩余进程
echo ""
echo "剩余相关进程:"
ps aux | grep -E "web_browser|python" | grep -v grep || echo "无"
