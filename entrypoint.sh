#!/bin/bash
set -e

# 1. 讀取環境變數，若沒提供則給預設值
POSTFIX_HOST_NAME=${POSTFIX_HOST_NAME:-mailer}
POSTFIX_DOMAIN_NAME=${POSTFIX_DOMAIN_NAME:-mydomain.com}

# 2. 原本要利用 postconf -e 動態寫入/更新 main.cf 設定
# postconf -e "myhostname = $POSTFIX_HOST_NAME"
# postconf -e "mydomain = $POSTFIX_DOMAIN_NAME"
#
# 但是, Docker 不允許容器內的行程去 delete 或 rename 一個被直接 Mount 的 Inode！
# 當 Postfix 嘗試用 main.cf.tmp 替換 /etc/postfix/main.cf 時，Linux Kernel 會阻擋這個操作
# 並拋出 Device or resource busy 的錯誤訊息。
#
# 用 sed -i 直接修改 /etc/postfix/main.cf 也會觸發 rename/Device or resource busy 的問題！
# (因為 sed -i 會先產生一個臨時檔案，然後再 rename 覆蓋原檔案) 
# sed -i "s/^myhostname = .*/myhostname = $POSTFIX_HOST_NAME/" /etc/postfix/main.cf
# sed -i "s/^mydomain = .*/mydomain = $POSTFIX_DOMAIN_NAME/" /etc/postfix/main.cf
#
# 最終解法:
# 1. 將更新後的內容寫到臨時記憶體或 /tmp (容器內部的非 Mount 路徑)
sed -e "s/^myhostname = .*/myhostname = $POSTFIX_HOST_NAME/" \
    -e "s/^mydomain = .*/mydomain = $POSTFIX_DOMAIN_NAME/" \
    /etc/postfix/main.cf > /tmp/main.cf.new

# 2. 用 cat 覆寫內容（關鍵：保持原檔案 Inode 不變，只覆寫內容）
cat /tmp/main.cf.new > /etc/postfix/main.cf
rm /tmp/main.cf.new

# ==========================================
# 檔案權限與擁有者自動校正 (針對 Shared Volume 掛載檔)
# ==========================================
# 確保 Let's Encrypt 憑證目錄與私密金鑰具備 Postfix 讀取所需的正確權限
if [ -d /etc/letsencrypt ]; then
    # 將憑證根目錄權限收緊，避免私密金鑰外洩
    find /etc/letsencrypt -type d -exec chmod 755 {} +
    find /etc/letsencrypt -type f -exec chmod 644 {} +

    # 特別針對私密金鑰 (privkey.pem) 收緊為 600（若存在的話）
    # 直接針對 archive 目錄下的所有 privkey*.pem 設定為 600
    if [ -d /etc/letsencrypt/archive ]; then
        find /etc/letsencrypt/archive -name "privkey*.pem" -exec chmod 600 {} +
        echo "已將私密金鑰權限收緊為 600"
    fi
    
    # 建立指向目標網域憑證目錄的固定符號連結 (mail-current)
    TARGET_CERT_DIR="/etc/letsencrypt/live/${POSTFIX_HOST_NAME}.${POSTFIX_DOMAIN_NAME}"
    FIXED_SYMLINK="/etc/letsencrypt/live/mail-current"

    if [ -d "$TARGET_CERT_DIR" ]; then
        # 如果符號連結已存在則強制更新，若不存在則建立
        ln -sfn "$TARGET_CERT_DIR" "$FIXED_SYMLINK"
        echo "已成功建立或更新憑證符號連結: $FIXED_SYMLINK -> $TARGET_CERT_DIR"
    else
        echo "警告: 找不到目標憑證目錄 $TARGET_CERT_DIR，無法建立符號連結。"
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