#!/usr/bin/env bash
# 一鍵安裝：AdGuard Home + Let's Encrypt 憑證 + 黑白名單 + iPhone 描述檔
# 用法：sudo ./setup.sh [網域] [Email]
#   不填網域時，自動使用 <你的IP>.sslip.io 免費網域
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
API="http://127.0.0.1:3000"
CRED_FILE="$DIR/data/admin-credentials.txt"

if [[ $EUID -ne 0 ]]; then
  echo "請用 sudo 執行" >&2
  exit 1
fi

echo "==> 安裝 Docker、certbot 等工具"
apt-get update -y
apt-get install -y ca-certificates curl certbot ufw jq openssl qrencode python3
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

IP="$(curl -fsS https://api.ipify.org)"
DOMAIN="${1:-${IP//./-}.sslip.io}"
EMAIL="${2:-}"
echo "==> 使用網域：$DOMAIN（VPS IP：$IP）"

echo "==> 設定防火牆（只開 SSH、80、DoH、DoT/DoQ；53 埠不對外）"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw allow 853/tcp
ufw allow 853/udp
ufw --force enable

if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
  echo "==> 申請 TLS 憑證（$DOMAIN 必須指向 $IP，且雲端安全群組已開 80 埠）"
  if [[ -n "$EMAIL" ]]; then
    certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
  else
    certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN"
  fi
fi

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/restart-adguardhome.sh <<HOOK
#!/bin/sh
docker restart adguardhome
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/restart-adguardhome.sh

echo "==> 啟動 AdGuard Home"
cd "$DIR"
docker compose up -d
for _ in $(seq 1 30); do
  curl -fsS -o /dev/null "$API" 2>/dev/null && break
  sleep 2
done

if curl -fsS -o /dev/null "$API/control/install/get_addresses" 2>/dev/null; then
  echo "==> 自動完成初始設定精靈"
  ADMIN_USER="admin"
  ADMIN_PASS="$(openssl rand -base64 18 | tr -d '/+=')"
  curl -fsS -X POST -H 'Content-Type: application/json' "$API/control/install/configure" --data "$(jq -n \
    --arg u "$ADMIN_USER" --arg p "$ADMIN_PASS" '{
      web: {ip: "0.0.0.0", port: 3000},
      dns: {ip: "0.0.0.0", port: 53},
      username: $u,
      password: $p
    }')" >/dev/null
  mkdir -p "$(dirname "$CRED_FILE")"
  printf '%s\n%s\n' "$ADMIN_USER" "$ADMIN_PASS" > "$CRED_FILE"
  chmod 600 "$CRED_FILE"
  sleep 3
elif [[ -f "$CRED_FILE" ]]; then
  echo "==> 已初始化過，沿用 $CRED_FILE 的帳密"
else
  echo "AdGuard Home 已初始化，但找不到 $CRED_FILE。請手動執行：" >&2
  echo "  ./apply-config.sh $DOMAIN <帳號> <密碼>" >&2
  exit 1
fi
{ read -r ADMIN_USER; read -r ADMIN_PASS; } < "$CRED_FILE"

"$DIR/apply-config.sh" "$DOMAIN" "$ADMIN_USER" "$ADMIN_PASS"

echo "==> 產生 iPhone 描述檔，開放 10 分鐘下載"
SERVE_DIR="$(mktemp -d)"
TOKEN="$(openssl rand -hex 8)"
mkdir -p "$SERVE_DIR/$TOKEN"
(cd "$SERVE_DIR/$TOKEN" && "$DIR/make-ios-profile.sh" "$DOMAIN" doh iphone >/dev/null)
cp "$SERVE_DIR/$TOKEN/adguard-doh-iphone.mobileconfig" "$DIR/data/"
PROFILE_URL="http://$DOMAIN/$TOKEN/adguard-doh-iphone.mobileconfig"
nohup timeout 600 python3 -c '
import http.server, sys
h = http.server.SimpleHTTPRequestHandler
h.extensions_map[".mobileconfig"] = "application/x-apple-aspen-config"
h.list_directory = lambda self, path: self.send_error(404)
http.server.ThreadingHTTPServer(("0.0.0.0", 80), lambda *a: h(*a, directory=sys.argv[1])).serve_forever()
' "$SERVE_DIR" >/dev/null 2>&1 &

cat <<MSG

==================== 安裝完成 ====================
iPhone 設定（10 分鐘內有效）：
  用 iPhone 相機掃下面的 QR Code，或用 Safari 開啟：
  $PROFILE_URL
MSG
qrencode -t ansiutf8 "$PROFILE_URL"
cat <<MSG
  下載後到「設定 → 一般 → VPN 與裝置管理」安裝描述檔。
  （逾時了就再執行一次 sudo ./setup.sh $DOMAIN）

管理介面（先在自己電腦執行 ssh -L 3000:127.0.0.1:3000 <使用者>@$IP）：
  http://localhost:3000
  帳號：$ADMIN_USER
  密碼：$ADMIN_PASS
  （帳密存在 $CRED_FILE）

DoH：https://$DOMAIN/dns-query
DoT：$DOMAIN
==================================================
MSG
