#!/bin/bash

echo "========================================="
echo "AI数据标注平台 - 诊断与修复"
echo "========================================="

# 1. 检查Python版本
echo -e "\n[1/6] 检查Python版本..."
python --version

# 2. 检查已安装的包
echo -e "\n[2/6] 检查关键依赖..."
pip list | grep -E "fastapi|uvicorn|sqlalchemy|pydantic"

# 3. 检查项目文件结构
echo -e "\n[3/6] 检查项目文件..."
if [ -f "app/main.py" ]; then
    echo "✓ app/main.py 存在"
else
    echo "✗ app/main.py 不存在"
    exit 1
fi

if [ -f "app/models.py" ]; then
    echo "✓ app/models.py 存在"
else
    echo "✗ app/models.py 不存在"
fi

# 4. 检查数据库初始化
echo -e "\n[4/6] 测试数据库初始化..."
python << 'PYEOF'
import sys
try:
    from app.models import Base, engine
    print("✓ 数据库模型导入成功")
    Base.metadata.create_all(engine)
    print("✓ 数据库表创建成功")
except Exception as e:
    print(f"✗ 数据库初始化失败: {e}")
    sys.exit(1)
PYEOF

if [ $? -ne 0 ]; then
    echo "数据库初始化失败，尝试重新安装依赖..."
    pip install sqlalchemy
fi

# 5. 测试导入所有模块
echo -e "\n[5/6] 测试模块导入..."
python << 'PYEOF'
import sys
modules = [
    ("app.models", "数据库模型"),
    ("app.auto_labeler", "自动标注器"),
    ("app.active_learning", "主动学习"),
    ("app.quality_check", "质检模块"),
    ("app.label_storage", "存储模块"),
    ("app.workflow", "工作流"),
]

for module, name in modules:
    try:
        __import__(module)
        print(f"✓ {name} 导入成功")
    except Exception as e:
        print(f"✗ {name} 导入失败: {e}")
PYEOF

# 6. 创建最小化测试版本
echo -e "\n[6/6] 创建最小化服务器测试..."
cat > test_minimal.py << 'PYEOF'
from fastapi import FastAPI
import uvicorn

app = FastAPI()

@app.get("/")
def root():
    return {"message": "Test server is running"}

if __name__ == "__main__":
    print("Starting minimal test server...")
    uvicorn.run(app, host="0.0.0.0", port=8000)
PYEOF

echo "启动最小化测试服务器（5秒）..."
timeout 5 python test_minimal.py 2>&1 &
sleep 3

if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "✓ 最小化服务器测试成功"
    pkill -f "test_minimal.py"
else
    echo "✗ 最小化服务器测试失败"
    echo "可能需要重新安装FastAPI和Uvicorn"
    pip install --upgrade fastapi uvicorn
fi

echo -e "\n========================================="
echo "诊断完成！"
echo "========================================="
