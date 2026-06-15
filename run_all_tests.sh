#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}OpenAPI Agent Test Suite${NC}"
echo -e "${BLUE}================================${NC}"

# 设置Python路径
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
echo -e "${GREEN}✓ PYTHONPATH set to: $PYTHONPATH${NC}"

# 运行基础测试
echo -e "\n${BLUE}Running Basic Tests...${NC}"
python tests/test_basic.py

# 检查退出状态
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✓ Basic tests passed!${NC}"
else
    echo -e "\n${RED}✗ Basic tests failed!${NC}"
    exit 1
fi

# 快速测试
echo -e "\n${BLUE}Running Quick Test...${NC}"
python quick_test.py

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Quick test passed!${NC}"
else
    echo -e "${RED}✗ Quick test failed!${NC}"
fi

echo -e "\n${GREEN}✓ All test suites completed!${NC}"
