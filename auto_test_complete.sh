#!/bin/bash

echo "========================================="
echo "AI数据标注平台 - 自动化测试"
echo "========================================="

# 清理
echo "[1/6] 清理环境..."
pkill -f "python.*server" 2>/dev/null
lsof -ti:8000 | xargs kill -9 2>/dev/null
rm -f labeling.db
rm -rf uploads exports
sleep 2

# 创建测试图片
echo "[2/6] 创建测试图片..."
python << 'PYEOF'
from PIL import Image, ImageDraw
import os

os.makedirs('test_data', exist_ok=True)
for i in range(3):
    img = Image.new('RGB', (800, 600), 'white')
    draw = ImageDraw.Draw(img)
    draw.rectangle([100 + i*50, 100, 300 + i*50, 300], outline='red', width=3)
    draw.rectangle([400, 200 + i*30, 600, 400 + i*30], outline='blue', width=3)
    img.save(f'test_data/test_{i}.jpg')
print("✓ 3个测试图片已创建")
PYEOF

# 后台启动服务器
echo "[3/6] 启动服务器..."
nohup python server_fixed.py > server.log 2>&1 &
SERVER_PID=$!
echo "服务器PID: $SERVER_PID"

# 等待启动
echo "[4/6] 等待服务器启动..."
for i in {1..10}; do
    if curl -s http://localhost:8000/ > /dev/null 2>&1; then
        echo "✓ 服务器启动成功"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# 运行完整测试
echo "[5/6] 运行API测试..."
python << 'PYEOF'
import requests
import json
import time

BASE = "http://localhost:8000"
results = {"pass": 0, "fail": 0, "total": 0}

def test(name, func):
    results["total"] += 1
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

print("\n开始测试...")

# 1. 根路径
test("根路径", lambda: requests.get(f"{BASE}/").status_code == 200)

# 2. 创建项目
project_id = None
def create_project():
    global project_id
    r = requests.post(f"{BASE}/api/projects", json={"name": "测试项目", "type": "image"})
    if r.status_code == 200:
        project_id = r.json()["id"]
        return True
    return False
test("创建项目", create_project)

if not project_id:
    print("无法创建项目，停止测试")
    exit(1)

# 3. 上传任务
task_ids = []
def upload_tasks():
    global task_ids
    for i in range(2):
        with open(f"test_data/test_{i}.jpg", "rb") as f:
            r = requests.post(f"{BASE}/api/projects/{project_id}/tasks", files={"file": f})
            if r.status_code == 200:
                task_ids.append(r.json()["id"])
    return len(task_ids) == 2
test("上传任务", upload_tasks)

# 4. 自动标注
def auto_label():
    if not task_ids:
        return False
    r = requests.post(f"{BASE}/api/tasks/{task_ids[0]}/auto-label")
    return r.status_code == 200
test("自动标注", auto_label)

# 5. 添加标注
def add_label():
    if not task_ids:
        return False
    data = {
        "task_id": task_ids[0],
        "label_type": "rectangle",
        "label_data": {"labels": [{"type": "rectangle", "label": "car", "bbox": [100,100,200,200]}]}
    }
    r = requests.post(f"{BASE}/api/labels?user_id=user1", json=data)
    return r.status_code == 200
test("添加标注", add_label)

# 6. 提交审核
def submit_review():
    if not task_ids:
        return False
    data = {"task_id": task_ids[0], "status": "approved"}
    r = requests.post(f"{BASE}/api/reviews?reviewer_id=reviewer1", json=data)
    return r.status_code == 200
test("提交审核", submit_review)

# 7. 质量检查
def quality_check():
    if not task_ids:
        return False
    r = requests.get(f"{BASE}/api/quality/task/{task_ids[0]}")
    return r.status_code == 200
test("质量检查", quality_check)

# 8. 项目进度
def project_progress():
    r = requests.get(f"{BASE}/api/projects/{project_id}/progress")
    return r.status_code == 200
test("项目进度", project_progress)

# 9. 项目统计
def project_stats():
    r = requests.get(f"{BASE}/api/projects/{project_id}/statistics")
    if r.status_code == 200:
        stats = r.json()
        print(f"    总任务: {stats['total_tasks']}, 完成率: {stats['progress_rate']}%")
        return True
    return False
test("项目统计", project_stats)

# 10. 主动学习
def active_learning():
    r = requests.post(f"{BASE}/api/projects/{project_id}/select-valuable")
    if r.status_code == 200:
        data = r.json()
        print(f"    节省: {data['estimated_savings']}")
        return True
    return False
test("主动学习", active_learning)

# 11. 导出数据
def export_data():
    r = requests.post(f"{BASE}/api/projects/{project_id}/export?format=coco")
    if r.status_code == 200:
        print(f"    导出: {r.json()['output_path']}")
        return True
    return False
test("导出数据", export_data)

# 12. 获取项目列表
def list_projects():
    r = requests.get(f"{BASE}/api/projects")
    return r.status_code == 200
test("项目列表", list_projects)

print(f"\n{'='*50}")
print(f"测试结果: {results['pass']}/{results['total']} 通过")
print(f"{'='*50}")

if results['fail'] == 0:
    print("\n🎉 所有测试通过！")
else:
    print(f"\n⚠️ {results['fail']} 个测试失败")

exit(0 if results['fail'] == 0 else 1)
PYEOF

TEST_RESULT=$?

# 显示服务器日志
echo ""
echo "[6/6] 服务器日志（最后10行）:"
tail -10 server.log

# 清理或保持运行
echo ""
echo "========================================="
if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ 测试全部通过！"
else
    echo "❌ 部分测试失败"
fi
echo "========================================="
echo "服务器PID: $SERVER_PID"
echo "API文档: http://localhost:8000/docs"
echo ""
echo "是否停止服务器？(y/n)"
read -t 10 -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kill $SERVER_PID 2>/dev/null
    lsof -ti:8000 | xargs kill -9 2>/dev/null
    echo "✓ 服务器已停止"
else
    echo "✓ 服务器继续运行"
    echo "查看日志: tail -f server.log"
    echo "停止服务: kill $SERVER_PID"
fi

exit $TEST_RESULT
