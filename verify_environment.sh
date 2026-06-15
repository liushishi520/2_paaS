#!/bin/bash

echo "========================================="
echo "容器云PaaS平台环境验证"
echo "========================================="

# 1. 系统信息
echo -e "\n【1. 系统信息】"
echo "操作系统: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "内核版本: $(uname -r)"
echo "主机名: $(hostname)"

# 2. IP地址
echo -e "\n【2. IP地址】"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "服务器IP: $SERVER_IP"
echo "本地访问: http://localhost"

# 3. Docker状态
echo -e "\n【3. Docker状态】"
if docker ps &>/dev/null; then
    echo "✓ Docker运行中"
    echo "Docker版本: $(docker --version | awk '{print $3}')"
    echo "运行容器数: $(docker ps -q | wc -l)"
else
    echo "✗ Docker未运行"
fi

# 4. Kubernetes状态
echo -e "\n【4. Kubernetes状态】"
if kubectl get nodes &>/dev/null; then
    echo "✓ Kubernetes集群运行中"
    echo "节点信息:"
    kubectl get nodes
else
    echo "✗ Kubernetes未运行或未配置"
fi

# 5. 检查运行中的容器
echo -e "\n【5. 运行中的服务容器】"
if [ $(docker ps -q | wc -l) -gt 0 ]; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -10
else
    echo "没有运行中的容器"
fi

# 6. 检查K8s Pods（如果K8s可用）
echo -e "\n【6. Kubernetes Pods状态】"
if kubectl get pods --all-namespaces &>/dev/null; then
    echo "Pods总数: $(kubectl get pods --all-namespaces --no-headers | wc -l)"
    echo "运行的Pods: $(kubectl get pods --all-namespaces --no-headers | grep Running | wc -l)"
    echo ""
    kubectl get pods --all-namespaces | grep -E "wordpress|logging|devops|monitoring" || echo "未找到项目相关Pods"
else
    echo "Kubernetes不可用"
fi

# 7. 服务端口监听
echo -e "\n【7. 服务端口监听】"
echo "监听端口:"
netstat -tlnp 2>/dev/null | grep -E "80|8080|30080|30601|30800|30900|30901|5601|9090|3000" | awk '{print $4}' | sort -u

# 8. 服务访问测试
echo -e "\n【8. 服务访问测试】"

# WordPress测试
if curl -s -o /dev/null -w "%{http_code}" http://localhost:30080 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ WordPress: http://$SERVER_IP:30080"
elif curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ WordPress: http://$SERVER_IP"
else
    echo "✗ WordPress未就绪"
fi

# Jenkins测试
if curl -s -o /dev/null -w "%{http_code}" http://localhost:30800 2>/dev/null | grep -q "200\|301\|302\|403"; then
    echo "✓ Jenkins: http://$SERVER_IP:30800"
elif curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null | grep -q "200\|301\|302\|403"; then
    echo "✓ Jenkins: http://$SERVER_IP:8080"
else
    echo "✗ Jenkins未就绪"
fi

# Kibana测试
if curl -s -o /dev/null -w "%{http_code}" http://localhost:30601 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ Kibana: http://$SERVER_IP:30601"
elif curl -s -o /dev/null -w "%{http_code}" http://localhost:5601 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ Kibana: http://$SERVER_IP:5601"
else
    echo "✗ Kibana未就绪"
fi

# Prometheus测试
if curl -s -o /dev/null -w "%{http_code}" http://localhost:30900 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ Prometheus: http://$SERVER_IP:30900"
elif curl -s -o /dev/null -w "%{http_code}" http://localhost:9090 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ Prometheus: http://$SERVER_IP:9090"
else
    echo "✗ Prometheus未就绪"
fi

# Grafana测试
if curl -s -o /dev/null -w "%{http_code}" http://localhost:30901 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ Grafana: http://$SERVER_IP:30901 (admin/admin123)"
elif curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null | grep -q "200\|301\|302"; then
    echo "✓ Grafana: http://$SERVER_IP:3000 (admin/admin123)"
else
    echo "✗ Grafana未就绪"
fi

# 9. 资源使用
echo -e "\n【9. 资源使用】"
echo "磁盘使用:"
df -h / | tail -1 | awk '{print "已用: " $3 " / 总计: " $2 " (" $5 ")"}'
echo "内存使用:"
free -h | grep Mem | awk '{print "已用: " $3 " / 总计: " $2 " (" int($3/$2*100) "%)"}'

# 10. 项目文件
echo -e "\n【10. 项目文件】"
echo "项目目录: ~/project"
echo "文件数量: $(find ~/project -type f 2>/dev/null | wc -l)"
echo "主要文件:"
ls -lh ~/project/*.yaml ~/project/*.yml ~/project/*.sh 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'

echo -e "\n========================================="
echo "验证完成！"
echo "========================================="
