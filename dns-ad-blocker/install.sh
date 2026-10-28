#!/usr/bin/env bash
# 一行安裝：curl -fsSL https://raw.githubusercontent.com/tony753951/gpt-ai-assistant/main/dns-ad-blocker/install.sh | sudo bash -s -- [網域] [Email]
set -euo pipefail

REPO="https://github.com/tony753951/gpt-ai-assistant.git"
BRANCH="${BRANCH:-main}"
TARGET="/opt/gpt-ai-assistant"

apt-get update -y
apt-get install -y git
if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" pull --ff-only
else
  git clone --depth 1 -b "$BRANCH" "$REPO" "$TARGET"
fi
exec "$TARGET/dns-ad-blocker/setup.sh" "$@"
