#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yml"

# ── Step 1: Validate prerequisites ──────────────────────────────────────────

info "Checking prerequisites..."

command -v node >/dev/null 2>&1 || error "Node.js not found. Install Node 22+."
NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
[ "$NODE_VERSION" -ge 22 ] || error "Node.js 22+ required (found v${NODE_VERSION})."

command -v gh >/dev/null 2>&1 || error "GitHub CLI (gh) not found. Install: https://cli.github.com"
gh auth status >/dev/null 2>&1 || error "GitHub CLI not authenticated. Run: gh auth login"

command -v openclaw >/dev/null 2>&1 || error "OpenClaw not found. Install: npm i -g @anthropic/openclaw"

command -v git >/dev/null 2>&1 || error "Git not found."

info "All prerequisites met."

# ── Step 2: Read config ─────────────────────────────────────────────────────

[ -f "$CONFIG_FILE" ] || error "config.yml not found. Copy config.example.yml to config.yml and fill it in."

# Parse YAML (simple grep-based, no yq dependency)
parse_yaml() {
  grep "^  $1:" "$CONFIG_FILE" | sed "s/.*: *\"\?\([^\"]*\)\"\?.*/\1/" | head -1
}

parse_yaml_list() {
  local in_section=false
  local section="$1"
  while IFS= read -r line; do
    if echo "$line" | grep -q "^  ${section}:"; then
      in_section=true
      continue
    fi
    if $in_section; then
      if echo "$line" | grep -q "^    -"; then
        echo "$line" | sed 's/.*- *//'
      else
        break
      fi
    fi
  done < "$CONFIG_FILE"
}

DEV_NAME=$(parse_yaml "name")
GH_USERNAME=$(parse_yaml "github_username")
BOT_ACCOUNT=$(parse_yaml "github_bot_account")
TIMEZONE=$(parse_yaml "timezone")
TELEGRAM_BOT_TOKEN=$(parse_yaml "telegram_bot_token")
TELEGRAM_CHAT_ID=$(parse_yaml "telegram_chat_id")
BASE_DIR=$(parse_yaml "base_dir")
BASE_DIR="${BASE_DIR/#\~/$HOME}"
MODEL_PRIMARY=$(parse_yaml "model_primary")
MODEL_POLLING=$(parse_yaml "model_polling")
CRON_MODE=$(grep "^cron_mode:" "$CONFIG_FILE" | sed "s/.*: *\"\?\([^\"]*\)\"\?.*/\1/" || echo "nightshift")

ACTIVE_REPOS=()
while IFS= read -r repo; do
  [ -n "$repo" ] && ACTIVE_REPOS+=("$repo")
done < <(parse_yaml_list "active")

[ -n "$DEV_NAME" ] || error "developer.name not set in config.yml"
[ -n "$BOT_ACCOUNT" ] || error "developer.github_bot_account not set in config.yml"
[ ${#ACTIVE_REPOS[@]} -gt 0 ] || error "repos.active is empty in config.yml"

info "Config loaded: ${DEV_NAME} (bot: ${BOT_ACCOUNT}), ${#ACTIVE_REPOS[@]} repos, cron: ${CRON_MODE}"

# ── Step 3: Verify API key ─────────────────────────────────────────────────

info "Checking API key..."

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  info "Anthropic API key found in environment."
elif [ -n "${OPENROUTER_API_KEY:-}" ]; then
  info "OpenRouter API key found in environment."
else
  warn "No API key found in environment (ANTHROPIC_API_KEY or OPENROUTER_API_KEY)."
  warn "Make sure your API key is configured via OpenClaw's standard setup."
  warn "Agent will fail to start without an API key."
fi

# ── Step 4: Verify git push auth ───────────────────────────────────────────

info "Checking git authentication..."

CURRENT_USER=$(gh api user --jq .login 2>/dev/null || echo "")
if [ "$CURRENT_USER" = "$BOT_ACCOUNT" ]; then
  info "gh CLI authenticated as ${BOT_ACCOUNT}."
else
  warn "gh CLI authenticated as '${CURRENT_USER}', expected '${BOT_ACCOUNT}'."
  warn "Make sure GH_TOKEN is set or run: gh auth login as the bot."
fi

# Ensure git can push via gh credentials
gh auth setup-git 2>/dev/null || warn "Could not run 'gh auth setup-git'. Git push may require manual auth config."

# ── Step 5: Clone repos ────────────────────────────────────────────────────

info "Setting up repos in ${BASE_DIR}..."
mkdir -p "$BASE_DIR"

for repo in "${ACTIVE_REPOS[@]}"; do
  REPO_DIR="${BASE_DIR}/${repo}"
  if [ -d "$REPO_DIR" ]; then
    info "  ${repo}: already cloned, pulling latest..."
    git -C "$REPO_DIR" pull --ff-only 2>/dev/null || warn "  ${repo}: pull failed (maybe on a branch), skipping"
  else
    info "  ${repo}: cloning..."
    git clone "https://github.com/vultisig/${repo}.git" "$REPO_DIR"
  fi

  # Configure git user for bot commits
  git -C "$REPO_DIR" config user.name "$BOT_ACCOUNT"
  git -C "$REPO_DIR" config user.email "${BOT_ACCOUNT}@users.noreply.github.com"
done

# ── Step 5b: Create agent labels on repos ──────────────────────────────────

info "Creating agent labels on repos..."

LABELS=(
  "agent:assigned:#0E8A16:Issue assigned to agent"
  "agent:in-progress:#FBCA04:Agent is working on this"
  "agent:review:#1D76DB:Agent PR ready for human review"
  "agent:blocked:#D93F0B:Agent is blocked and needs help"
)

for repo in "${ACTIVE_REPOS[@]}"; do
  for label_def in "${LABELS[@]}"; do
    IFS=':' read -r name color desc <<< "$label_def"
    gh label create "$name" --repo "vultisig/${repo}" --color "${color#\#}" --description "$desc" 2>/dev/null || true
  done
  info "  ${repo}: labels ready"
done

# ── Step 6: Generate OpenClaw config ────────────────────────────────────────

info "Generating OpenClaw configuration..."

OPENCLAW_DIR="${HOME}/.openclaw"
mkdir -p "$OPENCLAW_DIR"

AGENT_NAME="${BOT_ACCOUNT}-agent"

if [ -f "${OPENCLAW_DIR}/openclaw.json" ]; then
  # Existing config found — merge non-destructively (same approach as hire.sh)
  info "Existing openclaw.json found. Merging Vultisig agent (preserving your config)..."

  node -e "
const fs = require('fs');
const configPath = '${OPENCLAW_DIR}/openclaw.json';
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

// Ensure agents section exists
if (!config.agents) config.agents = {};
if (!config.agents.list) config.agents.list = [];

// Remove existing vultisig agent if present (idempotent)
config.agents.list = config.agents.list.filter(a => a.id !== 'vultisig');

// Add vultisig agent
config.agents.list.push({
  id: 'vultisig',
  default: true,
  workspace: '${SCRIPT_DIR}/workspace',
  model: {
    primary: '${MODEL_PRIMARY}',
    fallbacks: ['anthropic/claude-haiku-4-5']
  },
  tools: {
    profile: 'coding',
    alsoAllow: ['cron', 'gateway']
  }
});

// Merge env vars (don't overwrite existing)
if (!config.env) config.env = {};
if ('${TELEGRAM_BOT_TOKEN}') config.env.TELEGRAM_BOT_TOKEN = '${TELEGRAM_BOT_TOKEN}';
if ('${TELEGRAM_CHAT_ID}') config.env.TELEGRAM_CHAT_ID = '${TELEGRAM_CHAT_ID}';
config.env.WORKSPACE_DIR = '${SCRIPT_DIR}/workspace';

// Ensure gateway is set
if (!config.gateway) config.gateway = {};
if (!config.gateway.port) config.gateway.port = 18789;

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('  Vultisig agent merged into existing openclaw.json');
"

else
  # Fresh install — write full config
  info "No existing config. Creating openclaw.json..."

  cat > "${OPENCLAW_DIR}/openclaw.json" << OCEOF
{
  "env": {
    "TELEGRAM_BOT_TOKEN": "${TELEGRAM_BOT_TOKEN}",
    "TELEGRAM_CHAT_ID": "${TELEGRAM_CHAT_ID}",
    "WORKSPACE_DIR": "${SCRIPT_DIR}/workspace"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${MODEL_PRIMARY}",
        "fallbacks": ["anthropic/claude-haiku-4-5"]
      },
      "workspace": "${SCRIPT_DIR}/workspace",
      "memorySearch": {
        "enabled": true,
        "sources": ["memory"]
      }
    },
    "list": [
      {
        "id": "vultisig",
        "default": true,
        "workspace": "${SCRIPT_DIR}/workspace",
        "tools": {
          "profile": "coding",
          "alsoAllow": ["cron", "gateway"]
        }
      }
    ]
  },
  "gateway": {
    "port": 18789
  }
}
OCEOF

  info "OpenClaw config created."
fi

# ── Step 7: Copy workspace files ────────────────────────────────────────────

info "Setting up workspace files..."

# Template IDENTITY.md
sed "s/{{AGENT_NAME}}/${AGENT_NAME}/g; s/{{BOT_ACCOUNT}}/${BOT_ACCOUNT}/g" \
  "${SCRIPT_DIR}/workspace/IDENTITY.md.tmpl" > "${SCRIPT_DIR}/workspace/IDENTITY.md"

# Template USER.md
sed "s/{{DEV_NAME}}/${DEV_NAME}/g; s/{{GH_USERNAME}}/${GH_USERNAME}/g; s/{{TIMEZONE}}/${TIMEZONE}/g" \
  "${SCRIPT_DIR}/workspace/USER.md.tmpl" > "${SCRIPT_DIR}/workspace/USER.md"

info "Workspace files configured."

# ── Step 8: Init Brain submodule (optional) ─────────────────────────────────

info "Initializing Brain submodule..."
if [ ! -d "${SCRIPT_DIR}/brain/.git" ] && [ ! -f "${SCRIPT_DIR}/brain/.git" ]; then
  if git ls-remote https://github.com/vultisig/vultisig-coding-brain.git HEAD >/dev/null 2>&1; then
    git -C "$SCRIPT_DIR" submodule add https://github.com/vultisig/vultisig-coding-brain.git brain 2>/dev/null || {
      git -C "$SCRIPT_DIR" submodule update --init --recursive
    }
    info "Brain submodule ready."
  else
    warn "Brain repo not available yet (vultisig/vultisig-coding-brain)."
    warn "Agent will work without it — brain adds extra context for complex tasks."
    warn "Run './update.sh' later to pull brain when the repo is created."
  fi
else
  info "Brain submodule already initialized."
fi

# ── Step 9: Inject cron jobs ───────────────────────────────────────────────

info "Setting up cron jobs (mode: ${CRON_MODE})..."

CRON_DIR="${HOME}/.openclaw/cron"
mkdir -p "$CRON_DIR"

# Set intervals based on mode
# Polling crons (haiku) run frequently — cheap lookups.
# Work cron (primary model) runs slightly offset — does real coding.
if [ "$CRON_MODE" = "active" ]; then
  POLL_INTERVAL="*/5"
  WORK_INTERVAL="*/7"
else
  # nightshift (default)
  POLL_INTERVAL="*/15"
  WORK_INTERVAL="*/20"
fi

# Build repo list for cron prompts
REPO_LIST=$(printf ", %s" "${ACTIVE_REPOS[@]}")
REPO_LIST="${REPO_LIST:2}"  # trim leading ", "

# Build repo paths for cron prompts
REPO_PATHS=""
for repo in "${ACTIVE_REPOS[@]}"; do
  REPO_PATHS="${REPO_PATHS}  - ${repo}: ${BASE_DIR}/${repo}\n"
done

# Merge cron jobs non-destructively (preserves existing jobs from other setups)
# NOTE: jobs.json format uses CronStoreFile wrapper. Verify exact schema
# against OpenClaw source (src/cron/store.ts) during pilot.
node -e "
const fs = require('fs');
const crypto = require('crypto');
const cronPath = '${CRON_DIR}/jobs.json';

// Load existing jobs (handle both array and object formats)
let store = { jobs: [] };
if (fs.existsSync(cronPath)) {
  try {
    const raw = JSON.parse(fs.readFileSync(cronPath, 'utf8'));
    if (Array.isArray(raw)) store.jobs = raw;
    else if (raw.jobs) store = raw;
    else store.jobs = [];
  } catch { store = { jobs: [] }; }
}

// Remove old vultisig jobs (idempotent — safe to re-run)
store.jobs = store.jobs.filter(j => !j.name?.startsWith('vultisig-'));

const uuid = () => crypto.randomUUID();

store.jobs.push(
  {
    jobId: uuid(),
    name: 'vultisig-issue-watcher',
    enabled: true,
    agentId: 'vultisig',
    schedule: { kind: 'cron', expr: '${POLL_INTERVAL} * * * *', tz: '${TIMEZONE}' },
    sessionTarget: 'isolated',
    wakeMode: 'now',
    payload: {
      kind: 'agentTurn',
      message: \`LOOKUP ONLY — do NOT implement code. Check for GitHub issues labeled 'agent:assigned' on repos: ${REPO_LIST}. For each found: 1) Add label 'agent:in-progress', remove 'agent:assigned'. 2) Comment 'Picked up. Working on it.' If no issues found, respond 'No new issues.' and stop.\`,
      model: '${MODEL_POLLING}',
      timeoutSeconds: 60
    },
    delivery: { mode: 'none' }
  },
  {
    jobId: uuid(),
    name: 'vultisig-ci-monitor',
    enabled: true,
    agentId: 'vultisig',
    schedule: { kind: 'cron', expr: '${POLL_INTERVAL} * * * *', tz: '${TIMEZONE}' },
    sessionTarget: 'isolated',
    wakeMode: 'now',
    payload: {
      kind: 'agentTurn',
      message: \`LOOKUP ONLY — do NOT fix code. Check CI status on open PRs authored by ${BOT_ACCOUNT} on repos: ${REPO_LIST}. Report which PRs have passing CI and which have failures. If no open PRs or all green, respond 'All clear.' and stop.\`,
      model: '${MODEL_POLLING}',
      timeoutSeconds: 60
    },
    delivery: { mode: 'none' }
  },
  {
    jobId: uuid(),
    name: 'vultisig-pr-feedback',
    enabled: true,
    agentId: 'vultisig',
    schedule: { kind: 'cron', expr: '${POLL_INTERVAL} * * * *', tz: '${TIMEZONE}' },
    sessionTarget: 'isolated',
    wakeMode: 'now',
    payload: {
      kind: 'agentTurn',
      message: \`LOOKUP ONLY — do NOT write code. Check for new review comments on open PRs by ${BOT_ACCOUNT} on repos: ${REPO_LIST}. Report which PRs have unaddressed feedback. If no new comments, respond 'No new feedback.' and stop.\`,
      model: '${MODEL_POLLING}',
      timeoutSeconds: 60
    },
    delivery: { mode: 'none' }
  },
  {
    jobId: uuid(),
    name: 'vultisig-work-queue',
    enabled: true,
    agentId: 'vultisig',
    schedule: { kind: 'cron', expr: '${WORK_INTERVAL} * * * *', tz: '${TIMEZONE}' },
    sessionTarget: 'isolated',
    wakeMode: 'now',
    payload: {
      kind: 'agentTurn',
      message: \`Process pending work on repos: ${REPO_LIST}. Check in order:\n\n1. ISSUES: Any issues labeled 'agent:in-progress' without an open PR by ${BOT_ACCOUNT}? If yes: read the issue, read repo CLAUDE.md + AGENTS.md, cd into the repo, create branch, implement, test, commit, push, open PR, notify via Telegram.\n\n2. CI FIXES: Any open PRs by ${BOT_ACCOUNT} with failed CI? If yes: first check PR comments for previous 'CI fix attempt N/3' comments to count attempts. If attempts >= 3, label 'agent:blocked', comment 'CI fix attempts exhausted (3/3). Escalating to human.', notify, and move on. Otherwise: read CI logs, checkout branch, fix, commit, push, then comment 'CI fix attempt N/3'.\n\n3. FEEDBACK: Any open PRs by ${BOT_ACCOUNT} with unaddressed review comments? If yes: first check PR comments for previous 'Feedback round N/3' comments to count rounds. If rounds >= 3, label 'agent:blocked', comment 'Feedback rounds exhausted (3/3). Escalating to human.', notify, and move on. Otherwise: read comments, checkout branch, address feedback, commit, push, comment 'Feedback round N/3. Feedback addressed.' If all feedback addressed + CI green: mark ready for review, label 'agent:review', notify.\n\nIf nothing to do, respond 'No pending work.' and stop.\n\nRepo paths:\n${REPO_PATHS}Bot account: ${BOT_ACCOUNT}.\`,
      model: '${MODEL_PRIMARY}',
      timeoutSeconds: 600
    },
    delivery: { mode: 'none' }
  }
);

fs.writeFileSync(cronPath, JSON.stringify(store, null, 2));
console.log('  4 cron jobs added (prefixed vultisig-)');
"

info "Cron jobs configured."

# ── Step 10: Generate systemd service ──────────────────────────────────────

info "Generating systemd service file..."

CURRENT_USER=$(whoami)

cat > "${SCRIPT_DIR}/vultisig-agent.service" << SVCEOF
[Unit]
Description=Vultisig Dev Agent (${BOT_ACCOUNT})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${SCRIPT_DIR}
ExecStart=$(command -v openclaw) start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vultisig-agent

[Install]
WantedBy=multi-user.target
SVCEOF

info "Systemd service file generated: vultisig-agent.service"
info "To install: sudo cp vultisig-agent.service /etc/systemd/system/ && sudo systemctl enable --now vultisig-agent"

# ── Step 11: Verification ─────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════════════════"
info "Setup complete!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Verification checklist:"
echo "  [$([ -n "${ANTHROPIC_API_KEY:-}${OPENROUTER_API_KEY:-}" ] && echo 'x' || echo ' ')] API key configured (env var)"
echo "  [$([ -d "$BASE_DIR" ] && echo 'x' || echo ' ')] Repos cloned to ${BASE_DIR}"
echo "  [$([ -f "${HOME}/.openclaw/openclaw.json" ] && echo 'x' || echo ' ')] OpenClaw config generated"
echo "  [$([ -f "${SCRIPT_DIR}/workspace/IDENTITY.md" ] && echo 'x' || echo ' ')] Workspace files templated"
echo "  [$([ -d "${SCRIPT_DIR}/brain" ] && echo 'x' || echo ' ')] Brain submodule initialized"
echo "  [$([ -f "${CRON_DIR}/jobs.json" ] && echo 'x' || echo ' ')] Cron jobs configured (${CRON_MODE})"
echo "  [$([ -f "${SCRIPT_DIR}/vultisig-agent.service" ] && echo 'x' || echo ' ')] Systemd service file generated"
echo ""
echo "Next steps:"
echo "  1. Start agent: cd ${SCRIPT_DIR} && openclaw start"
echo "  2. Or install as service: sudo cp vultisig-agent.service /etc/systemd/system/ && sudo systemctl enable --now vultisig-agent"
echo "  3. Create an issue on a repo, label 'agent:assigned', assign ${BOT_ACCOUNT}"
echo "  4. Watch agent pick it up within $([ "$CRON_MODE" = "active" ] && echo '5' || echo '15') minutes"
echo ""
