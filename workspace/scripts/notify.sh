#!/usr/bin/env bash
set -euo pipefail

# Send a Telegram notification.
# Usage: notify.sh "<message>"
#
# Requires env vars: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
# If not set, silently skips (notifications are optional).

MESSAGE="${1:?Usage: notify.sh \"<message>\"}"

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  # Notifications not configured — skip silently
  exit 0
fi

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="${MESSAGE}" \
  -d parse_mode="Markdown" \
  >/dev/null 2>&1 || true

# Never fail the workflow because of a notification error
