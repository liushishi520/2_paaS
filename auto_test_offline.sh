#!/bin/bash

echo "========================================="
echo "Mojo Embedding Service - Offline Auto Test"
echo "========================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PORT=8000

# 清理端口
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo -e "${YELLOW}Port $PORT is busy. Killing existing process...${NC}"
    kill -9 $(lsof -t -i:$PORT) 2>/dev/null
    sleep 2
fi

# 启动离线服务
echo -e "${GREEN}Starting offline embedding service...${NC}"
nohup python embedding_service_offline.py > service.log 2>&1 &
SERVICE_PID=$!
echo "Service PID: $SERVICE_PID"

# 等待服务启动
echo -e "${YELLOW}Waiting for service...${NC}"
MAX_RETRIES=20
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:$PORT/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Service is ready!${NC}"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 1
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "\n${RED}✗ Service failed to start${NC}"
    tail -20 service.log
    exit 1
fi

echo ""

# 运行测试
echo -e "${GREEN}Running Tests${NC}"
echo "========================================="

# 测试1: 健康检查
echo -e "\n${YELLOW}[1/8] Health Check${NC}"
curl -s http://localhost:$PORT/health | python3 -m json.tool

# 测试2: 单文本
echo -e "\n${YELLOW}[2/8] Single Text Embedding${NC}"
curl -s -X POST http://localhost:$PORT/v1/embeddings \
    -H "Content-Type: application/json" \
    -d '{"texts": ["Hello world"]}' | python3 -m json.tool

# 测试3: 批量32
echo -e "\n${YELLOW}[3/8] Batch 32 Texts${NC}"
python3 << EOF
import requests, time
texts = [f"Test text {i}" for i in range(32)]
start = time.time()
response = requests.post("http://localhost:$PORT/v1/embeddings", json={"texts": texts})
elapsed = time.time() - start
data = response.json()
print(f"Generated {len(data['embeddings'])} embeddings")
print(f"Dimension: {len(data['embeddings'][0])}")
print(f"Latency: {elapsed*1000:.2f}ms")
print(f"Throughput: {32/elapsed:.2f} req/sec")
