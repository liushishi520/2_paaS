#!/bin/bash
# 修复Python导入路径

# 创建__init__.py文件
touch device-management/__init__.py
touch edge-inference/__init__.py
touch data-pipeline/__init__.py
touch cloud-control/__init__.py
touch application/__init__.py

# 重命名目录（Python不允许目录名中有连字符）
mv device-management device_management
mv edge-inference edge_inference
mv data-pipeline data_pipeline
mv cloud-control cloud_control

echo "目录已重命名，导入问题已修复"
