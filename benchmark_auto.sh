#!/bin/bash

echo "========================================="
echo "Performance Benchmark"
echo "========================================="

PORT=8000

# 确保服务在运行
if ! curl -s http://localhost:$PORT/health > /dev/null 2>&1; then
    echo "Service not running. Starting service..."
    nohup python embedding_service.py > service.log 2>&1 &
    sleep 10
fi

echo -e "\nRunning performance benchmarks...\n"

# 不同批次大小的性能测试
python3 << 'PYEOF'
import requests
import time
import statistics
import numpy as np

def benchmark_batch_size(batch_size, num_iterations=20):
    """测试特定批次大小的性能"""
    texts = [f"Benchmark text {i} for performance testing" for i in range(batch_size)]
    
    latencies = []
    
    # 预热
    for _ in range(3):
        requests.post("http://localhost:8000/v1/embeddings", json={"texts": texts[:8]})
    
    # 正式测试
    for _ in range(num_iterations):
        start = time.time()
        response = requests.post("http://localhost:8000/v1/embeddings", json={"texts": texts})
        elapsed = time.time() - start
        latencies.append(elapsed)
    
    avg_latency = statistics.mean(latencies) * 1000
    p95_latency = np.percentile(latencies, 95) * 1000
    throughput = batch_size / statistics.mean(latencies)
    
    return {
        'batch_size': batch_size,
        'avg_latency_ms': avg_latency,
        'p95_latency_ms': p95_latency,
        'throughput_rps': throughput
    }

print("=" * 60)
print("Batch Size Performance Report")
print("=" * 60)
print(f"{'Batch':<10} {'Avg Latency(ms)':<20} {'P95 Latency(ms)':<20} {'Throughput(rps)':<20}")
print("-" * 70)

batch_sizes = [1, 4, 8, 16, 32, 64]

for batch_size in batch_sizes:
    try:
        result = benchmark_batch_size(batch_size)
        print(f"{result['batch_size']:<10} "
              f"{result['avg_latency_ms']:<20.2f} "
              f"{result['p95_latency_ms']:<20.2f} "
              f"{result['throughput_rps']:<20.2f}")
    except Exception as e:
        print(f"{batch_size:<10} {'ERROR':<20} {'ERROR':<20} {'ERROR':<20}")

print("=" * 60)

# 缓存命中率测试
print("\n" + "=" * 60)
print("Cache Hit Rate Test")
print("=" * 60)

texts = [f"Unique text {i}" for i in range(100)]
cache_hits = 0
total_requests = 200

for i in range(total_requests):
    # 重复使用前20个文本
    text_idx = i % 20
    response = requests.post("http://localhost:8000/v1/embeddings", 
                            json={"texts": [texts[text_idx]]})
    if response.status_code == 200:
        data = response.json()
        # 简化：假设第二次请求相同文本会命中缓存
        if i >= 100:  # 经过一轮后应该有缓存
            cache_hits += 1

hit_rate = (cache_hits / total_requests) * 100
print(f"Estimated cache hit rate: {hit_rate:.1f}%")

# 获取实际统计
stats = requests.get("http://localhost:8000/v1/stats").json()
print(f"Actual cache stats: {stats['cache']}")

print("=" * 60)

# 内存使用估计
print("\n" + "=" * 60)
print("Memory Usage Estimation")
print("=" * 60)

import psutil
import os

process = psutil.Process(os.getpid())
memory_mb = process.memory_info().rss / 1024 / 1024
print(f"Current process memory: {memory_mb:.2f} MB")

# 估算100万向量的内存
embedding_dim = 768
bytes_per_float = 4
vectors_1m_memory = 1_000_000 * embedding_dim * bytes_per_float / 1024 / 1024
print(f"Estimated memory for 1M vectors (dim={embedding_dim}): {vectors_1m_memory:.2f} MB")
print(f"With overhead (~20%): {vectors_1m_memory * 1.2:.2f} MB")

PYEOF

echo ""
echo "Benchmark completed!"
