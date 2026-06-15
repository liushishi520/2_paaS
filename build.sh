#!/bin/bash
# 编译Rust项目
cd rust-lib
cargo build --release
cd ..

# 复制共享库
cp rust-lib/target/release/librust_lib.so .
cp rust-lib/target/release/librust_lib.a .

echo "编译完成"
