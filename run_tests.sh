#!/bin/bash
echo "🚀 开始自动化测试..."
echo ""

# 确保数据目录存在
mkdir -p data/levels

# 运行测试
python3 tests/auto_test.py

# 检查测试结果
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 所有测试通过！"
else
    echo ""
    echo "❌ 部分测试失败，请查看上面的详细信息"
fi
