#!/bin/bash
cd ~/video-pipeline/comfyui-standalone
source venv/bin/activate
echo "🎨 ComfyUI 시작: http://$(hostname -I | awk '{print $1}'):8188"
python main.py --listen 0.0.0.0 --port 8188
