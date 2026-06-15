#!/bin/bash
echo "强制清理端口 5000..."
sudo fuser -k 5000/tcp 2>/dev/null || true
pkill -9 -f "python.*app.py" 2>/dev/null
pkill -9 -f "simulate_device" 2>/dev/null
sleep 2
echo "端口清理完成"
netstat -tulnp | grep 5000 || echo "端口5000已释放"
