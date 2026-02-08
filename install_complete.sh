#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Video Pipeline 설치 (Native + Docker)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# 1. 시스템 요구사항 확인
echo -e "${YELLOW}[1/12] 시스템 요구사항 확인 중...${NC}"

if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}오류: NVIDIA GPU 드라이버가 설치되지 않았습니다.${NC}"
    exit 1
fi

echo "GPU 확인 완료:"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

total_mem=$(free -g | awk '/^Mem:/{print $2}')
if [ "$total_mem" -lt 14 ]; then
    echo -e "${YELLOW}경고: RAM이 16GB 미만입니다. (현재: ${total_mem}GB)${NC}"
fi

# 2. 시스템 패키지 설치
echo -e "\n${YELLOW}[2/12] 시스템 패키지 설치 중...${NC}"

sudo apt-get update
sudo apt-get install -y \
    python3 \
    python3-venv \
    python3-pip \
    git \
    curl \
    wget \
    jq \
    ffmpeg \
    postgresql-client

# 3. Docker 설치
echo -e "\n${YELLOW}[3/12] Docker 설치 중...${NC}"

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    DOCKER_INSTALLED=true
else
    echo "Docker가 이미 설치되어 있습니다."
    DOCKER_INSTALLED=false
fi

if ! groups $USER | grep -q docker; then
    sudo usermod -aG docker $USER
    DOCKER_GROUP_ADDED=true
else
    DOCKER_GROUP_ADDED=false
fi

# 4. Docker Compose 설치
echo -e "\n${YELLOW}[4/12] Docker Compose 설치 중...${NC}"

if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# 5. NVIDIA Container Toolkit 설치
echo -e "\n${YELLOW}[5/12] NVIDIA Container Toolkit 설치 중...${NC}"

sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list 2>/dev/null
sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null

if ! dpkg -l | grep -q nvidia-container-toolkit; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
fi

# 6. 프로젝트 디렉토리 생성
echo -e "\n${YELLOW}[6/12] 프로젝트 디렉토리 생성 중...${NC}"

PROJECT_DIR="$HOME/video-pipeline"
mkdir -p "$PROJECT_DIR"/{models/{checkpoints,vae,loras},shared/{audio,images,videos,final,temp},scripts,services,postgres-data,n8n,ollama-data,whisper-models,rss-bridge}

cd "$PROJECT_DIR"

# 7. 환경 변수 파일 생성
echo -e "\n${YELLOW}[7/12] 환경 변수 설정 중...${NC}"

cat > .env << 'ENVEOF'
# n8n 설정
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=video2024!

# PostgreSQL 설정
POSTGRES_USER=n8n
POSTGRES_PASSWORD=n8n123
POSTGRES_DB=video_pipeline

# 시간대
TZ=Asia/Seoul
ENVEOF

# 8. Docker Compose 파일 생성
echo -e "\n${YELLOW}[8/12] Docker Compose 설정 생성 중...${NC}"

cat > docker-compose.yml << 'DOCKEREOF'
networks:
  pipeline:
    driver: bridge

services:
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=${TZ}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - pipeline
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  adminer:
    image: adminer:latest
    container_name: adminer
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - ADMINER_DEFAULT_SERVER=postgres
    networks:
      - pipeline
    depends_on:
      - postgres

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_HOST=0.0.0.0
      - WEBHOOK_URL=http://localhost:5678
      - GENERIC_TIMEZONE=${TZ}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ./n8n:/home/node/.n8n
      - ./shared:/shared
      - ./scripts:/scripts
    networks:
      - pipeline
    depends_on:
      postgres:
        condition: service_healthy

  rss-bridge:
    image: rssbridge/rss-bridge:latest
    container_name: rss-bridge
    restart: unless-stopped
    ports:
      - "3001:80"
    volumes:
      - ./rss-bridge:/config
    networks:
      - pipeline

  whisper:
    image: onerahmet/openai-whisper-asr-webservice:latest
    container_name: whisper
    restart: unless-stopped
    ports:
      - "9000:9000"
    environment:
      - ASR_MODEL=medium
      - ASR_ENGINE=faster_whisper
    volumes:
      - ./whisper-models:/root/.cache/whisper
      - ./shared:/shared
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    networks:
      - pipeline
DOCKEREOF

# 9. 데이터베이스 초기화
echo -e "\n${YELLOW}[9/12] 데이터베이스 스키마 생성 중...${NC}"

cat > init-db.sql << 'SQLEOF'
CREATE TABLE IF NOT EXISTS content_plan (
    id SERIAL PRIMARY KEY,
    target_age VARCHAR(50),
    keyword VARCHAR(200) NOT NULL,
    format VARCHAR(20) DEFAULT 'shorts',
    voice_tone VARCHAR(50) DEFAULT 'professional',
    status VARCHAR(50) DEFAULT 'planning',
    title TEXT,
    description TEXT,
    script TEXT,
    tags TEXT[],
    category VARCHAR(100),
    audio_url TEXT,
    video_url TEXT,
    youtube_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS scenes (
    id SERIAL PRIMARY KEY,
    content_id INTEGER REFERENCES content_plan(id) ON DELETE CASCADE,
    scene_number INTEGER NOT NULL,
    start_time FLOAT,
    end_time FLOAT,
    text TEXT,
    image_prompt TEXT,
    image_url TEXT,
    video_url TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS topic_templates (
    id SERIAL PRIMARY KEY,
    category VARCHAR(100) NOT NULL,
    template TEXT NOT NULL,
    target_age VARCHAR(50),
    tags TEXT[],
    weight INTEGER DEFAULT 1,
    last_used TIMESTAMP,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rss_sources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    url TEXT NOT NULL,
    category VARCHAR(100),
    enabled BOOLEAN DEFAULT true,
    last_fetched TIMESTAMP,
    fetch_interval INTEGER DEFAULT 3600,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_content_status ON content_plan(status);
CREATE INDEX idx_scenes_content ON scenes(content_id);
CREATE INDEX idx_rss_enabled ON rss_sources(enabled);

INSERT INTO topic_templates (category, template, target_age, tags, weight) VALUES
('기술', '2025년 주목해야 할 AI 기술 트렌드', '20-40대', ARRAY['AI', '기술'], 3),
('생활', '바쁜 직장인을 위한 아침 루틴', '20-30대', ARRAY['생산성', '라이프'], 5),
('건강', '겨울철 면역력 높이는 방법', '전연령', ARRAY['건강', '웰빙'], 3),
('재테크', '2025년 주목할 투자 트렌드', '30-40대', ARRAY['재테크', '투자'], 2);

INSERT INTO content_plan (target_age, keyword, format, voice_tone, status, category) VALUES
('20-30대', 'AI 도구로 업무 효율 2배 높이기', 'shorts', 'professional', 'planning', '기술'),
('전연령', '겨울 감기 예방 필수 팁 5가지', 'shorts', 'friendly', 'planning', '건강');

INSERT INTO rss_sources (name, url, category, enabled) VALUES
('TechCrunch', 'https://techcrunch.com/feed/', '기술', true),
('Hacker News', 'https://news.ycombinator.com/rss', '기술', true),
('The Verge', 'https://www.theverge.com/rss/index.xml', '기술', true);

CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_content_plan_modtime
    BEFORE UPDATE ON content_plan
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_column();
SQLEOF

# 10. ComfyUI 설치
echo -e "\n${YELLOW}[10/12] ComfyUI 설치 중...${NC}"

COMFYUI_DIR="$PROJECT_DIR/comfyui-standalone"

if [ ! -d "$COMFYUI_DIR" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
    cd "$COMFYUI_DIR"
    
    python3 -m venv venv
    source venv/bin/activate
    
    pip install --upgrade pip
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
    pip install -r requirements.txt
    
    # 모델 디렉토리 연결
    rm -rf models/checkpoints models/vae models/loras
    ln -sf "$PROJECT_DIR/models/checkpoints" models/checkpoints
    ln -sf "$PROJECT_DIR/models/vae" models/vae
    ln -sf "$PROJECT_DIR/models/loras" models/loras
    ln -sf "$PROJECT_DIR/shared/images" output
    
    deactivate
    echo -e "${GREEN}✅ ComfyUI 설치 완료${NC}"
else
    echo "ComfyUI가 이미 설치되어 있습니다."
fi

cd "$PROJECT_DIR"

# 11. Ollama 설치
echo -e "\n${YELLOW}[11/12] Ollama 설치 중...${NC}"

if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Ollama 환경 변수 설정
if ! grep -q "OLLAMA_HOST" /etc/environment; then
    echo 'OLLAMA_HOST=0.0.0.0:11434' | sudo tee -a /etc/environment
fi

# 12. Python 스크립트 생성
echo -e "\n${YELLOW}[12/12] 작업 스크립트 생성 중...${NC}"

pip3 install psycopg2-binary requests feedparser --break-system-packages 2>/dev/null || pip3 install psycopg2-binary requests feedparser

# topic_manager.py
cat > scripts/topic_manager.py << 'PYEOF'
#!/usr/bin/env python3
import psycopg2
import sys
from datetime import datetime
import random

DB_CONFIG = {
    'host': 'localhost',
    'database': 'video_pipeline',
    'user': 'n8n',
    'password': 'n8n123',
    'port': 5432
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def list_topics(status='all'):
    conn = get_connection()
    cur = conn.cursor()
    
    if status == 'all':
        cur.execute("SELECT id, keyword, target_age, status, category, created_at FROM content_plan ORDER BY created_at DESC LIMIT 20")
    else:
        cur.execute("SELECT id, keyword, target_age, status, category, created_at FROM content_plan WHERE status = %s ORDER BY created_at DESC", (status,))
    
    rows = cur.fetchall()
    conn.close()
    
    print(f"\n{'ID':<5} {'주제':<40} {'연령':<10} {'상태':<12} {'카테고리':<10}")
    print("-" * 80)
    for row in rows:
        print(f"{row[0]:<5} {row[1]:<40} {row[2]:<10} {row[3]:<12} {row[4] or 'N/A':<10}")
    print(f"\n총 {len(rows)}개 주제")

def generate_from_template():
    conn = get_connection()
    cur = conn.cursor()
    
    cur.execute("""
        SELECT id, template, target_age, category
        FROM topic_templates
        WHERE enabled = true AND (last_used IS NULL OR last_used < NOW() - INTERVAL '7 days')
        ORDER BY RANDOM() * weight DESC LIMIT 1
    """)
    
    template = cur.fetchone()
    if not template:
        print("사용 가능한 템플릿이 없습니다.")
        conn.close()
        return
    
    template_id, text, age, category = template
    filled = text
    
    cur.execute("""
        INSERT INTO content_plan (keyword, target_age, format, voice_tone, status, category)
        VALUES (%s, %s, 'shorts', 'professional', 'planning', %s)
        RETURNING id
    """, (filled, age, category))
    
    new_id = cur.fetchone()[0]
    cur.execute("UPDATE topic_templates SET last_used = NOW() WHERE id = %s", (template_id,))
    
    conn.commit()
    conn.close()
    
    print(f"\n✅ 새 주제 생성 (ID: {new_id}): {filled}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python3 topic_manager.py [list|generate]")
        sys.exit(1)
    
    if sys.argv[1] == 'list':
        status = sys.argv[2] if len(sys.argv) > 2 else 'all'
        list_topics(status)
    elif sys.argv[1] == 'generate':
        generate_from_template()
PYEOF

# rss_fetcher.py
cat > scripts/rss_fetcher.py << 'PYEOF'
#!/usr/bin/env python3
import feedparser
import psycopg2
import sys
from datetime import datetime

DB_CONFIG = {
    'host': 'localhost',
    'database': 'video_pipeline',
    'user': 'n8n',
    'password': 'n8n123',
    'port': 5432
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

def fetch_rss_feeds():
    conn = get_connection()
    cur = conn.cursor()
    
    cur.execute("SELECT id, name, url, category FROM rss_sources WHERE enabled = true")
    sources = cur.fetchall()
    
    new_topics = 0
    for source_id, name, url, category in sources:
        print(f"📡 Fetching: {name}")
        try:
            feed = feedparser.parse(url)
            
            for entry in feed.entries[:5]:  # 최근 5개만
                title = entry.title
                
                # 중복 확인
                cur.execute("SELECT id FROM content_plan WHERE keyword = %s", (title,))
                if cur.fetchone():
                    continue
                
                cur.execute("""
                    INSERT INTO content_plan (keyword, target_age, format, voice_tone, status, category)
                    VALUES (%s, '전연령', 'shorts', 'professional', 'planning', %s)
                """, (title, category))
                new_topics += 1
            
            cur.execute("UPDATE rss_sources SET last_fetched = NOW() WHERE id = %s", (source_id,))
        except Exception as e:
            print(f"  ⚠️  오류: {e}")
    
    conn.commit()
    conn.close()
    print(f"\n✅ {new_topics}개 새 주제 추가됨")

if __name__ == "__main__":
    fetch_rss_feeds()
PYEOF

chmod +x scripts/*.py

# 서비스 관리 스크립트
cat > services/start_comfyui.sh << 'COMFYEOF'
#!/bin/bash
cd ~/video-pipeline/comfyui-standalone
source venv/bin/activate
echo "🎨 ComfyUI 시작: http://$(hostname -I | awk '{print $1}'):8188"
python main.py --listen 0.0.0.0 --port 8188
COMFYEOF

cat > services/stop_comfyui.sh << 'STOPEOF'
#!/bin/bash
pkill -f "python main.py.*8188"
echo "✅ ComfyUI 중지"
STOPEOF

cat > services/start_ollama.sh << 'OLLAMAEOF'
#!/bin/bash
export OLLAMA_HOST=0.0.0.0:11434
ollama serve > ~/video-pipeline/ollama.log 2>&1 &
echo "✅ Ollama 시작: http://localhost:11434"
OLLAMAEOF

cat > services/stop_ollama.sh << 'STOPOLLEOF'
#!/bin/bash
pkill ollama
echo "✅ Ollama 중지"
STOPOLLEOF

chmod +x services/*.sh

# 통합 관리 스크립트
cat > manage.sh << 'MANAGEEOF'
#!/bin/bash

PROJECT_DIR="$HOME/video-pipeline"
cd "$PROJECT_DIR"

show_menu() {
    echo ""
    echo "========================================="
    echo "    Video Pipeline 관리 도구"
    echo "========================================="
    echo ""
    echo "=== Docker 서비스 ==="
    echo "1. Docker 서비스 시작 (PostgreSQL, n8n, Adminer, RSS)"
    echo "2. Docker 서비스 중지"
    echo "3. Docker 서비스 상태"
    echo ""
    echo "=== AI 서비스 (Native) ==="
    echo "4. ComfyUI 시작"
    echo "5. ComfyUI 중지"
    echo "6. Ollama 시작"
    echo "7. Ollama 중지"
    echo "8. Whisper 시작"
    echo "9. Whisper 중지"
    echo "10. 모든 AI 서비스 상태"
    echo ""
    echo "=== 주제 관리 ==="
    echo "11. 주제 목록 보기"
    echo "12. 새 주제 생성"
    echo "13. RSS 피드 가져오기"
    echo "14. 데이터베이스 접속"
    echo ""
    echo "=== 시스템 ==="
    echo "15. 전체 시스템 시작"
    echo "16. 전체 시스템 중지"
    echo "17. GPU 상태 확인"
    echo "18. 디스크 사용량"
    echo "19. 서비스 로그 보기"
    echo ""
    echo "0. 종료"
    echo ""
    echo -n "선택: "
}

start_docker() {
    echo "🐳 Docker 서비스 시작 중..."
    docker-compose up -d postgres adminer n8n rss-bridge
    sleep 2
    echo "✅ 완료"
    echo ""
    echo "접속 정보:"
    echo "  📊 n8n:        http://localhost:5678"
    echo "  🗄️  Adminer:   http://localhost:8080"
    echo "  📡 RSS Bridge: http://localhost:3001"
    echo ""
    echo "Adminer 로그인 정보:"
    echo "  시스템: PostgreSQL"
    echo "  서버: postgres"
    echo "  사용자: n8n"
    echo "  비밀번호: n8n123"
    echo "  데이터베이스: video_pipeline"
}

stop_docker() {
    echo "🛑 Docker 서비스 중지 중..."
    docker-compose down
    echo "✅ Docker 서비스 중지 완료"
}

start_comfyui() {
    if ps aux | grep "python main.py.*8188" | grep -v grep > /dev/null; then
        echo "⚠️  ComfyUI가 이미 실행 중"
        echo "   PID: $(pgrep -f 'python main.py.*8188')"
        echo "   http://$(hostname -I | awk '{print $1}'):8188"
    else
        echo "🎨 ComfyUI 시작 중..."
        nohup ./services/start_comfyui.sh > comfyui.log 2>&1 &
        sleep 3
        if ps aux | grep "python main.py.*8188" | grep -v grep > /dev/null; then
            echo "✅ ComfyUI 시작 성공: http://$(hostname -I | awk '{print $1}'):8188"
        else
            echo "❌ ComfyUI 시작 실패. 로그를 확인하세요: tail -f comfyui.log"
        fi
    fi
}

stop_comfyui() {
    ./services/stop_comfyui.sh
}

start_ollama() {
    if pgrep ollama > /dev/null; then
        echo "⚠️  Ollama가 이미 실행 중"
        echo "   PID: $(pgrep ollama)"
        echo "   http://localhost:11434"
    else
        echo "🤖 Ollama 시작 중..."
        ./services/start_ollama.sh
        sleep 2
        if pgrep ollama > /dev/null; then
            echo "✅ Ollama 시작 성공: http://localhost:11434"
        else
            echo "❌ Ollama 시작 실패. 로그를 확인하세요: tail -f ollama.log"
        fi
    fi
}

stop_ollama() {
    ./services/stop_ollama.sh
}

start_whisper() {
    echo "🎤 Whisper 시작 중..."
    docker-compose up -d whisper
    sleep 2
    if docker ps | grep whisper > /dev/null; then
        echo "✅ Whisper 시작 성공: http://localhost:9000"
    else
        echo "❌ Whisper 시작 실패. 로그를 확인하세요: docker-compose logs whisper"
    fi
}

stop_whisper() {
    docker-compose stop whisper
    echo "✅ Whisper 중지"
}

check_services() {
    echo "=== 서비스 상태 ==="
    echo ""
    echo "📦 Docker 서비스:"
    docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    echo "🖥️  Native 서비스:"
    echo ""
    echo "ComfyUI:"
    if ps aux | grep "python main.py.*8188" | grep -v grep > /dev/null; then
        echo "  ✅ 실행 중 (PID: $(pgrep -f 'python main.py.*8188'))"
        echo "     http://$(hostname -I | awk '{print $1}'):8188"
    else
        echo "  ❌ 중지됨"
    fi
    echo ""
    
    echo "Ollama:"
    if pgrep ollama > /dev/null; then
        echo "  ✅ 실행 중 (PID: $(pgrep ollama))"
        echo "     http://localhost:11434"
    else
        echo "  ❌ 중지됨"
    fi
}

view_logs() {
    echo ""
    echo "어떤 서비스의 로그를 보시겠습니까?"
    echo "1. PostgreSQL"
    echo "2. n8n"
    echo "3. Adminer"
    echo "4. RSS Bridge"
    echo "5. Whisper"
    echo "6. ComfyUI"
    echo "7. Ollama"
    echo "8. 모든 Docker 서비스"
    echo ""
    echo -n "선택: "
    read log_choice
    
    case $log_choice in
        1) docker-compose logs -f postgres ;;
        2) docker-compose logs -f n8n ;;
        3) docker-compose logs -f adminer ;;
        4) docker-compose logs -f rss-bridge ;;
        5) docker-compose logs -f whisper ;;
        6) tail -f comfyui.log ;;
        7) tail -f ollama.log ;;
        8) docker-compose logs -f ;;
        *) echo "❌ 잘못된 선택" ;;
    esac
}

start_all() {
    echo "🚀 전체 시스템 시작 중..."
    echo ""
    start_docker
    sleep 3
    start_comfyui
    start_ollama
    echo ""
    echo "✅ 모든 서비스 시작 완료!"
    echo ""
    check_services
}

stop_all() {
    echo "🛑 전체 시스템 중지 중..."
    stop_comfyui
    stop_ollama
    stop_whisper
    stop_docker
    echo "✅ 모든 서비스 중지 완료"
}

while true; do
    show_menu
    read choice
    
    case $choice in
        1) start_docker ;;
        2) stop_docker ;;
        3) docker-compose ps ;;
        4) start_comfyui ;;
        5) stop_comfyui ;;
        6) start_ollama ;;
        7) stop_ollama ;;
        8) start_whisper ;;
        9) stop_whisper ;;
        10) check_services ;;
        11) python3 scripts/topic_manager.py list ;;
        12) python3 scripts/topic_manager.py generate ;;
        13) python3 scripts/rss_fetcher.py ;;
        14) docker exec -it postgres psql -U n8n -d video_pipeline ;;
        15) start_all ;;
        16) stop_all ;;
        17) nvidia-smi ;;
        18) du -sh * | sort -h ;;
        19) view_logs ;;
        0) exit 0 ;;
        *) echo "❌ 잘못된 선택" ;;
    esac
    
    echo ""
    read -p "Enter를 눌러 계속..."
done
MANAGEEOF

chmod +x manage.sh

# 빠른 시작 가이드 생성
cat > README.md << 'READMEEOF'
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
READMEEOF

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}설치 완료!${NC}"
echo -e "${GREEN}========================================${NC}\n"

if [ "$DOCKER_INSTALLED" = true ] || [ "$DOCKER_GROUP_ADDED" = true ]; then
    echo -e "${YELLOW}⚠️  Docker 권한 설정을 위해 재로그인이 필요합니다.${NC}"
    echo ""
    echo "다음 중 하나를 실행하세요:"
    echo "  1. 로그아웃 후 다시 로그인 (권장)"
    echo "  2. newgrp docker (임시)"
    echo ""
fi

echo "설치 위치: $PROJECT_DIR"
echo ""
echo "시작 방법:"
echo "  cd $PROJECT_DIR"
echo "  ./manage.sh"
echo ""
echo "주요 서비스:"
echo "  - ComfyUI: Native 설치 (포트 8188)"
echo "  - Ollama: Native 설치 (포트 11434)"
echo "  - PostgreSQL: Docker (포트 5432)"
echo "  - n8n: Docker (포트 5678)"
echo "  - Adminer: Docker (포트 8080)"
echo "  - RSS Bridge: Docker (포트 3001)"
echo "  - Whisper: Docker (포트 9000) - 선택적"
echo ""
echo "자세한 사용법: cat $PROJECT_DIR/README.md"
echo ""

