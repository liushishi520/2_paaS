#!/bin/bash
echo "Fixing dependencies..."

# 安装缺失的langchain组件
pip install langchain langchain-community langchain-core

# 安装其他可能缺失的包
pip install chromadb sentence-transformers scikit-learn

# 验证安装
python -c "from langchain.text_splitter import RecursiveCharacterTextSplitter; print('✅ langchain installed')"
python -c "import chromadb; print('✅ chromadb installed')"
python -c "from sentence_transformers import SentenceTransformer; print('✅ sentence-transformers installed')"

echo "Done!"
