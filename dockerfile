# 1. 以 Ubuntu 24.04 為基底
FROM ubuntu:24.04

# 2. 設定非互動式安裝，並預設時區為亞洲/台北 (Asia/Taipei)
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Taipei

# 設定環境變數, 要透過 postconf -e 用來覆寫 postfix main.cf.
ENV POSTFIX_HOST_NAME=mailer
ENV POSTFIX_DOMAIN_NAME=mydomain.com

# 3. 預先設定 Postfix 的 debconf 選項
RUN echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections && \
    echo "postfix postfix/mailname string $POSTFIX_DOMAIN_NAME" | debconf-set-selections && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 4. 更新系統、安裝基礎工具與郵件相關軟體 (Postfix + Dovecot + Supervisor)
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
    nano \
    wget \
    curl \
    net-tools \
    tzdata \
    supervisor \
    postfix \
    dovecot-imapd \
    dovecot-pop3d \
    && rm -rf /var/lib/apt/lists/*

# 5. 建立專屬的 vmail 系統帳號與群組 (UID/GID 設為 5000，供後續 Dovecot 存放信箱使用)
# -s /bin/false: 禁止登入 shell
# -d /var/vmail: 指定信箱根目錄
RUN groupadd -g 5000 vmail && \
    useradd -u 5000 -g vmail -s /bin/false -d /home/vmail -m vmail

# 7.1 複製 Supervisord 設定檔
COPY etc/supervisor/supervisord.conf /etc/supervisor/supervisord.conf

# 9. 複製並設定容器啟動腳本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 10. 開放郵件相關通訊埠
# 25: SMTP, 465: SMTPS, 587: Submission, 143: IMAP, 993: IMAPS, 110: POP3, 995: POP3S
EXPOSE 25 465 587 143 993 110 995

# 11. 設定容器啟動入口：執行初始化後啟動 supervisord
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]