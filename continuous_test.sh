#!/bin/bash
# 持续测试脚本

echo "持续测试模式 (每30秒运行一次)"
echo "按 Ctrl+C 停止"
echo ""

while true; do
    clear
    echo "========================================"
    echo "运行时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================"
    echo ""
    
    python auto_test.py 2>&1 | grep -E "(测试|通过|失败|达标|实体|关系)"
    
    echo ""
    echo "等待30秒..."
    sleep 30
done
