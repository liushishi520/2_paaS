#!/bin/bash
echo "Installing dependencies for Cascade Inference Engine..."

# 激活虚拟环境
source venv/bin/activate

# 升级pip
pip install --upgrade pip

# 安装核心依赖
pip install numpy
pip install scikit-learn
pip install matplotlib
pip install psutil

# 可选：PyTorch (根据系统选择)
# pip install torch torchvision

echo "Dependencies installed successfully!"
echo ""
echo "To run the cascade engine:"
echo "  python run_cascade_engine.py --mode demo"
echo ""
echo "To run tests:"
echo "  python run_cascade_engine.py --mode test"
echo ""
echo "To run benchmark:"
echo "  python run_cascade_engine.py --mode benchmark --samples 1000"
