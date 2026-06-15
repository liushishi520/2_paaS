#!/bin/bash
echo "启动OCR+LLM智能文档抽取系统..."

# 检查虚拟环境
if [ -z "$VIRTUAL_ENV" ]; then
    echo "警告: 未检测到虚拟环境"
fi

# 安装依赖（如果必要）
if [ ! -f ".deps_installed" ]; then
    echo "安装依赖..."
    pip install -i https://pypi.org/simple paddlepaddle paddleocr pdf2image Pillow numpy opencv-python flask pandas loguru PyPDF2 reportlab
    
    # 安装其他依赖
    pip install flask-cors sqlalchemy jinja2 tqdm python-dotenv openai
    
    touch .deps_installed
fi

# 创建必要目录
mkdir -p data/{uploaded,processed,reviews} logs

# 启动应用
echo "启动Web服务..."
python app.py

if [ $? -ne 0 ]; then
    echo "启动失败，尝试使用简化版本..."
    python test_simple.py
fi
