## 개인 도메인 관리용 Github
- domain : https://seogyoung.com (준비중)
- sandbox-doman : https://sandbox.seogyoung.com


## 새 서비스(서브도메인) 추가하기

1. `nginx/conf.d/<이름>.conf` 작성 — **80 블록만** 둔다. 443(HTTPS)은 certbot이 붙인다.
   앱이 뒤에서 세션 쿠키에 `Secure`를 쓰면 `proxy_set_header X-Forwarded-Proto $scheme;`를 넣는다.
   (예시: `nginx/conf.d/career.conf`)
2. `ssl_setup.sh`의 `DOMAINS` 배열에 새 도메인을 추가한다.
3. DNS에 서브도메인 레코드를 추가한다(기존과 동일하게).
4. 서버에서:
   ```bash
   git pull
   sudo bash setup.sh       # 새 conf만 배포 (기존 certbot 관리 conf는 보존)
   sudo bash ssl_setup.sh   # certbot이 443 블록 추가 + SAN 인증서 확장
   ```

> `setup.sh`는 **새 conf만 추가**하고 기존 conf는 건드리지 않는다(certbot이 수정한 443 설정 보존).
> 기존 도메인 설정을 바꿀 때는 `/etc/nginx/conf.d/`를 직접 편집 후
> `sudo nginx -t && sudo systemctl reload nginx`.
>
> 스크립트는 `sh`가 아니라 `bash`로 실행할 것(`sudo bash setup.sh`). `sh`로 돌리면
> `source`·배열 같은 bash 문법이 깨진다.

---
참고 
- 주요 내용은 gitignore로 관리될 예정입니다.
- ~.. 월 2만원이 나가고 있어요~ Raspberry Pi 3 Model로 호스팅중입니다.
