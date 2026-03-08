#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

# Parse bot account from config
BOT_ACCOUNT=$(grep "github_bot_account:" "$CONFIG_FILE" 2>/dev/null | sed "s/.*: *\"\?\([^\"]*\)\"\?.*/\1/" | head -1)

echo "═══════════════════════════════════════"
echo " Vultisig Agent Status"
echo "═══════════════════════════════════════"
echo ""

# Agent process
if systemctl is-active --quiet vultisig-agent 2>/dev/null; then
  echo -e "  Agent:  ${GREEN}running (systemd)${NC}"
elif pgrep -f "openclaw start" >/dev/null 2>&1; then
  echo -e "  Agent:  ${GREEN}running (manual)${NC}"
else
  echo -e "  Agent:  ${RED}stopped${NC}"
fi

# gh auth
GH_USER=$(gh api user --jq .login 2>/dev/null || echo "not authenticated")
echo -e "  GitHub: ${GH_USER}"

# API key
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo -e "  API:    ${GREEN}Anthropic key set${NC}"
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
  echo -e "  API:    ${GREEN}OpenRouter key set${NC}"
else
  echo -e "  API:    ${YELLOW}no key in environment${NC}"
fi

# Cron
if [ -f "${HOME}/.openclaw/cron/jobs.json" ]; then
  CRON_JOBS=$(grep -c '"name"' "${HOME}/.openclaw/cron/jobs.json" 2>/dev/null || echo 0)
  echo -e "  Cron:   ${GREEN}${CRON_JOBS} jobs configured${NC}"
else
  echo -e "  Cron:   ${RED}no jobs.json${NC}"
fi

echo ""

# Open PRs by bot
if [ -n "$BOT_ACCOUNT" ]; then
  echo "Open PRs by ${BOT_ACCOUNT}:"
  gh search prs --author="$BOT_ACCOUNT" --state=open --owner=vultisig --limit=10 2>/dev/null \
    | head -10 || echo "  (could not fetch)"
fi

echo ""
