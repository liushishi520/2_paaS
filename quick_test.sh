#!/bin/bash
# 快速自动化测试脚本

echo "========================================="
echo "   图像修复服务 - 自动化测试"
echo "========================================="
echo ""

# 检查Python环境
if ! command -v python &> /dev/null; then
    echo "❌ Python未安装"
    exit 1
fi

# 运行测试
python auto_test.py

# 检查测试结果
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 自动化测试全部通过"
    echo "📁 查看测试输出: test_output/"
    echo "📄 查看详细报告: cat test_output/test_report.json"
else
    echo ""
    echo "❌ 测试失败，请检查错误信息"
    exit 1
fi
