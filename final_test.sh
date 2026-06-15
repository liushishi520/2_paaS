#!/bin/bash

echo "========================================="
echo "边缘设备监控系统 - 完整自动化测试"
echo "========================================="

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 清理函数
cleanup() {
    echo -e "\n${YELLOW}🧹 清理进程...${NC}"
    pkill -f "src/app_fixed.py" 2>/dev/null
    pkill -f "simulate_device.py" 2>/dev/null
    sleep 2
}

# 设置退出时的清理
trap cleanup EXIT INT TERM

# 清理旧进程
cleanup

# 删除旧数据库重新开始
rm -f data/device_monitor.db

# 启动服务器
echo -e "${YELLOW}[1/5] 启动监控服务器 (端口5001)...${NC}"
python src/app_fixed.py > server.log 2>&1 &
SERVER_PID=$!
echo "服务器PID: $SERVER_PID"

# 等待服务器启动
echo "等待服务器启动..."
sleep 5

# 检查服务器是否运行
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}❌ 服务器启动失败！查看 server.log${NC}"
    tail -20 server.log
    exit 1
fi
echo -e "${GREEN}✅ 服务器启动成功${NC}"

# 启动模拟设备
echo -e "${YELLOW}[2/5] 启动模拟设备...${NC}"
for i in {1..3}; do
    python simulate_device.py --id "sim-device-00$i" --server http://localhost:5001 --interval 10 > device_$i.log 2>&1 &
    echo "  启动模拟设备 sim-device-00$i"
done
sleep 3

# 测试API
echo -e "${YELLOW}[3/5] 测试API接口...${NC}"

# 测试心跳发送
echo "📤 发送测试心跳..."
curl -s -X POST http://localhost:5001/api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device-001",
    "cpu_usage": 45.5,
    "memory_usage": 60.2,
    "disk_usage": 55.8,
    "temperature": 52.3,
    "network": {"bytes_sent": 1024, "bytes_recv": 2048},
    "hostname": "test-host"
  }' | python -m json.tool

echo -e "\n📋 获取设备列表..."
curl -s http://localhost:5001/api/devices | python -m json.tool

echo -e "\n⚠️ 测试高负载告警..."
curl -s -X POST http://localhost:5001/api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device-001",
    "cpu_usage": 95.5,
    "memory_usage": 88.2,
    "disk_usage": 82.8,
    "temperature": 52.3,
    "network": {"bytes_sent": 1024, "bytes_recv": 2048},
    "hostname": "test-host"
  }' | python -m json.tool

# 等待告警触发
sleep 5

echo -e "\n🚨 获取告警列表..."
curl -s http://localhost:5001/api/alerts | python -m json.tool

# 测试健康分析
echo -e "\n${YELLOW}[4/5] 测试健康分析...${NC}"
for device in test-device-001 sim-device-001 sim-device-002; do
    echo "📊 分析设备 $device:"
    curl -s "http://localhost:5001/api/devices/$device/health" 2>/dev/null | python -m json.tool | head -15
    echo ""
done

# 生成健康报告
echo -e "${YELLOW}[5/5] 生成健康报告...${NC}"
curl -s "http://localhost:5001/api/report/test-device-001" 2>/dev/null | python -m json.tool

# 统计测试结果
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}📊 测试统计${NC}"
echo -e "${BLUE}=========================================${NC}"

# 统计设备数量
DEVICE_COUNT=$(curl -s http://localhost:5001/api/devices | python -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null)
ALERT_COUNT=$(curl -s http://localhost:5001/api/alerts | python -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null)

echo -e "${GREEN}✅ 设备数量: $DEVICE_COUNT${NC}"
echo -e "${YELLOW}⚠️ 告警数量: $ALERT_COUNT${NC}"

# 检查自动修复成功率
echo -e "\n🔧 自动修复记录:"
sqlite3 data/device_monitor.db "SELECT issue_type, success, COUNT(*) as count FROM auto_heal_records GROUP BY issue_type, success;" 2>/dev/null || echo "暂无自动修复记录"

# 计算自动修复成功率
TOTAL=$(sqlite3 data/device_monitor.db "SELECT COUNT(*) FROM auto_heal_records;" 2>/dev/null)
SUCCESS=$(sqlite3 data/device_monitor.db "SELECT COUNT(*) FROM auto_heal_records WHERE success=1;" 2>/dev/null)
if [ ! -z "$TOTAL" ] && [ $TOTAL -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=2; $SUCCESS * 100 / $TOTAL" | bc)
    echo -e "\n📈 自动修复成功率: ${SUCCESS_RATE}%"
    if (( $(echo "$SUCCESS_RATE > 70" | bc -l) )); then
        echo -e "${GREEN}✅ 达标！成功率 > 70%${NC}"
    else
        echo -e "${RED}❌ 未达标，成功率 < 70%${NC}"
    fi
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}✨ 测试完成！${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "📝 查看详细信息:"
echo "  服务器日志: tail -f server.log"
echo "  设备日志: tail -f device_1.log"
echo ""
echo "🌐 访问仪表盘: http://localhost:5001"
echo ""
echo "按 Enter 键停止所有服务并退出..."
read

# 清理
cleanup
echo -e "${GREEN}测试结束${NC}"
