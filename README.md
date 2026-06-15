# 容器云PaaS平台

## 项目简介
基于Kubernetes的企业级容器云PaaS平台，实现应用自动部署、日志收集、监控告警等完整功能。

## 已部署组件
- ✅ Kubernetes集群 (3节点)
- ✅ WordPress应用 + MySQL
- ✅ EFK日志系统 (Elasticsearch + Kibana)
- ✅ Jenkins CI/CD流水线
- ✅ Prometheus + Grafana监控告警

## 访问地址
- WordPress: http://192.168.26.135
- Jenkins: http://192.168.26.135:8080
- Grafana: http://192.168.26.135:3000 (admin/admin123)
- Kibana: http://192.168.26.135:5601

## 快速启动
```bash
docker start wordpress-mysql wordpress-app elasticsearch kibana jenkins prometheus grafana
