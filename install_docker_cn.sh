#!/bin/bash

# 安装依赖
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# 使用阿里云镜像安装Docker
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"

# 安装Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# 启动Docker
sudo systemctl start docker
sudo systemctl enable docker

# 创建docker组并添加当前用户
sudo groupadd docker 2>/dev/null
sudo usermod -aG docker $USER

# 配置Docker镜像加速
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'JSON'
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn", "https://hub-mirror.c.163.com"]
}
JSON

# 重启Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "Docker安装完成"
docker --version
