#!/bin/bash
# SSL 인증서 발급 스크립트 (Let's Encrypt / certbot)
#
# [현재 방식] certbot HTTP-01 챌린지 — nginx가 직접 HTTPS 처리
#   EC2 → nginx(HTTPS, certbot 인증서) → 앱
#
# [ACM 전환 시 이 스크립트는 불필요해짐]
#   ACM 인증서는 AWS 콘솔에서 발급 (무료, 자동 갱신)
#   CloudFront 배포에 ACM 인증서 연결 → HTTPS는 CloudFront가 처리
#   EC2/nginx는 HTTP만 받으면 되므로 certbot, SSL 설정 전부 제거
#   전환 절차:
#     1. ACM에서 도메인 인증서 발급 (DNS 검증)
#     2. CloudFront 배포 → 편집 → SSL 인증서를 ACM으로 교체
#     3. nginx conf에서 443 블록 및 ssl_certificate 설정 제거
#     4. certbot-renew.timer / crontab 갱신 항목 삭제
#     5. /etc/letsencrypt 디렉토리 정리
set -e

ENV_FILE="$(dirname "$0")/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo ".env 파일이 없습니다. .env.example을 복사해 작성하세요."
    exit 1
fi
source "$ENV_FILE"
EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL가 .env에 없습니다}"

# 인증서 하나에 모든 도메인 포함 (SAN)
# seogyoung.com 은 준비 완료 후 추가
DOMAINS=(
    "sandbox.seogyoung.com"
    "odiga.sandbox.seogyoung.com"
    "odiga-server.sandbox.seogyoung.com"
)

# ────────────────────────────────────────
# 1. certbot 설치
# ────────────────────────────────────────
echo "[1/4] certbot 설치 확인..."
if ! command -v certbot &>/dev/null; then
    if command -v dnf &>/dev/null; then
        sudo dnf install -y certbot python3-certbot-nginx
    elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y certbot python3-certbot-nginx
    else
        echo "지원하지 않는 패키지 매니저. certbot을 수동 설치하세요."
        exit 1
    fi
else
    echo "certbot 이미 설치됨 ($(certbot --version 2>&1))"
fi

# ────────────────────────────────────────
# 2. 인증서 발급
# ────────────────────────────────────────
echo ""
echo "[2/4] 인증서 발급 중..."

PRIMARY_DOMAIN="${DOMAINS[0]}"

DOMAIN_ARGS=""
for d in "${DOMAINS[@]}"; do
    DOMAIN_ARGS="$DOMAIN_ARGS -d $d"
done

# 모든 도메인이 기존 인증서에 포함되어 있는지 확인
ALL_COVERED=true
for d in "${DOMAINS[@]}"; do
    if ! sudo certbot certificates 2>/dev/null | grep -q "  $d"; then
        ALL_COVERED=false
        break
    fi
done

if [ "$ALL_COVERED" = true ]; then
    echo "  모든 도메인 인증서 이미 존재 — 건너뜀"
elif sudo certbot certificates 2>/dev/null | grep -q "$PRIMARY_DOMAIN"; then
    # 인증서는 있지만 누락 도메인 있음 → expand
    echo "  누락 도메인 감지 — 기존 인증서에 추가 중..."
    sudo certbot --nginx --expand $DOMAIN_ARGS \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
else
    # 인증서 없음 → 신규 발급
    echo "  신규 발급 중..."
    sudo certbot --nginx $DOMAIN_ARGS \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
fi

# ────────────────────────────────────────
# 3. 자동 갱신 설정
# ────────────────────────────────────────
echo ""
echo "[3/4] 자동 갱신 설정..."

# AL2023은 systemd 타이머 우선 사용
if systemctl list-unit-files 2>/dev/null | grep -q "certbot-renew.timer"; then
    sudo systemctl enable --now certbot-renew.timer
    echo "  systemd certbot-renew.timer 활성화됨"
else
    # fallback: crontab (하루 2회 — Let's Encrypt 공식 권장)
    CRON_JOB="0 0,12 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'"
    if sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
        echo "  crontab 갱신 항목 이미 존재"
    else
        (sudo crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo crontab -
        echo "  crontab 갱신 등록됨 (00:00, 12:00)"
    fi
fi

# ────────────────────────────────────────
# 4. 결과 확인
# ────────────────────────────────────────
echo ""
echo "[4/4] 인증서 상태 확인..."
sudo certbot certificates

echo ""
echo "완료!"
echo ""
echo "주의: setup.sh 재실행 시 SSL 설정이 덮어써집니다."
echo "nginx 설정 변경이 필요하면 ssl_setup.sh를 다시 실행하거나,"
echo "/etc/nginx/conf.d/ 를 직접 수정 후 'sudo systemctl reload nginx' 하세요."
