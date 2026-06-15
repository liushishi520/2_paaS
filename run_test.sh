#!/bin/bash
echo "=== 视频分析工具测试 ==="

# 激活虚拟环境
source venv/bin/activate

# 安装numpy（如果需要）
pip install numpy --quiet

# 运行分析
echo ""
echo "1. 分析单个文件:"
python main.py test1.mp4

echo ""
echo "2. 批量分析当前目录:"
python main.py .

echo ""
echo "✅ 完成！查看 reports/ 目录"
ls -lh reports/
