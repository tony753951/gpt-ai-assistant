# 擋手機 App 廣告的 DNS（AdGuard Home + iPhone 加密 DNS）

在雲端 VPS 架一台 [AdGuard Home](https://github.com/AdguardTeam/AdGuardHome)，
iPhone 安裝一個描述檔後，不論在 Wi-Fi 或 4G/5G，App 的廣告、追蹤、惡意網站都會在 DNS 層被擋掉。

```
iPhone ──(DoH 443 / DoT 853，加密)──▶ VPS 上的 AdGuard Home ──(加密)──▶ Cloudflare / Google / Quad9
                                        └─ 命中黑名單 → 回傳 0.0.0.0（廣告載不出來）
```

## 功能

| 需求 | 做法 |
|---|---|
| 擋 App 廣告 | AdGuard DNS filter、HaGeZi Multi PRO、OISD Big |
| 中文 / 台灣 App 廣告 | anti-AD、AdRules DNS |
| 擋追蹤 / 惡意 / 釣魚 | HaGeZi Threat Intelligence、Phishing Army、AdGuard 安全瀏覽 |
| 加密 DNS | DoH (`https://網域/dns-query`)、DoT/DoQ (853)，Let's Encrypt 憑證自動續期 |
| 白名單 | 編輯 `whitelist.txt` 後重跑 `apply-config.sh` |

## 準備

1. 一台 Ubuntu 22.04+/Debian 12 的 VPS（Oracle Cloud 免費方案、GCP、Linode、Vultr 皆可，1 GB RAM 足夠）
2. 雲端主控台的安全群組 / 防火牆開放：TCP 22、80、443、853，UDP 443、853
3. （選填）自己的網域，A 記錄指向 VPS 公網 IP。沒有的話會自動使用免費的 `<IP>.sslip.io`（共用網域，偶爾可能碰到憑證申請次數上限，失敗時稍後再試或改用自己的網域）

## 一鍵安裝

SSH 登入 VPS 後執行這一行：

```bash
curl -fsSL https://raw.githubusercontent.com/tony753951/gpt-ai-assistant/main/dns-ad-blocker/install.sh | sudo bash
```

有自己的網域就加在後面（Email 選填，用來接收憑證到期通知）：

```bash
curl -fsSL https://raw.githubusercontent.com/tony753951/gpt-ai-assistant/main/dns-ad-blocker/install.sh | sudo bash -s -- dns.example.com you@example.com
```

> PR 還沒合併前，請改用分支網址：把 `main` 換成 `claude/dns-ad-blocker-xm025x`，並在 `sudo` 後加上 `BRANCH=claude/dns-ad-blocker-xm025x`。

腳本會自動：安裝 Docker → 申請 HTTPS 憑證 → 設定防火牆 → 啟動 AdGuard Home →
完成初始設定（隨機產生管理密碼）→ 套用黑白名單 → 產生 iPhone 描述檔並顯示 **QR Code**。

## iPhone 設定

1. 用 iPhone 相機掃描終端機上的 QR Code（或用 Safari 開啟顯示的網址），**10 分鐘內有效**
2. 允許下載描述檔
3. **設定 → 一般 → VPN 與裝置管理** → 安裝描述檔
4. 同一頁的 **DNS** 項目確認已選取「擋廣告 DNS」

逾時了就在 VPS 上重跑 `sudo /opt/gpt-ai-assistant/dns-ad-blocker/setup.sh <網域>`，會再產生一次。
描述檔也會存在 `/opt/gpt-ai-assistant/dns-ad-blocker/data/adguard-doh-iphone.mobileconfig`。

## 管理介面

管理介面只能透過 SSH 通道進入。在**你自己的電腦**執行：

```bash
ssh -L 3000:127.0.0.1:3000 ubuntu@<VPS IP>
```

再用瀏覽器打開 <http://localhost:3000>。帳號密碼在安裝完成畫面，也存在 VPS 的
`/opt/gpt-ai-assistant/dns-ad-blocker/data/admin-credentials.txt`。
到「查詢記錄」可看到哪些廣告網域被擋。

## 白名單（App 壞掉時）

1. 管理介面 → **查詢記錄** → 篩選「已封鎖」，找出那個 App 被擋的網域
2. 加到 `whitelist.txt`（一行一個網域，子網域會一併放行）
3. 重新執行 `sudo /opt/gpt-ai-assistant/dns-ad-blocker/setup.sh <網域>`（或 `./apply-config.sh <網域> <帳號> <密碼>`）

也可直接在查詢記錄點「解除封鎖」，但寫在 `whitelist.txt` 方便日後重建。

## 安全性說明

- **53 埠不對外開放**：公開的 53 埠會被當成開放解析器拿去做 DDoS 放大攻擊，手機只用加密的 443/853。
- **管理介面 3000 埠只綁 127.0.0.1**：只能透過 SSH 通道進入。
  注意：啟用 TLS 後管理介面也能從 `https://網域/` 開啟，請務必使用強密碼。
- 若想只讓自己的手機使用：管理介面 → 設定 → DNS 設定 → **允許的用戶端**，填入你的 ClientID（例如 `iphone`），
  其他未帶 ClientID 的查詢就會被拒絕。

## 限制

- DNS 擋廣告無法擋掉「和內容同網域」的廣告，例如 **YouTube、Facebook、Instagram 的內嵌廣告**。
- 少數 App 會寫死自己的 DNS 或使用自家加密通道，這類 App 無法透過 DNS 過濾。

## 檔案說明

| 檔案 | 用途 |
|---|---|
| `docker-compose.yml` | AdGuard Home 容器與埠號設定 |
| `install.sh` | 一行安裝入口：下載本專案並執行 `setup.sh` |
| `setup.sh` | 完整安裝流程（Docker、憑證、防火牆、初始設定、描述檔 QR Code），可重複執行 |
| `apply-config.sh` | 透過 API 套用黑白名單、上游 DNS、TLS，可重複執行 |
| `blocklists.txt` | 黑名單清單（`名稱|網址`） |
| `whitelist.txt` | 白名單網域 |
| `make-ios-profile.sh` | 單獨產生 iPhone 加密 DNS 描述檔（例如多台裝置用不同 ClientID） |
