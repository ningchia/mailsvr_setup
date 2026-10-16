#!/bin/bash
set -e

# 1. 讀取環境變數，若沒提供則給預設值
POSTFIX_HOST_NAME=${POSTFIX_HOST_NAME:-mailer}
POSTFIX_DOMAIN_NAME=${POSTFIX_DOMAIN_NAME:-mydomain.com}

# 2. 利用 postconf -e 動態寫入/更新 main.cf 設定
postconf -e "myhostname = $POSTFIX_HOST_NAME"
postconf -e "mydomain = $POSTFIX_DOMAIN_NAME"

# 3. 自動執行資料庫編譯與權限檢查
postmap /etc/postfix/virtualmap
postmap /etc/postfix/client_sasl_passwd
chmod 600 /etc/postfix/client_sasl_passwd /etc/postfix/client_sasl_passwd.db
newaliases

# 4. 確保 supervisor 日誌與運行目錄存在
mkdir -p /var/log/supervisor

# 5. 啟動 Supervisord 主行程（由 CMD 帶入命令）
# $@ 代表傳遞給這個腳本的所有命令列參數.
# exec 會用新的行程（也就是 supervisord）完全取代原本的 Shell 腳本行程（PID 1）。
# 這讓 supervisord 能夠直接接收來自 Docker 的訊號（例如 docker stop 的 SIGTERM），確保容器能正常 graceful shutdown。
exec "$@"