#!/bin/bash
echo "=== 视频元数据分析工具测试 ==="
echo ""

# 创建测试视频（使用Python生成，不需要ffmpeg）
python3 << 'PYTHON'
import os

# 创建一个简单的文本文件模拟视频信息
test_files = ['test1.mp4', 'test2.mkv', 'test3.avi']

for file in test_files:
    if not os.path.exists(file):
        # 创建虚拟文件
        with open(file, 'wb') as f:
            f.write(b'RIFF\x00\x00\x00\x00AVI LIST\x00\x00\x00\x00hdrlavih\x38\x00\x00\x00')
            f.write(b'\x00' * 1000)  # 填充数据
        print(f"✓ 创建测试文件: {file}")

print("\n✅ 测试文件创建完成")
PYTHON

echo ""
echo "测试单文件分析:"
python3 main.py test1.mp4

echo ""
echo "测试批量扫描:"
python3 main.py .

echo ""
echo "✅ 测试完成! 查看 reports/ 目录"
ls -lh reports/
