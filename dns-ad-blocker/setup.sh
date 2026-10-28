#!/usr/bin/env bash
# 在全新的 Ubuntu/Debian VPS 上安裝 AdGuard Home + Let's Encrypt 憑證
# 用法：sudo ./setup.sh dns.example.com you@example.com
set -euo pipefail

DOMAIN="${1:?請提供網域，例如 dns.example.com}"
EMAIL="${2:?請提供 Email（憑證到期通知用）}"
DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "請用 sudo 執行" >&2
  exit 1
fi

echo "==> 安裝 Docker 與 certbot"
apt-get update -y
apt-get install -y ca-certificates curl certbot ufw
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

echo "==> 申請 TLS 憑證（需要 ${DOMAIN} 的 A 記錄已指向這台主機，且 80 埠可連線）"
ufw allow 80/tcp
certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"

echo "==> 憑證續期後自動重啟 AdGuard Home"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/restart-adguardhome.sh <<HOOK
#!/bin/sh
docker restart adguardhome
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/restart-adguardhome.sh

echo "==> 設定防火牆（只開 SSH、DoH、DoT/DoQ；53 埠不對外）"
ufw allow OpenSSH
ufw allow 443/tcp
ufw allow 443/udp
ufw allow 853/tcp
ufw allow 853/udp
ufw --force enable

echo "==> 啟動 AdGuard Home"
cd "$DIR"
docker compose up -d

cat <<MSG

完成！接下來：
  1. 在你自己的電腦執行：ssh -L 3000:127.0.0.1:3000 <使用者>@<VPS IP>
  2. 瀏覽器打開 http://localhost:3000 完成初始設定精靈
     - 網頁管理介面：所有介面，埠 3000
     - DNS 伺服器：所有介面，埠 53
     - 設定一組強密碼
  3. 回到 VPS 執行：./apply-config.sh ${DOMAIN} <帳號> <密碼>
MSG
