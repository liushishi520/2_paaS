#!/bin/bash
# 安装脚本 - 使用多个镜像源尝试

echo "开始安装Python依赖..."

# 尝试不同的镜像源
MIRRORS=(
    "https://pypi.org/simple"
    "https://mirrors.aliyun.com/pypi/simple"
    "https://pypi.douban.com/simple"
    "https://mirrors.ustc.edu.cn/pypi/web/simple"
)

for mirror in "${MIRRORS[@]}"; do
    echo "尝试使用镜像源: $mirror"
    if pip install -i "$mirror" pdfplumber camelot-py[cv] openpyxl pandas psycopg2-binary chardet; then
        echo "安装成功！使用镜像源: $mirror"
        exit 0
    else
        echo "使用 $mirror 安装失败，尝试下一个..."
    fi
done

echo "所有镜像源都失败了，请检查网络连接"
exit 1
