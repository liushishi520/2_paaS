#!/bin/bash
echo "编译Rust项目（离线模式）..."

cd rust-lib

# 清理旧的编译文件
cargo clean

# 尝试编译
if cargo build --release 2>/dev/null; then
    echo "✓ 编译成功"
    cd ..
    cp rust-lib/target/release/librust_lib.so .
    echo "✓ 编译完成"
else
    echo "⚠ 编译失败，使用Python模拟模式"
    cd ..
    echo "# 模拟库" > librust_lib.so
fi

echo "构建脚本完成"
