# Mail Server Setup Guide

這個 repo 是一份以 Docker 為基礎的郵件伺服器設定範本，核心使用：

- Postfix：SMTP 收發信
- Dovecot：IMAP / POP3 / SASL 認證
- Nginx：用來處理 Let's Encrypt HTTP-01 驗證
- Certbot：自動申請與更新 SSL 憑證
- Ubuntu 24.04：作業系統基底

這份設定適合拿來在新主機或新環境中快速建置一個可用的郵件伺服器，並保留方便修改的設定檔。

## 目錄

- [1. 這個 repo 主要是什麼](#1-這個-repo-主要是什麼)
- [2. 開 VM、開防火牆與準備 DNS](#2-開-vm開防火牆與準備-dns)
  - [建議 DNS 設定](#建議-dns-設定)
  - [Azure 上的 DNS 設定範例](#azure-上的-dns-設定範例)
  - [SPF 記錄](#spf-記錄)
  - [DMARC 記錄](#dmarc-記錄)
  - [DKIM 記錄](#dkim-記錄)
  - [Azure 的反向 DNS（PTR）與驗證](#azure-的反向-dnsptr-與驗證)
  - [Azure NSG / 防火牆要開放](#azure-nsg--防火牆要開放)
- [3. 修正 .env 與郵件設定檔](#3-修正-env-與郵件設定檔)
  - [3.1 .env](#31-env)
  - [3.2 設定 `mail_config/dovecot/users`](#32-設定-mail_configdovecotusers)
  - [3.3 設定 `mail_config/aliases`](#33-設定-mail_configaliases)
  - [3.4 設定 `mail_config/postfix/virtualmap`](#34-設定-mail_configpostfixvirtualmap)
  - [3.5 設定 `mail_config/postfix/client_sasl_passwd`](#35-設定-mail_configpostfixclient_sasl_passwd)
- [4. 啟動 postfix, dovecot, nginx](#4-啟動-postfix-dovecot-nginx)
  - [4.1 新增/修改收信帳號](#41-新增修改收信帳號)
  - [4.2 修改管理別名](#42-修改管理別名)
  - [4.3 修改 Postfix 虛擬郵件表](#43-修改-postfix-虛擬郵件表)
  - [4.4 執行 docker compose up 的細節](#44-執行-docker-compose-up-的細節)
- [5. 為 mail server 申請 SSL 憑證](#5-為-mail-server-申請-ssl-憑證)
- [6. 維護工作：容器重啟與健檢](#6-維護工作容器重啟與健檢)
  - [6.1 需要時重啟容器](#61-需要時重啟容器)
  - [6.2 新增/修改信箱使用者](#62-新增修改信箱使用者)
  - [6.3 修改外寄中繼設定](#63-修改外寄中繼設定)
  - [6.4 常用驗證命令](#64-常用驗證命令)
- [7. Docker Compose 的作用](#7-docker-compose-的作用)
- [8. 新機器部署的最簡步驟](#8-新機器部署的最簡步驟)
- [9. 維護與除錯建議](#9-維護與除錯建議)
- [10. 一個簡單的總結](#10-一個簡單的總結)
- [11. 你可以直接照這樣做](#11-你可以直接照這樣做)

### 目錄結構

```text
mailsvr_setup/
├── .env                           # 全域設定：主機名稱 / 網域 / 管理者信箱
├── .gitignore                    # 忽略 certbot-webroot 等實際動態資料
├── docker-compose.yml            # 定義 mail-server 與 nginx 容器
├── dockerfile                    # 建立郵件伺服器映像檔
├── entrypoint.sh                 # 容器啟動時注入 Postfix 設定
├── init_cert.sh                 # 使用 Certbot 申請 Let's Encrypt 憑證
├── readme.md                     # 這份使用說明
├── certs/                       # Let's Encrypt 憑證放置處
├── certbot-webroot/             # Certbot HTTP-01 驗證用 webroot
├── etc/
│   └── supervisor/
│       └── supervisord.conf      # 讓容器內啟動 Postfix / Dovecot 等服務
├── mail_config/
│   ├── aliases                  # 系統別名設定
│   ├── dovecot/
│   │   ├── users                # 信箱帳號與密碼
│   │   └── conf.d/
│   │       ├── 10-auth.conf
│   │       ├── 10-logging.conf
│   │       ├── 10-mail.conf
│   │       ├── 10-master.conf
│   │       ├── 10-ssl.conf
│   │       ├── 20-pop3.conf
│   │       └── auth-passwd.conf.ext
│   └── postfix/
│       ├── client_sasl_passwd  # relayhost 的 SMTP 認證帳密
│       ├── main.cf              # Postfix 主設定
│       ├── master.cf            # SMTP / 465 / 587 / 其他通訊埠設定
│       ├── virtualmap           # 虛擬別名 / 轉寄規則
│       └── ...
├── nginx/
│   └── conf.d/
│       └── default.conf.template
└── 附大量註解的原始postfix_main.cf.orig  # 參考設定範本
```

這個 repo 的設計重點是：把郵件相關設定檔都掛到容器外部，因此你可以直接在 Host 端修改設定，再重啟容器生效。

---

## 1. 這個 repo 主要是什麼

在這個資料夾中，最重要的檔案是：

- `docker-compose.yml`：定義 `mail-server` 與 `nginx` 兩個容器
- `dockerfile`：建立郵件伺服器容器映像檔
- `.env`：設定郵件網域、主機名稱與管理員信箱
- `entrypoint.sh`：容器啟動時注入 Postfix 的環境設定
- `mail_config/`：Postfix / Dovecot / alias 的實際設定檔
- `init_cert.sh`：用來向 Let's Encrypt 申請證書
- `nginx/conf.d/default.conf.template`：Nginx 的模板設定

這個 repo 的設計重點是：把郵件相關設定檔都掛到容器外部，因此你可以直接在 Host 端修改設定，再重啟容器生效。

---

## 2. 開 VM、開防火牆與準備 DNS

在真正啟動這個郵件伺服器之前，請先準備：

1. 一台有公開 IP 的 Linux / VPS / 雲端主機
2. Docker 與 Docker Compose 已安裝
3. 你自己的網域，例如 `example.com`
4. DNS 記錄已經設定好
5. 防火牆 / Security Group 已放行 SMTP / IMAP / HTTP / HTTPS 所需通訊埠

這一步的目標是：先讓 VM 能從網際網路看到、讓 hostname 能解析、讓 80 / 443 / 25 / 587 / 993 / 995 能通過，接著再開始修設定、啟動容器與申請 cert。

### 建議 DNS 設定

請至少確認以下紀錄（以 Azure 實務來看，`CNAME` 往往比 `A/AAAA` 更常見，因為 Azure 會先提供 hostname，再由 Azure DNS 解析到實際 IP）：

- CNAME：`mail.example.com` 或 `smtp.example.com` 指向 Azure 的 host name，例如 `myvm.eastus.cloudapp.azure.com`
- MX：`example.com` 指向 `mail.example.com`
- TXT：`example.com` 的 SPF，並補上 `_dmarc` 記錄
- 若你使用子網域，也可把 `mail` 作為實際郵件主機名稱

> 也就是說，`A/AAAA` 並不一定是必要的；在 Azure 環境中，常見做法是讓 `CNAME` 指向 Azure 提供的 hostname，再由 Azure DNS 完成解析。只有在你完全掌握自有 IP / 自有 DNS 架構時，才會用 `A/AAAA` 直接指到固定 IP。

### Azure 上的 DNS 設定範例

以下以 Azure 為例，假設你的 Azure VM hostname 是 `myvm.eastus.cloudapp.azure.com`，網域是 `example.com`。實際上，郵件系統最重要的三類 DNS 記錄通常是：

- `CNAME`：將主機名稱指向另一個名稱
- `MX`：告訴外部郵件伺服器，哪個主機負責接收這個網域的郵件
- `TXT`：放 SPF 與 DMARC 等驗證資訊

> 這裡不建議直接用 `A` 記錄去表示「郵件主機」作為唯一答案；在 Azure 的實務上常見是用 `CNAME` 指向 Azure DNS 內的主機名稱，再由 Azure DNS 解析到實際 Public IP。也就是說，`CNAME` 的 value 通常不是直接寫一個 IP，而是寫 Azure 的 hostname，例如 `myvm.eastus.cloudapp.azure.com`，再由 Azure 去完成實際解析。

#### 1) Azure DNS Zone 中的 DNS 記錄範例

在 Azure Portal 中建立或選擇你的 DNS Zone：`example.com`，新增以下記錄：

```text
Type  Name       Value                                                  TTL
CNAME mail       myvm.eastus.cloudapp.azure.com.                          300
MX    @          mail.example.com. 10                                   300
TXT   @          v=spf1 mx include:mail.example.com -all                300
TXT   _dmarc     v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com   300
TXT   selector1  v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtest123... 300
```

這些記錄的意思是：

- `CNAME mail`：把 `mail` 這個別名指向 Azure VM 的 host name，例如 `myvm.eastus.cloudapp.azure.com`
- `MX @`：這個網域的郵件由 `mail.example.com` 處理，優先順序為 `10`
- `TXT @`：SPF 定義，說明哪些 IP 或網域可以代表 `example.com` 發送郵件
- `_dmarc`：DMARC 定義，告訴外部郵件伺服器應如何處理未通過檢查的郵件
- `selector1`：DKIM 公鑰宣告，讓對方能驗證你發送的信件真的來自這個網域

> 這是 Azure 常見的做法：先把你自己的別名，例如 `mail.example.com`，指向 Azure 內部提供的 hostname；再由 Azure DNS 解析到 VM / Public IP。這樣最符合 Azure 環境中的命名與解析方式。

<a id="spf-記錄"></a>

#### 2) SPF 記錄（通常是 `TXT @`）

SPF 通常寫在 root domain 的 `TXT` 記錄中，格式例如：

```text
v=spf1 mx include:mail.example.com -all
```

各個欄位的含義如下：

- `v=spf1`：表示這是一個 SPF 版本 1 的記錄，必須是第一個欄位
- `mx`：允許發信的 SMTP 伺服器是這個網域的 MX 記錄所指向的主機
- `include:mail.example.com`：允許該主機名所代表的服務發信，例如中繼服務或自有郵件伺服器
- `-all`：其他任何來源都拒絕，這是最嚴格的終點規則
- `~all`：其他來源視為 Soft Fail，通常用於過渡期
- `?all`：其他來源不做明確判定，較寬鬆

簡單來說，SPF 的目的是讓收件伺服器確認：

> 「這封信的發信 IP 是否真的屬於我所授權的合法郵件伺服器？」

如果你的 `relayhost` 是外部中繼服務（例如 Brevo / SendGrid / Mailgun），SPF 往往需要依照其官方建議調整，例如加入 `include:<provider>.com`。

<a id="dmarc-記錄"></a>

#### 3) DMARC 記錄（通常是 `TXT _dmarc`）

DMARC 也寫在 `TXT` 紀錄中，通常是：

```text
v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; ruf=mailto:postmaster@example.com; adkim=r; aspf=r
```

欄位意義：

- `v=DMARC1`：表示這是 DMARC 的版本資訊
- `p=quarantine`：當 SPF 或 DKIM 驗證失敗時，該如何處理
  - `none`：不採取動作，只記錄
  - `quarantine`：將信件視為可疑，放進垃圾信或額外檢查
  - `reject`：直接拒收
- `rua=mailto:dmarc@example.com`：匯報給定義的郵件地址，會收到聚合報告（Aggregate Report）
- `ruf=mailto:postmaster@example.com`：匯報失敗的個別郵件詳細內容，供後續排查
- `adkim=r`：DKIM 驗證的對齊模式
  - `r`：Relaxed，允許 subdomain 之間對齊
  - `s`：Strict，要求精確相符
- `aspf=r`：SPF 驗證的對齊模式，含義與 `adkim` 類似
- `pct=100`：只對 100% 的郵件做 DMARC 判斷，較少見，但可作調整

DMARC 的目標不是取代 SPF 或 DKIM，而是把兩者結合起來，讓收件端以統一策略來處理：

> 「我怎麼處理 SPF/DKIM 驗證失敗的郵件？」

<a id="dkim-記錄"></a>

#### 4) DKIM 記錄（通常是 `TXT selector1` / `TXT selector2`）

DKIM 是透過 `TXT` 紀錄公開公鑰，讓收件端可驗證你發信端真的是你所控制的伺服器。格式通常是：

```text
selector1._domainkey.example.com. IN TXT "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtest123..."
```

欄位意義：

- `selector1`：DKIM 的 selector 名稱，可自行命名，通常是 `selector1`、`selector2` 或服務供應商自定義名稱
- `_domainkey`：固定字首，表示這是 DKIM 公鑰記錄
- `v=DKIM1`：宣告這是一個 DKIM 記錄
- `k=rsa`：表示使用 RSA 金鑰
- `p=`：真正的公鑰內容（長字串）

DKIM 的典型用途：

- 讓外部郵件伺服器驗證你所發送的信件是否真的是由你的郵件伺服器簽名
- 當你使用外部 relayhost（例如 Brevo）時，通常需要依照該服務提供的 DKIM selector 與公鑰進行設定

> 這三個記錄通常一起出現：
> - SPF：宣告哪些來源可以發信
> - DMARC：宣告失敗時如何處理
> - DKIM：提供發信端的公鑰，讓收件端能驗證簽名
>
> 實際上，`relayhost` 可能有不同需求，因此這三者通常要依服務商指定的規範來微調。

<a id="azure-的反向-dnsptr-與驗證"></a>

#### 4) Azure 的反向 DNS（PTR）與驗證

郵件伺服器很容易被忽略的地方是「反向 DNS」。反向 DNS 的目的是讓遠端郵件伺服器做 IP 反查，確認：

> 這個 IP 反查回來的名稱，是否與該網域的郵件伺服器名稱一致？

對 Azure 來說，這通常不是在你自己的 DNS Zone 內設定，而是在 Azure 服務層裡設定 Public IP 的 Reverse FQDN（也就是 PTR 反向解析的 FQDN）。這與你在 Azure DNS Zone 內的正向解析是不同層級的設定。

官方文件可參考：

- https://learn.microsoft.com/zh-tw/azure/dns/dns-reverse-dns-for-azure-services

Azure 官方的例子如下：

```powershell
$pip = Get-AzPublicIpAddress -Name "PublicIP" -ResourceGroupName "MyResourceGroup"
$pip.DnsSettings.ReverseFqdn = "myvm.eastus.cloudapp.azure.com."
Set-AzPublicIpAddress -PublicIpAddress $pip
```

這段意思是：

1. 先抓出指定的 Public IP 物件
2. 設定它的 `ReverseFqdn`
3. 再把變更寫回 Azure

也就是說，反向 DNS 不是寫在 `example.com` 的 DNS Zone 裡，而是寫在 Azure Public IP 本身上，讓它反查回來的名稱會是：

```text
myvm.eastus.cloudapp.azure.com.
```

這通常會對收到的郵件進行反查，檢查：

- 正向解析：`myvm.eastus.cloudapp.azure.com.` -> 對應的 Public IP
- 反向解析：Public IP -> `myvm.eastus.cloudapp.azure.com.`

如果你的郵件伺服器是 Azure VM，最常見的做法是：

- `mail.example.com` 先透過 Azure DNS 的 `CNAME` 或 `A` 指向 Azure hostname
- 然後在 Public IP 上再設定 Reverse FQDN，讓這個 IP 反查到你希望的郵件主機名

這樣的配套可以讓外部郵件伺服器看到：

```text
mail.example.com -> Public IP -> ReverseFqdn = myvm.eastus.cloudapp.azure.com.
```

這和你在 DNS Zone 設定的 `MX`、`SPF`、`DMARC`、`DKIM` 相互補強，會讓郵件更容易通過收件端的驗證。

若你在 Linux 端做驗證，常用命令如下：

```bash
nslookup mail.example.com
nslookup 203.0.113.10
set type=ptr
203.0.113.10
```

例如你在圖中的驗證結果應該會出現：

```text
Name:   myvm.eastus.cloudapp.azure.com
Address: 40.115.238.161
```

以及：

```text
Non-authoritative answer:
161.238.115.40.in-addr.arpa   name = mail.example.com
```

這表示：

- 正向解析：`mail.example.com` -> `203.0.113.10` 正常
- 反向解析：`203.0.113.10` -> `mail.example.com` 正常

這對郵件系統來說很重要，因為很多收件端會檢查這個反向名稱是否符合你宣告的郵件伺服器。

> 簡單說：A/MX/TXT 給外部郵件伺服器「這是誰」；PTR 則讓外部郵件伺服器確認「這個 IP 的反向名稱也真的是你」。

<a id="azure-nsg--防火牆要開放"></a>

#### 5) Azure NSG / 防火牆要開放

在 Azure 的 Network Security Group（NSG）或 VM Firewall 中，至少要允許：

- TCP 25
- TCP 587
- TCP 465
- TCP 143
- TCP 993
- TCP 110
- TCP 995
- TCP 80
- TCP 443

此外，若你在 Azure 後端是 VM，請確認：

- VM 的 Public IP 或 NIC 有被正確綁定
- Azure NSG 沒有封鎖郵件埠
- 80 / 443 允許 Let's Encrypt 驗證

### 防火牆與端口

你需要讓這些埠能對外開放：

- 25：SMTP
- 587：Submission
- 465：SMTPS
- 143：IMAP
- 993：IMAPS
- 110：POP3
- 995：POP3S
- 80：HTTP（Let's Encrypt 驗證）
- 443：HTTPS

> 注意：很多雲端環境（例如 Azure、AWS）會預設封鎖 25。若你的環境不允許 25 出站/入站，請先確認你的主機或雲端安全群組允許它。

---

## 3. 修正 .env 與郵件設定檔

在開好 VM / DNS / 防火牆後，下一步就是先把郵件相關設定檔修好。這一步要先完成，因為後續 `docker compose up`、`init_cert.sh` 都依賴這些值。

進入專案目錄後，修改 `.env`：

```bash
cd mailsvr_setup
nano .env
```

內容大致如下：

```env
POSTFIX_HOST_NAME=mail
POSTFIX_DOMAIN_NAME=example.com
SSL_ADMIN_EMAIL=admin@example.com
```

請將它改成你實際使用的值：

- `POSTFIX_HOST_NAME`：郵件主機名稱，例如 `mail`
- `POSTFIX_DOMAIN_NAME`：你要作為郵件網域的名稱，例如 `example.com`
- `SSL_ADMIN_EMAIL`：申請 Let's Encrypt 時的管理員信箱

這些參數會在容器啟動時由 `entrypoint.sh` 注入 Postfix 設定中。

---

## 4. 啟動 postfix, dovecot, nginx

在 `.env` 與 `mail_config` 設定完成後，先把 docker compose 啟動起來。這裡的目的不是先申請 cert，而是先讓 nginx / 80 / ACME challenge 能跑起來，讓後續的首次證書申請有 HTTP 入口。

這個 repo 內有幾個你必須先確認的設定檔。

### 4.1 新增/修改收信帳號

檔案：`mail_config/dovecot/users`

預設內容是：

```text
notroot@mydomain.com:{PLAIN}password::::::userdb_quota_rule=*:storage=100M
```

你需要改成自己的帳號與密碼，例如：

```text
admin@example.com:{PLAIN}StrongPassword123::::::userdb_quota_rule=*:storage=100M
```

這樣做之後，Dovecot 就會讓這個帳號能夠收信與登入 IMAP/POP3。

### 4.2 修改管理別名

檔案：`mail_config/aliases`

預設內容：

```text
postmaster: mydomain_contact@mydomain.com
root:       mydomain_contact@mydomain.com
```

請改成你的真實管理信箱：

```text
postmaster: admin@example.com
root:       admin@example.com
```

如果你想接收 root / postmaster 的信件，這裡很重要。

### 4.3 修改 Postfix 虛擬郵件表

檔案：`mail_config/postfix/virtualmap`

這個檔案通常用來定義別名與轉寄規則。你的實際設定可能需要依照你的需求更新，例如：

```text
postmaster@example.com admin@example.com
abuse@example.com admin@example.com
```

若你沒有特殊需求，也可以先保留為預設範例進行修改。

---

### 4.4 執行 docker compose up 的細節

在前面的設定都確認無誤後，正式啟動服務前，通常會在專案目錄中執行：

```bash
cd mailsvr_setup
docker compose up --build -d
```

這個指令的含義是：

- `docker compose`：使用 Docker Compose 來管理多個容器
- `up`：建立或啟動定義出的服務
- `--build`：在啟動前先重新建置映像檔，這能讓你剛修改過 `dockerfile`、`entrypoint.sh` 或基底設定時生效
- `-d`：背景執行（detached mode），讓容器在後台持續運行

這個專案裡，`docker-compose.yml` 定義了：

- `mail-server`：執行 Postfix + Dovecot + Supervisor
- `nginx`：提供 80 / 443 端口，讓 Certbot 可以做 HTTP-01 驗證

因此，這一步的實際目的就是：

1. 啟動 Postfix 與 Dovecot，讓郵件服務開始正常運作
2. 啟動 Nginx，讓 `/.well-known/acme-challenge/` 可以被外部驗證
3. 為後續申請 Let's Encrypt 憑證準備 HTTP 入口

若要查看啟動狀態，可執行：

```bash
docker compose ps
```

若要查看整個啟動過程中出現的錯誤，可執行：

```bash
docker compose logs -f
```

若只看 mail-server 的日誌：

```bash
docker compose logs -f mail-server
```

若只看 nginx 的日誌：

```bash
docker compose logs -f nginx
```

> 這一段很重要：這不是「先做 SSL」而是「先把郵件服務和 HTTP 驗證入口準備好」。只有在 80 埠與 Nginx 正常運作之後，下一步的 `init_cert.sh` 才有辦法真的申請到憑證。

---

## 5. 為 mail server 申請 SSL 憑證

這份 repo 已經設計好 Webroot 模式，讓 Certbot 可以在公開網域上取得 SSL 憑證。這一步應該在 `docker compose up --build -d` 之後、且 nginx 已開啟 80 埠時進行。

先執行：

```bash
chmod +x init_cert.sh
./init_cert.sh
```

這個腳本會：

- 載入 `.env`
- 使用 `certbot/certbot` 容器執行
- 將憑證寫到 `./certs`
- 將 HTTP-01 驗證檔案放到 `./certbot-webroot`

如果你的 DNS 和 80 埠都已正確設定，通常可以成功拿到憑證。

> 若申請失敗，首先檢查：
> - `example.com` 是否已正確解析到主機
> - 80 埠是否已開放
> - `.env` 中的 `POSTFIX_DOMAIN_NAME` 和 `SSL_ADMIN_EMAIL` 是否正確

<a id="renew-ssl-cert"></a>

### 5.1 第一次申請完成後，請補上一個定期 renew 工作

這部分的章節定位要放在最後，因為 renew 是在第一次 cert 成功之後才需要設定。

第一次憑證申請成功後，建議立即在 Host 的 `crontab` 裡掛上一個自動續約任務，避免憑證到期後無法正常服務。這裡的重點是：不要只依靠 Certbot 容器內建的 cron；應該在 Docker 宿主機（VM / 主機）上執行 renew。

```bash
crontab -e
```

加入：

```cron
0 2 * * * docker run --rm -v /path/to/mailsvr_setup/certs:/etc/letsencrypt -v /path/to/mailsvr_setup/certbot-webroot:/var/www/certbot certbot/certbot renew --webroot --webroot-path=/var/www/certbot --quiet && docker restart nginx-proxy mail-server
```

請將 `/path/to/mailsvr_setup` 改成你實際 repo 的絕對路徑，例如：

```bash
0 2 * * * docker run --rm -v /home/ubuntu/mailsvr_setup/certs:/etc/letsencrypt -v /home/ubuntu/mailsvr_setup/certbot-webroot:/var/www/certbot certbot/certbot renew --webroot --webroot-path=/var/www/certbot --quiet && docker restart nginx-proxy mail-server
```

這個任務的目的是：

- 每天 02:00 執行一次 Let's Encrypt 的 `renew`
- 使用 `--webroot` 與 `certbot-webroot` 來驗證域名
- 重新更新掛載到 Host 的 `certs` 目錄
- 在續約成功後，重啟 `nginx-proxy` 與 `mail-server` 容器，讓新憑證生效

#### 為什麼 Certbot 容器自動產生的 crontab 不適合在 Docker 環境中使用？

在一般非容器環境中，Certbot 會自動安裝一個 cron 或 systemd timer，這些機制會由宿主系統 scheduling 機制統一管理，效果很好。 但在 Docker 的情況下，事情會變得不一樣：

1. `certbot/certbot` 是一個短暫容器，不一定會長時間保留 cron 程序
   - `docker run --rm ... certbot/certbot renew ...` 只會在命令執行當下啟動容器，執行完就退出
   - 它不是一個常駐的服務，因此不是自然的 cron 目標

2. cron 需要在宿主機上管理，而不是容器內部管理
   - 容器內的 `/etc/crontab` 或 `cron` 服務只有在那個容器本身持續運行時才有用
   - 但你這個 repo 的設計是由 Docker Compose 來啟動服務，而不是把 cron 當成長期背景服務執行

3. 你要的是「更新 Host 上掛載的憑證目錄」，而不是「更新容器內部某個抽象檔案系統」
   - 這份設定把憑證掛載到 Host 路徑，例如 `./certs`
   - 因此最穩定的作法是由宿主機的 `crontab` 直接觸發 `docker run ... certbot ...`，再讓容器把新憑證寫回相同目錄

4. 容器內的 cron 不會自動知道要重啟 `nginx` 或 `mail-server`
   - 若憑證更新後沒有重啟對應容器，Nginx / Postfix 可能仍舊讀取舊 certificate
   - 宿主機的 cron 會更容易在同一個流程內執行 `docker restart ...`

因此，這個專案最常見且穩定的做法是：

- 把 renew 任務掛在宿主機的 `crontab`
- 由宿主機執行 `docker run certbot/certbot renew`
- 使用同一個 Host 目錄掛載，讓容器讀到更新後的新憑證
- 再重啟對應容器，確保新 cert 生效

> 簡單說：在 Docker 環境中，真正的執行者應該是宿主機的 cron，而不是 Certbot 容器內建的 cron。因為只有宿主機才能穩定地讀取 Host 端掛載的目錄、觸發 `docker` 指令、並協調容器重啟流程。

---

## 6. 維護工作：容器重啟與健檢

在首次成功拿到憑證之後，接下來的工作重點不是再部署，而是定期維護：

- 在 cert 更新後重啟對應容器
- 檢查容器是否正常運作
- 觀察 Postfix / Dovecot / Nginx 的日誌

### 6.1 需要時重啟容器

如果只是重啟服務：

```bash
docker compose restart
```

如果你只是想重建並重新啟動整個環境：

```bash
docker compose up --build -d
```

檢查狀態：

```bash
docker compose ps
```

查看日誌：

```bash
docker compose logs -f mail-server
```

若要查看 Nginx：

```bash
docker compose logs -f nginx
```

---

### 6.2 新增/修改信箱使用者

新增加一個信箱使用者，基本流程是：

1. 編輯 `mail_config/dovecot/users`
2. 新增一列帳號，例如：

```text
user@example.com:{PLAIN}your-password::::::userdb_quota_rule=*:storage=100M
```

3. 重新啟動容器：

```bash
docker compose restart mail-server
```

這樣 Dovecot 就會讓新使用者登入收信。

---

### 6.3 修改外寄中繼設定

這個 repo 內的 `mail_config/postfix/main.cf` 已經有一段範例：

```text
relayhost = [smtp-relay.brevo.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/client_sasl_passwd
```

也就是說，若你的主機不能直接對外送信，建議使用 SMTP 中繼服務（例如 Brevo / SendGrid / 其他符合你需求的中繼服務）。

請修改：

- `mail_config/postfix/client_sasl_passwd`

範例：

```text
[smtp-relay.brevo.com]:587 username@example.com:your-password
```

然後重新建立資料庫：

```bash
docker exec -it mail-server postmap /etc/postfix/client_sasl_passwd
```

你也可以參考 `entrypoint.sh` 內的自動處理流程。

---

### 6.4 常用驗證命令

#### 檢查容器是否正常

```bash
docker compose ps
```

#### 檢查郵件服務狀態

```bash
docker exec -it mail-server postfix status
```

#### 檢查 Postfix 設定

```bash
docker exec -it mail-server postconf -n
```

#### 檢查 Dovecot 設定

```bash
docker exec -it mail-server dovecot -n
```

#### 看日誌

```bash
docker compose logs -f
```

#### 測試 SMTP

```bash
openssl s_client -starttls smtp -connect mail.example.com:587
```

#### 測試 IMAP

```bash
openssl s_client -connect mail.example.com:993
```

---

## 7. Docker Compose 的作用

`docker-compose.yml` 主要負責把整個郵件系統啟動起來，這裡會建立兩個容器：

### 7.1 `mail-server`

包含：

- Postfix
- Dovecot
- Supervisor
- 設定檔掛載
- 憑證路徑掛載

啟動時，`entrypoint.sh` 會執行：

```bash
postconf -e "myhostname = $POSTFIX_HOST_NAME"
postconf -e "mydomain = $POSTFIX_DOMAIN_NAME"
postmap /etc/postfix/virtualmap
postmap /etc/postfix/client_sasl_passwd
newaliases
```

也就是說，容器啟動時會把現在的環境值寫進 Postfix 的 `main.cf`。

### 7.2 `nginx`

Nginx 會：

- 監聽 80 / 443
- 讓 Certbot 可以驗證 `/.well-known/acme-challenge/`
- 提供預設的 HTTP 回應

---

## 8. 新機器部署的最簡步驟

如果你要在一台新主機上從頭部署，建議依照這個順序：

1. 開 VM，設定 Public IP、DNS、CNAME、PTR、防火牆（25 / 80 / 587 / 993 / 995）
2. 修正 `.env`，讓 `POSTFIX_HOST_NAME` 和 DNS 記錄一致
3. 修正 `mail_config/dovecot/users`、`mail_config/aliases`、`mail_config/postfix/virtualmap`、`mail_config/postfix/client_sasl_passwd`
4. 執行 `docker compose up --build -d`，讓 postfix + dovecot + nginx 先起來
5. 以 root 身分執行 `./init_cert.sh`，申請第一份 SSL cert
6. 在宿主機 crontab 中新增 renew 工作，讓 SSL 自動更新
7. 測試收發信與 IMAP 登入
8. 依實際需求再調整 `main.cf` 與轉寄設定

---

## 9. 維護與除錯建議

- 每次修改郵件設定後，建議重新啟動 `mail-server`
- 若你修改了 `aliases`，請執行 `newaliases`
- 若你修改了 Postfix 引用的 map 檔，請重新 `postmap`
- 若你新增了使用者，請確認 Dovecot 的帳密檔格式正確
- 若 SMTP 無法寄信，優先檢查：
  - 25/587 是否開放
  - `relayhost` 是否正確
  - SASL 密碼檔是否正確
  - DNS 與 MX 設定是否可解析

---

## 10. 一個簡單的總結

這個 repo 的核心思路很簡單：

- Host 端保留可編輯設定檔
- 容器內執行 Postfix + Dovecot
- 用 Docker Compose 統一啟動
- 透過 `.env` 控制主機名稱與網域
- 透過 `mail_config` 改變信箱、別名與路由
- 透過 `init_cert.sh` 綁定 Let's Encrypt

只要你把 `.env`、帳號檔與網域資訊改成你的目標環境，這個 repo 就可以作為一個可直接擴展的郵件伺服器基底。

如果你要把它部署到實際生產環境，下一步通常還需要：

- 固定 IP / DNS / MX / SPF / DKIM / DMARC
- 防垃圾信 / 封鎖清單 / 寄信監控
- 監控與保護（logrotate、fail2ban、TLS 版本限制）

這些是進一步強化郵件伺服器可靠性的後續工作。

---

<a id="chapter-14"></a>

## 11. 你可以直接照這樣做

最簡的實際操作步驟如下：

```bash
cd mailsvr_setup

# 1. 開 VM、DNS、PTR、防火牆
# 先確認 25 / 80 / 587 / 993 / 995 可用，且 mail.example.com 能解析到這台 VM

# 2. 修改 .env
nano .env

# 3. 修改信箱使用者 / 別名 / 虛擬信箱 / SMTP relay 認證
nano mail_config/dovecot/users
nano mail_config/aliases
nano mail_config/postfix/virtualmap
nano mail_config/postfix/client_sasl_passwd

# 4. 啟動服務（先讓 nginx / 80 可用）
docker compose up --build -d

# 5. 執行第一次憑證申請（以 root 身分執行）
chmod +x init_cert.sh
./init_cert.sh

# 6. 設定定期 renew（宿主機 crontab）
crontab -e
# 加入：
# 0 2 * * * docker run --rm -v /home/ubuntu/mailsvr_setup/certs:/etc/letsencrypt -v /home/ubuntu/mailsvr_setup/certbot-webroot:/var/www/certbot certbot/certbot renew --webroot --webroot-path=/var/www/certbot --quiet && docker restart nginx-proxy mail-server

# 7. 查看狀態
docker compose ps
```

這個流程的順序是：

1. 先準備 VM / DNS / 防火牆
2. 再修正 `.env` 和郵件設定檔
3. 接著執行 `docker compose up --build -d`
4. 之後以 root 身分執行 `./init_cert.sh`
5. 最後在宿主機設定 renew cron
6. 再確認服務正常運作

如果以上步驟都可以正常完成，通常就表示你已經成功把這份 repo 轉成一個新的 mail server。這時候你還要再確認：

- DNS：`MX`、`SPF`、`DMARC`、`DKIM` 正確
- 反向 DNS：Azure Public IP 的 Reverse FQDN 正確設定
- 安全群組：25 / 587 / 465 / 993 等埠能對外
- Email 轉寄與 relayhost：沒有設定錯誤

也就是說，第一次憑證申請只是開始，真正維持 mail server 長期穩定的關鍵，是「憑證 renew」與「DNS / 反向 DNS / 防火牆」同步處理。
