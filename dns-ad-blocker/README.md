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
2. 一個網域，新增 A 記錄：`dns.你的網域` → VPS 公網 IP
3. 雲端主控台的安全群組 / 防火牆開放：TCP 22、80、443、853，UDP 443、853

## 安裝步驟

```bash
# 1) 在 VPS 上取得本資料夾
git clone -b claude/dns-ad-blocker-xm025x https://github.com/tony753951/gpt-ai-assistant.git
cd gpt-ai-assistant/dns-ad-blocker

# 2) 安裝 Docker、申請憑證、設定防火牆、啟動 AdGuard Home
sudo ./setup.sh dns.example.com you@example.com
```

3) 在**你自己的電腦**開 SSH 通道，再用瀏覽器打開 <http://localhost:3000> 完成初始精靈：

```bash
ssh -L 3000:127.0.0.1:3000 ubuntu@<VPS IP>
```

- 網頁管理介面：所有介面、埠 **3000**
- DNS 伺服器：所有介面、埠 **53**
- 設定帳號與強密碼

4) 回到 VPS 套用所有設定（黑名單、白名單、上游 DNS、DoH/DoT）：

```bash
sudo apt-get install -y jq
./apply-config.sh dns.example.com <帳號> <密碼>
```

## iPhone 設定

```bash
./make-ios-profile.sh dns.example.com doh iphone   # 產生 adguard-doh-iphone.mobileconfig
```

1. 把 `.mobileconfig` 用 AirDrop / Email 傳到 iPhone，點開
2. **設定 → 一般 → VPN 與裝置管理** → 安裝描述檔
3. 同一頁的 **DNS** 項目確認已選取「擋廣告 DNS」
4. 打開常用 App，再到管理介面「查詢記錄」就能看到被擋的廣告網域

> 第三個參數 `iphone` 是 ClientID，會出現在查詢記錄中，方便分辨多台裝置。
> 不需要可省略；若想改用 DoT，把 `doh` 換成 `dot`。

## 白名單（App 壞掉時）

1. 管理介面 → **查詢記錄** → 篩選「已封鎖」，找出那個 App 被擋的網域
2. 加到 `whitelist.txt`（一行一個網域，子網域會一併放行）
3. 重新執行 `./apply-config.sh dns.example.com <帳號> <密碼>`

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
| `setup.sh` | VPS 一鍵安裝（Docker、憑證、防火牆） |
| `apply-config.sh` | 透過 API 套用黑白名單、上游 DNS、TLS，可重複執行 |
| `blocklists.txt` | 黑名單清單（`名稱|網址`） |
| `whitelist.txt` | 白名單網域 |
| `make-ios-profile.sh` | 產生 iPhone 加密 DNS 描述檔 |
