#!/bin/bash
# 批量处理脚本 - 无交互模式

echo "开始批量处理..."

python3 << 'PYTHON_SCRIPT'
from auto_rpa import RPAProcessor
from pathlib import Path

processor = RPAProcessor()

# 处理test_files目录下的所有文件
test_dir = Path("test_files")
if test_dir.exists():
    files = list(test_dir.glob("*.txt"))
    if files:
        print(f"找到 {len(files)} 个文件")
        processor.process_batch([str(f) for f in files])
        
        # 导出结果
        from datetime import datetime
        output_file = f"output/batch_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        processor.export_results(output_file)
        
        # 打印报告
        print(processor.generate_report())
    else:
        print("没有找到文件")
else:
    print("test_files目录不存在")

PYTHON_SCRIPT

echo ""
echo "批量处理完成！"
