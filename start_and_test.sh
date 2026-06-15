#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AI数据标注平台 - 完整启动与测试${NC}"
echo -e "${GREEN}========================================${NC}"

# 清理端口
echo -e "${YELLOW}[1/7] 清理端口8000...${NC}"
lsof -ti:8000 | xargs kill -9 2>/dev/null
pkill -f "app.main" 2>/dev/null
sleep 2
echo -e "${GREEN}✓ 端口已清理${NC}"

# 启动服务器
echo -e "${YELLOW}[2/7] 启动服务器...${NC}"
nohup python -m app.main > server.log 2>&1 &
SERVER_PID=$!
echo -e "${GREEN}✓ 服务器已启动 (PID: $SERVER_PID)${NC}"

# 等待服务器启动
echo -e "${YELLOW}[3/7] 等待服务器启动...${NC}"
for i in {1..15}; do
    if curl -s http://localhost:8000/ > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 服务器启动成功${NC}"
        break
    fi
    if [ $i -eq 15 ]; then
        echo -e "${RED}✗ 服务器启动超时${NC}"
        tail -30 server.log
        exit 1
    fi
    sleep 1
    echo -n "."
done
echo ""

# 显示服务器版本
echo -e "${YELLOW}[4/7] 测试API...${NC}"
curl -s http://localhost:8000/ | python -m json.tool

# 创建测试数据
echo -e "\n${YELLOW}[5/7] 创建测试数据...${NC}"
python << 'PYEOF'
from PIL import Image, ImageDraw
import os

os.makedirs('test_data', exist_ok=True)

# 创建测试图片
img = Image.new('RGB', (800, 600), color='white')
draw = ImageDraw.Draw(img)
draw.rectangle([100, 100, 300, 300], outline='red', width=3)
draw.rectangle([400, 200, 600, 400], outline='blue', width=3)
draw.ellipse([500, 50, 700, 250], outline='green', width=3)
img.save('test_data/test.jpg')
print("✓ 测试图片创建完成")

# 创建测试文本
with open('test_data/test.txt', 'w') as f:
    f.write("这是一个测试文本，包含人名张三和地名北京。")
print("✓ 测试文本创建完成")
PYEOF

# 运行完整API测试
echo -e "\n${YELLOW}[6/7] 运行API测试...${NC}"

python << 'PYEOF'
import requests
import json
import time

BASE = "http://localhost:8000"
results = {"pass": 0, "fail": 0}

def test(name, func):
    try:
        result = func()
        if result:
            print(f"  ✓ {name}")
            results["pass"] += 1
        else:
            print(f"  ✗ {name}")
            results["fail"] += 1
    except Exception as e:
        print(f"  ✗ {name}: {e}")
        results["fail"] += 1

# 测试1: 根路径
test("根路径", lambda: requests.get(f"{BASE}/").status_code == 200)

# 测试2: 创建项目
project_id = None
def create_project():
    global project_id
    r = requests.post(f"{BASE}/api/projects", json={"name": "测试项目", "type": "image"})
    if r.status_code == 200:
        project_id = r.json()["id"]
        return True
    return False
test("创建项目", create_project)

# 测试3: 获取项目列表
test("获取项目列表", lambda: requests.get(f"{BASE}/api/projects").status_code == 200)

# 测试4: 上传任务
task_id = None
def upload_task():
    global task_id
    if not project_id:
        return False
    with open("test_data/test.jpg", "rb") as f:
        r = requests.post(f"{BASE}/api/projects/{project_id}/tasks", files={"file": f})
    if r.status_code == 200:
        task_id = r.json()["id"]
        return True
    return False
test("上传图片任务", upload_task)

# 测试5: 自动标注
def auto_label():
    if not task_id:
        return False
    r = requests.post(f"{BASE}/api/tasks/{task_id}/auto-label")
    return r.status_code == 200
test("自动标注", auto_label)

# 测试6: 添加标注
def add_label():
    if not task_id:
        return False
    data = {
        "task_id": task_id,
        "label_type": "rectangle",
        "label_data": {"labels": [{"type": "rectangle", "label": "test", "bbox": [100,100,200,200]}]}
    }
    r = requests.post(f"{BASE}/api/labels?user_id=test_user", json=data)
    return r.status_code == 200
test("添加标注", add_label)

# 测试7: 提交审核
def submit_review():
    if not task_id:
        return False
    data = {"task_id": task_id, "status": "approved"}
    r = requests.post(f"{BASE}/api/reviews?reviewer_id=test_reviewer", json=data)
    return r.status_code == 200
test("提交审核", submit_review)

# 测试8: 质量检查
def quality_check():
    if not task_id:
        return False
    r = requests.get(f"{BASE}/api/quality/task/{task_id}")
    return r.status_code == 200
test("质量检查", quality_check)

# 测试9: 项目统计
def get_stats():
    if not project_id:
        return False
    r = requests.get(f"{BASE}/api/projects/{project_id}/statistics")
    if r.status_code == 200:
        stats = r.json()
        print(f"    总任务: {stats.get('total_tasks', 0)}")
        print(f"    完成率: {stats.get('progress_rate', 0)}%")
        return True
    return False
test("项目统计", get_stats)

# 测试10: 导出数据
def export_data():
    if not project_id:
        return False
    r = requests.post(f"{BASE}/api/projects/{project_id}/export?format=coco")
    return r.status_code == 200
test("导出COCO格式", export_data)

print(f"\n测试结果: {results['pass']} 通过, {results['fail']} 失败")
exit(0 if results['fail'] == 0 else 1)
PYEOF

TEST_RESULT=$?

# 显示服务器日志
echo -e "\n${YELLOW}[7/7] 服务器状态${NC}"
echo -e "${BLUE}服务器日志最后10行:${NC}"
tail -10 server.log

# 显示API文档地址
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✓ 测试完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}API文档:${NC}"
echo "  Swagger UI: http://localhost:8000/docs"
echo "  ReDoc: http://localhost:8000/redoc"
echo ""
echo -e "${BLUE}服务器信息:${NC}"
echo "  PID: $SERVER_PID"
echo "  日志: tail -f server.log"
echo ""
echo -e "${YELLOW}是否停止服务器？(输入 y 停止，其他键继续运行)${NC}"
read -t 10 -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kill $SERVER_PID 2>/dev/null
    lsof -ti:8000 | xargs kill -9 2>/dev/null
    echo -e "${GREEN}✓ 服务器已停止${NC}"
else
    echo -e "${GREEN}✓ 服务器继续运行${NC}"
fi

exit $TEST_RESULT
