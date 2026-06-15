#!/bin/bash

cd ~/project

# 使用清华大学镜像下载kubectl
echo "开始下载kubectl..."
wget https://mirrors.tuna.tsinghua.edu.cn/kubernetes/core/v1.28.0/bin/linux/amd64/kubectl

if [ -f kubectl ]; then
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "kubectl安装成功"
    kubectl version --client
else
    echo "下载失败，尝试备用地址"
    wget https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    kubectl version --client
fi
