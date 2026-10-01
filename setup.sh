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
#
# certbot --nginx 는 /etc/nginx/conf.d/ 의 conf 를 직접 수정한다(443 블록·리다이렉트 추가).
# 따라서 repo 로 "기존" conf 를 덮으면 certbot 이 만든 HTTPS 설정이 날아간다.
# → repo 에 있고 서버엔 없는 "새" conf 만 배포하고, 기존 conf 는 건드리지 않는다.
#   (새 도메인 추가가 기존 도메인 설정을 깨지 않도록. 기존 conf 수정이 필요하면
#    /etc/nginx/conf.d/ 를 직접 편집 후 reload.)
echo "[2/4] conf 동기화 (새 파일만 추가, 기존 certbot 관리 conf 는 보존)"
sudo mkdir -p "$CONF_DST" "$HTML_DST"

new_confs=0
for src in "$CONF_SRC"/*.conf; do
    [ -e "$src" ] || continue
    name="$(basename "$src")"
    if [ -e "$CONF_DST/$name" ]; then
        echo "  = $name 이미 존재 — 건너뜀 (수정 필요 시 직접 편집 후 reload)"
    else
        sudo cp "$src" "$CONF_DST/$name"
        echo "  + $name 배포됨"
        new_confs=$((new_confs + 1))
    fi
done

# html 은 repo 전용 정적 콘텐츠라 그대로 동기화한다(certbot 이 건드리지 않음).
sudo rsync -a "$HTML_SRC/" "$HTML_DST/"

if [ "$new_confs" -gt 0 ]; then
    echo "  → 새 conf $new_confs 개 배포됨. 새 도메인이면 ssl_setup.sh 로 인증서(443)를 발급하세요."
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
