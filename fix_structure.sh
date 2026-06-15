#!/bin/bash
# 重命名目录，将连字符改为下划线
mv attack-library attack_library 2>/dev/null
mv defense-library defense_library 2>/dev/null
mv robustness-metrics robustness_metrics 2>/dev/null
mv auto-tester auto_tester 2>/dev/null
mv comparison-dashboard comparison_dashboard 2>/dev/null

# 更新__init__.py文件
touch attack_library/__init__.py
touch defense_library/__init__.py
touch robustness_metrics/__init__.py
touch auto_tester/__init__.py
touch comparison_dashboard/__init__.py
touch certificate/__init__.py

echo "目录结构已修复"
