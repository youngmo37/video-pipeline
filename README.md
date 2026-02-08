# Video Pipeline 시스템

## 빠른 시작

### 1. 전체 시스템 시작
```bash
cd ~/video-pipeline
./manage.sh
# 메뉴에서 15번 선택
```

### 2. 주요 서비스 접속 정보

#### Docker 서비스
- **n8n**: http://localhost:5678
  - 사용자: admin
  - 비밀번호: video2024!

- **Adminer**: http://localhost:8080
  - 시스템: PostgreSQL
  - 서버: postgres
  - 사용자: n8n
  - 비밀번호: n8n123
  - 데이터베이스: video_pipeline

- **RSS Bridge**: http://localhost:3001

#### Native 서비스
- **ComfyUI**: http://[서버IP]:8188
- **Ollama**: http://localhost:11434
- **Whisper**: http://localhost:9000 (선택적)

### 3. 주요 명령어

#### 서비스 관리
```bash
# 전체 시작
./manage.sh  # 15번 선택

# 전체 중지
./manage.sh  # 16번 선택

# 상태 확인
./manage.sh  # 3번, 10번 선택
```

#### 주제 관리
```bash
# 주제 목록
python3 scripts/topic_manager.py list

# 새 주제 생성
python3 scripts/topic_manager.py generate

# RSS 피드 가져오기
python3 scripts/rss_fetcher.py
```

#### 로그 확인
```bash
# ComfyUI 로그
tail -f ~/video-pipeline/comfyui.log

# Ollama 로그
tail -f ~/video-pipeline/ollama.log

# Docker 서비스 로그
docker-compose logs -f [서비스명]
```

### 4. 문제 해결

#### Docker 권한 오류
```bash
newgrp docker
# 또는 재로그인
```

#### 서비스가 시작되지 않는 경우
```bash
# 로그 확인
./manage.sh  # 19번 선택

# 개별 서비스 재시작
docker-compose restart [서비스명]
```

#### GPU 확인
```bash
nvidia-smi
```

### 5. 디렉토리 구조
```
video-pipeline/
├── comfyui-standalone/    # ComfyUI (Native)
├── models/                # AI 모델
├── scripts/              # Python 스크립트
├── services/             # 서비스 관리 스크립트
├── shared/               # 공유 데이터
├── manage.sh            # 통합 관리 도구
└── docker-compose.yml   # Docker 설정
```

## systemd 서비스 등록 (자동 시작)

ComfyUI와 Ollama를 시스템 시작 시 자동으로 실행하려면:

```bash
# ComfyUI 서비스
sudo tee /etc/systemd/system/comfyui.service << 'EOF'
[Unit]
Description=ComfyUI
After=network.target

[Service]
Type=simple
User=ymim
WorkingDirectory=/home/ymim/video-pipeline/comfyui-standalone
Environment=PATH=/home/ymim/video-pipeline/comfyui-standalone/venv/bin
ExecStart=/home/ymim/video-pipeline/comfyui-standalone/venv/bin/python main.py --listen 0.0.0.0 --port 8188
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Ollama 서비스
sudo tee /etc/systemd/system/ollama-serve.service << 'EOF'
[Unit]
Description=Ollama Service
After=network.target

[Service]
Type=simple
User=ymim
Environment=OLLAMA_HOST=0.0.0.0:11434
ExecStart=/usr/local/bin/ollama serve
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 서비스 활성화
sudo systemctl daemon-reload
sudo systemctl enable comfyui ollama-serve
sudo systemctl start comfyui ollama-serve
```
