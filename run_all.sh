#!/bin/bash

echo "========================================="
echo "Mojo Embedding Service - Complete Test Suite"
echo "========================================="

# 清理旧进程
echo "Cleaning up old processes..."
pkill -f "python embedding_service.py" 2>/dev/null
sleep 2

# 释放端口
PORT=8000
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "Killing process on port $PORT..."
    kill -9 $(lsof -t -i:$PORT) 2>/dev/null
    sleep 2
fi

# 运行自动化测试
echo ""
./auto_test.sh

# 如果服务还在运行，运行性能基准
if curl -s http://localhost:$PORT/health > /dev/null 2>&1; then
    echo ""
    read -p "Run performance benchmark? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./benchmark_auto.sh
    fi
fi

echo ""
echo "All done!"
