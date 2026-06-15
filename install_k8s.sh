#!/bin/bash
cd ~/project

echo "========== 1. 安装 Docker =========="
# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker $USER

echo "========== 2. 安装 kubectl =========="
# 安装 kubectl
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

echo "========== 3. 安装 Minikube =========="
# 安装 Minikube
curl -LO https://github.com/kubernetes/minikube/releases/download/v1.31.2/minikube-linux-amd64
chmod +x minikube-linux-amd64
sudo mv minikube-linux-amd64 /usr/local/bin/minikube

echo "========== 验证安装 =========="
docker --version
kubectl version --client
minikube version

echo "安装完成！请执行: newgrp docker"
