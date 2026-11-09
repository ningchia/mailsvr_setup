#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# 自動載入 .env 內的環境變數（忽略註解與空白行）
# set -a 會將所有變數自動導出為環境變數，set +a 則關閉此功能。
if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
else
    echo "錯誤: 找不到 .env 檔案！"
    exit 1
fi

# 刪掉可能存在結尾的 Windows 換行符號('\r').
# 可以用 printf '%q\n' "$SSL_ADMIN_EMAIL"來確認. 
# %q 會將字串以可重現的方式輸出，方便檢查是否有多餘的換行符號。
SSL_ADMIN_EMAIL="${SSL_ADMIN_EMAIL%$'\r'}"
POSTFIX_HOST_NAME="${POSTFIX_HOST_NAME%$'\r'}"
POSTFIX_DOMAIN_NAME="${POSTFIX_DOMAIN_NAME%$'\r'}"

# 驗證必要變數
if [ -z "${SSL_ADMIN_EMAIL:-}" ]; then
    echo "錯誤: SSL_ADMIN_EMAIL 未設定，請先在 .env 中填入有效電子郵件。"
    exit 1
fi

if [[ ! "$SSL_ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "錯誤: SSL_ADMIN_EMAIL 格式不合法: $SSL_ADMIN_EMAIL"
    exit 1
fi

if [ -z "${POSTFIX_DOMAIN_NAME:-}" ]; then
    echo "錯誤: POSTFIX_DOMAIN_NAME 未設定。"
    exit 1
fi

echo "=== 開始透過 Webroot 模式為 $POSTFIX_DOMAIN_NAME 申請 SSL 憑證 (管理員: $SSL_ADMIN_EMAIL) ==="

docker run -it --rm \
  -v "$SCRIPT_DIR/certs:/etc/letsencrypt" \
  -v "$SCRIPT_DIR/certbot-webroot:/var/www/certbot" \
  certbot/certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email "$SSL_ADMIN_EMAIL" \
  --agree-tos \
  --no-eff-email \
  -d "$POSTFIX_DOMAIN_NAME"

echo "=== 憑證申請程序結束 ==="