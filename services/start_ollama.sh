#!/bin/bash
export OLLAMA_HOST=0.0.0.0:11434
ollama serve > ~/video-pipeline/ollama.log 2>&1 &
echo "✅ Ollama 시작: http://localhost:11434"
