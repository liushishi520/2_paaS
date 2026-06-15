#!/bin/bash
mkdir -p modules/{recorder,agent,player,editor,utils}
mkdir -p recordings/{screenshots,scripts,videos}
mkdir -p logs
touch modules/__init__.py
touch modules/recorder/__init__.py
touch modules/agent/__init__.py
touch modules/player/__init__.py
touch modules/editor/__init__.py
touch modules/utils/__init__.py
chmod +x setup_structure.sh
