#!/bin/bash
echo "=========================================="
echo "游戏录像与回放系统"
echo "=========================================="
echo ""
echo "正在启动..."
echo ""

# 使用修复版文件
cp main_fixed.py main.py
cp recorder_fixed.py recorder.py
cp playback_engine_fixed.py playback_engine.py

python main.py
