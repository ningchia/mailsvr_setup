#!/bin/bash

# 自動載入 .env 內的環境變數
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo "錯誤: 找不到 .env 檔案！"
    exit 1
fi

echo "=== 開始透過 Webroot 模式為 $POSTFIX_DOMAIN_NAME 申請 SSL 憑證 (管理員: $SSL_ADMIN_EMAIL) ==="

docker run -it --rm \
  -v ./certs:/etc/letsencrypt \
  -v ./certbot-webroot:/var/www/certbot \
  certbot/certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email $SSL_ADMIN_EMAIL \
  --agree-tos \
  --no-eff-email \
  -d $POSTFIX_DOMAIN_NAME

echo "=== 憑證申請程序結束 ==="