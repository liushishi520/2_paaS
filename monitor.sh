#!/bin/bash

# 监控服务器状态
while true; do
    clear
    echo "=== AI标注工具监控面板 ==="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 检查Web服务器
    if curl -s http://localhost:5000 > /dev/null 2>&1; then
        echo "✓ Web服务器: 运行中 (端口5000)"
        # 获取图像数量
        COUNT=$(curl -s http://localhost:5000/api/images | python -c "import sys,json; print(len(json.load(sys.stdin).get('images', [])))" 2>/dev/null || echo "N/A")
        echo "  图像数量: $COUNT"
    else
        echo "✗ Web服务器: 未运行"
    fi
    
    echo ""
    echo "资源使用:"
    # CPU和内存
    ps aux | grep -E "(web_browser|python.*web)" | grep -v grep | awk '{print "  PID: "$2", CPU: "$3"%, MEM: "$4"%"}'
    
    echo ""
    echo "日志大小:"
    ls -lh web_server.log 2>/dev/null | awk '{print "  " $9 ": " $5}'
    
    echo ""
    echo "按 Ctrl+C 退出监控"
    sleep 3
done
