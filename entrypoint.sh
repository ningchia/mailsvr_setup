#!/bin/bash
set -e

# 1. 讀取環境變數，若沒提供則給預設值
POSTFIX_HOST_NAME=${POSTFIX_HOST_NAME:-mailer}
POSTFIX_DOMAIN_NAME=${POSTFIX_DOMAIN_NAME:-mydomain.com}

# 2. 利用 postconf -e 動態寫入/更新 main.cf 設定
postconf -e "myhostname = $POSTFIX_HOST_NAME"
postconf -e "mydomain = $POSTFIX_DOMAIN_NAME"

# ==========================================
# 檔案權限與擁有者自動校正 (針對 Shared Volume 掛載檔)
# ==========================================
# 確保 Let's Encrypt 憑證目錄與私密金鑰具備 Postfix 讀取所需的正確權限
if [ -d /etc/letsencrypt ]; then
    # 將憑證根目錄權限收緊，避免私密金鑰外洩
    find /etc/letsencrypt -type d -exec chmod 755 {} +
    find /etc/letsencrypt -type f -exec chmod 644 {} +
    # 特別針對私密金鑰 (privkey.pem) 收緊為 600（若存在的話）
    if [ -f /etc/letsencrypt/live/*/privkey.pem ]; then
        chmod 600 /etc/letsencrypt/live/*/privkey.pem
    fi
fi

# Postfix 核心設定與對應表
chown root:root /etc/postfix/main.cf /etc/postfix/master.cf /etc/postfix/virtualmap /etc/postfix/client_sasl_passwd
chmod 644 /etc/postfix/main.cf /etc/postfix/master.cf /etc/postfix/virtualmap
chmod 600 /etc/postfix/client_sasl_passwd  # 包含密碼必須嚴格設為 600

# 系統別名檔
chown root:root /etc/aliases
chmod 644 /etc/aliases

# Dovecot conf.d 設定檔
chown -R root:root /etc/dovecot/conf.d/
chmod 644 /etc/dovecot/conf.d/*.conf /etc/dovecot/conf.d/*.ext

# Dovecot 密碼檔 (安全性要求最高：root 讀寫, dovecot 群組唯讀)
if [ -f /etc/dovecot/users ]; then
    chown root:dovecot /etc/dovecot/users
    chmod 640 /etc/dovecot/users
fi

# 3. 自動執行資料庫編譯與權限檢查
postmap /etc/postfix/virtualmap
postmap /etc/postfix/client_sasl_passwd
newaliases

# 4. 確保 supervisor 日誌與運行目錄存在
mkdir -p /var/log/supervisor

# 5. 啟動 Supervisord 主行程（由 CMD 帶入命令）
# $@ 代表傳遞給這個腳本的所有命令列參數.
# exec 會用新的行程（也就是 supervisord）完全取代原本的 Shell 腳本行程（PID 1）。
# 這讓 supervisord 能夠直接接收來自 Docker 的訊號（例如 docker stop 的 SIGTERM），確保容器能正常 graceful shutdown。
exec "$@"