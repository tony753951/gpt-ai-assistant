#!/usr/bin/env bash
# 透過 AdGuard Home API 套用：黑名單、白名單、上游 DNS、安全瀏覽、DoH/DoT 憑證
# 用法：./apply-config.sh dns.example.com <帳號> <密碼>
# 可重複執行；修改 blocklists.txt / whitelist.txt 後再跑一次即可。
set -euo pipefail

DOMAIN="${1:?請提供網域}"
USER="${2:?請提供管理帳號}"
PASS="${3:?請提供管理密碼}"
API="${API:-http://127.0.0.1:3000/control}"
DIR="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null || { echo "需要 jq：sudo apt-get install -y jq" >&2; exit 1; }

api() {
  local method="$1" path="$2" body="${3:-}"
  curl -fsS -u "$USER:$PASS" -X "$method" -H 'Content-Type: application/json' \
    ${body:+--data "$body"} "$API$path"
}

echo "==> 上游 DNS（加密）"
api POST /dns_config "$(jq -n '{
  upstream_dns: ["https://dns.cloudflare.com/dns-query", "https://dns.google/dns-query", "https://dns.quad9.net/dns-query"],
  bootstrap_dns: ["1.1.1.1", "8.8.8.8", "9.9.9.9"],
  dnssec_enabled: true
}')"

echo "==> 開啟安全瀏覽（惡意 / 釣魚網站）"
api POST /safebrowsing/enable

echo "==> 加入黑名單"
existing="$(api GET /filtering/status | jq -r '.filters[]?.url')"
grep -vE '^\s*(#|$)' "$DIR/blocklists.txt" | while IFS='|' read -r name url; do
  if grep -qxF "$url" <<<"$existing"; then
    echo "   已存在：$name"
  else
    api POST /filtering/add_url "$(jq -n --arg n "$name" --arg u "$url" '{name:$n, url:$u, whitelist:false}')" >/dev/null
    echo "   已加入：$name"
  fi
done

echo "==> 套用白名單"
rules="$(grep -vE '^\s*(#|$)' "$DIR/whitelist.txt" | sed -E 's/^\s+|\s+$//g; s/.*/@@||&^$important/' | jq -R . | jq -s .)"
api POST /filtering/set_rules "$(jq -n --argjson r "$rules" '{rules:$r}')"

echo "==> 啟用 DoH / DoT / DoQ"
api POST /tls/configure "$(jq -n --arg d "$DOMAIN" '{
  enabled: true,
  server_name: $d,
  force_https: false,
  port_https: 443,
  port_dns_over_tls: 853,
  port_dns_over_quic: 853,
  certificate_path: ("/etc/letsencrypt/live/" + $d + "/fullchain.pem"),
  private_key_path: ("/etc/letsencrypt/live/" + $d + "/privkey.pem")
}')" >/dev/null

echo "==> 更新所有清單"
api POST /filtering/refresh '{"whitelist":false}' >/dev/null

echo
echo "完成！DoH 位址：https://${DOMAIN}/dns-query"
echo "      DoT 位址：${DOMAIN}"
echo "下一步：./make-ios-profile.sh ${DOMAIN} 產生 iPhone 描述檔"
