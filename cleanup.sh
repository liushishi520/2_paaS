#!/bin/bash
echo "清理现有进程..."
pkill -f "python src/app.py" 2>/dev/null
pkill -f "simulate_device.py" 2>/dev/null
sleep 2
echo "清理完成"
