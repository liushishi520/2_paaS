#!/bin/bash

SERVER_IP="192.168.26.135"

echo "========================================="
echo "容器云PaaS平台 - 最终状态"
echo "========================================="

echo -e "\n【容器状态】"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "wordpress|jenkins|elasticsearch|kibana|prometheus|grafana"

echo -e "\n【服务访问测试】"
curl -s -o /dev/null -w "WordPress: %{http_code}\n" http://$SERVER_IP
curl -s -o /dev/null -w "Jenkins: %{http_code}\n" http://$SERVER_IP:8080
curl -s -o /dev/null -w "Kibana: %{http_code}\n" http://$SERVER_IP:5601
curl -s -o /dev/null -w "Grafana: %{http_code}\n" http://$SERVER_IP:3000

echo -e "\n【Kubernetes集群】"
kubectl get nodes

echo -e "\n【访问地址】"
echo "WordPress: http://$SERVER_IP"
echo "Jenkins: http://$SERVER_IP:8080"
echo "Kibana: http://$SERVER_IP:5601"
echo "Grafana: http://$SERVER_IP:3000"

echo -e "\n【登录信息】"
echo "Jenkins密码: 77ae39e2dbe54703a06e645b1ccf2786"
echo "Grafana: admin/admin123"
echo "WordPress: 你刚设置的账号密码"

echo "========================================="
