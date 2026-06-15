#!/bin/bash

echo "====================================="
echo "边缘语音命令识别系统 - 修复版"
echo "====================================="

cd /home/gril/project
source venv/bin/activate

echo ""
echo "运行系统..."
echo ""

python app_fixed.py

echo ""
echo "系统已退出"
