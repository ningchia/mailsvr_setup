#!/bin/bash

# 替換成目標網域與信箱
DOMAIN="mydomain.com"
EMAIL="notroot@mydomain.com"

echo "=== 開始透過 Webroot 模式為 $DOMAIN 申請 SSL 憑證 ==="

# 在正式發送申請之前，可以增加使用 --dry-run 參數。
# 這會連線到 Let's Encrypt 的測試伺服器進行完整流程驗證，不會消耗您的正式申請額度（Rate Limits）。
docker run -it --rm \
  -v ./certs:/etc/letsencrypt \
  -v ./certbot-webroot:/var/www/certbot \
  certbot/certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email $EMAIL \
  --agree-tos \
  --no-eff-email \
  -d $DOMAIN 

echo "=== 憑證申請程序結束 ==="