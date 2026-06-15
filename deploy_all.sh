#!/bin/bash
echo "========================================="
echo "部署容器云PaaS平台"
echo "========================================="

# 创建命名空间
kubectl create namespace wordpress-app
kubectl create namespace logging
kubectl create namespace devops
kubectl create namespace monitoring

# 部署MySQL
kubectl apply -f - << 'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: wordpress-app
type: Opaque
data:
  root-password: cm9vdDEyMzQ1Ng==
  password: d29yZHByZXNzMTIz
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: wordpress-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:5.7
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        - name: MYSQL_DATABASE
          value: wordpress
        - name: MYSQL_USER
          value: wordpress
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: wordpress-app
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
YAML

# 部署WordPress
kubectl apply -f - << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:latest
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql
        - name: WORDPRESS_DB_USER
          value: wordpress
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: WORDPRESS_DB_NAME
          value: wordpress
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: wordpress-app
spec:
  type: NodePort
  selector:
    app: wordpress
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
YAML

# 部署Elasticsearch和Kibana
kubectl apply -f - << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
      - name: elasticsearch
        image: elasticsearch:7.17.0
        env:
        - name: discovery.type
          value: single-node
        - name: ES_JAVA_OPTS
          value: "-Xms256m -Xmx256m"
        ports:
        - containerPort: 9200
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: logging
spec:
  selector:
    app: elasticsearch
  ports:
  - port: 9200
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kibana
  template:
    metadata:
      labels:
        app: kibana
    spec:
      containers:
      - name: kibana
        image: kibana:7.17.0
        env:
        - name: ELASTICSEARCH_HOSTS
          value: http://elasticsearch:9200
        ports:
        - containerPort: 5601
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: logging
spec:
  type: NodePort
  selector:
    app: kibana
  ports:
  - port: 5601
    targetPort: 5601
    nodePort: 30601
YAML

# 部署Jenkins
kubectl apply -f - << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
  namespace: devops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
      - name: jenkins
        image: jenkins/jenkins:lts
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: devops
spec:
  type: NodePort
  selector:
    app: jenkins
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30800
YAML

# 部署Prometheus和Grafana
kubectl apply -f - << 'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30900
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        env:
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: admin123
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30901
YAML

echo "等待Pod启动..."
sleep 30
echo "部署完成！"
echo "访问地址："
echo "WordPress: http://localhost:30080"
echo "Kibana: http://localhost:30601"
echo "Jenkins: http://localhost:30800"
echo "Prometheus: http://localhost:30900"
echo "Grafana: http://localhost:30901 (admin/admin123)"
