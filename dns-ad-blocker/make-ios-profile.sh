#!/usr/bin/env bash
# 產生 iPhone/iPad 用的加密 DNS 描述檔 (.mobileconfig)
# 用法：./make-ios-profile.sh dns.example.com [doh|dot] [裝置名稱]
#   裝置名稱（選填）會成為 ClientID，可在管理介面分辨是哪台手機的查詢
set -euo pipefail

DOMAIN="${1:?請提供網域}"
PROTO="${2:-doh}"
CLIENT="${3:-}"

uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen; }

case "$PROTO" in
  doh)
    PROTOCOL="HTTPS"
    SERVER_KEY="ServerURL"
    SERVER_VAL="https://${DOMAIN}/dns-query${CLIENT:+/$CLIENT}"
    ;;
  dot)
    PROTOCOL="TLS"
    SERVER_KEY="ServerName"
    SERVER_VAL="${CLIENT:+$CLIENT.}${DOMAIN}"
    ;;
  *) echo "協定只能是 doh 或 dot" >&2; exit 1 ;;
esac

OUT="adguard-${PROTO}${CLIENT:+-$CLIENT}.mobileconfig"
cat > "$OUT" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>DNSSettings</key>
      <dict>
        <key>DNSProtocol</key>
        <string>${PROTOCOL}</string>
        <key>${SERVER_KEY}</key>
        <string>${SERVER_VAL}</string>
      </dict>
      <key>OnDemandRules</key>
      <array>
        <dict>
          <key>Action</key>
          <string>Connect</string>
        </dict>
      </array>
      <key>PayloadDisplayName</key>
      <string>擋廣告 DNS (${PROTO^^})</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.dnsSettings.managed.$(uuid)</string>
      <key>PayloadType</key>
      <string>com.apple.dnsSettings.managed</string>
      <key>PayloadUUID</key>
      <string>$(uuid)</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>擋廣告 DNS - ${DOMAIN}</string>
  <key>PayloadIdentifier</key>
  <string>${DOMAIN}.dns.$(uuid)</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$(uuid)</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
XML

echo "已產生：$OUT"
echo "把檔案用 AirDrop / Email / 網址傳到 iPhone 開啟，"
echo "再到「設定 → 一般 → VPN 與裝置管理」安裝，"
echo "最後到「設定 → 一般 → VPN 與裝置管理 → DNS」確認已選取。"
