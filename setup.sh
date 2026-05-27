#!/bin/bash
set -e

CONF_SRC="$(cd "$(dirname "$0")/nginx/conf.d" && pwd)"
CONF_DST="/etc/nginx/conf.d"
HTML_SRC="$(cd "$(dirname "$0")/nginx/html" && pwd)"
HTML_DST="/etc/nginx/html"

# nginx 설치 (없을 경우)
if ! command -v nginx &>/dev/null; then
    echo "[1/4] nginx 설치 중..."
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y nginx
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y nginx
    else
        echo "지원하지 않는 패키지 매니저입니다. nginx를 수동으로 설치하세요."
        exit 1
    fi
else
    echo "[1/4] nginx 이미 설치됨 ($(nginx -v 2>&1))"
fi

# conf 동기화
# SSL 인증서가 이미 발급된 경우 certbot이 수정한 conf를 덮어쓰지 않음
if [ -d "/etc/letsencrypt/live" ] && sudo ls /etc/letsencrypt/live/ 2>/dev/null | grep -q .; then
    echo "[2/4] SSL 인증서 감지됨 — conf 동기화 건너뜀 (ssl_setup.sh가 관리)"
    echo "      nginx conf 변경이 필요하면 /etc/nginx/conf.d/ 를 직접 수정하세요."
else
    echo "[2/4] conf 동기화: $CONF_SRC → $CONF_DST"
    sudo rsync -av --delete "$CONF_SRC/" "$CONF_DST/"
    sudo mkdir -p "$HTML_DST"
    sudo rsync -av --delete "$HTML_SRC/" "$HTML_DST/"
fi

# 설정 검증
echo "[3/4] nginx 설정 검증..."
sudo nginx -t

# 부팅 시 자동 시작 + 실행/리로드
echo "[4/4] nginx 활성화 및 시작..."
sudo systemctl enable nginx

if sudo systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
    echo "nginx 리로드 완료"
else
    sudo systemctl start nginx
    echo "nginx 시작 완료"
fi

echo ""
echo "완료. 상태 확인:"
sudo systemctl status nginx --no-pager -l
