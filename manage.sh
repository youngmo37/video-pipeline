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
