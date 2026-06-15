#!/bin/bash
echo "========================================="
echo "Code Documentation Generator"
echo "========================================="
echo ""
echo "To generate documentation:"
echo "  python main.py generate /path/to/code"
echo ""
echo "To run demo:"
echo "  python main.py demo"
echo ""
echo "To test components:"
echo "  python test_generator.py"
echo ""
echo "========================================="

# 检查是否运行demo
if [ "$1" == "demo" ]; then
    python main.py demo
elif [ "$1" == "test" ]; then
    python test_generator.py
else
    echo ""
    echo "Running demo now..."
    python main.py demo
fi
