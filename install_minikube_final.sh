#!/bin/bash

cd ~/project

# 下载Minikube
echo "开始下载Minikube..."
wget https://github.com/kubernetes/minikube/releases/download/v1.31.2/minikube-linux-amd64

if [ -f minikube-linux-amd64 ]; then
    chmod +x minikube-linux-amd64
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube
    echo "Minikube安装成功"
    minikube version
else
    echo "下载失败，尝试使用代理"
    # 使用代理下载（如果有）
    wget --no-check-certificate https://mirrors.aliyun.com/kubernetes/minikube/v1.31.2/minikube-linux-amd64
    if [ -f minikube-linux-amd64 ]; then
        chmod +x minikube-linux-amd64
        sudo mv minikube-linux-amd64 /usr/local/bin/minikube
        echo "Minikube安装成功"
        minikube version
    else
        echo "Minikube下载失败，请检查网络"
        exit 1
    fi
fi
