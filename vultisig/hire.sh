#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# hire.sh — Hire a Vultisig agent into your existing OpenClaw setup
# ═══════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
ask()   { echo -e "${CYAN}[?]${NC} $1"; }

OPENCLAW_DIR="${HOME}/.openclaw"
VULTISIG_DIR="${OPENCLAW_DIR}/vultisig"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Hire a Vultisig Agent"
echo "  Adds a Vultisig coding agent to your existing OpenClaw"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Check prerequisites ─────────────────────────────────────────

info "Checking prerequisites..."

[ -d "$OPENCLAW_DIR" ] || error "OpenClaw not found at ${OPENCLAW_DIR}. Install OpenClaw first: npm i -g openclaw@latest && openclaw onboard"
[ -f "${OPENCLAW_DIR}/openclaw.json" ] || error "No openclaw.json found. Run: openclaw onboard"
command -v gh >/dev/null 2>&1 || error "GitHub CLI (gh) not found. Install: https://cli.github.com"
gh auth status >/dev/null 2>&1 || error "GitHub CLI not authenticated. Run: gh auth login"
command -v git >/dev/null 2>&1 || error "Git not found."
command -v node >/dev/null 2>&1 || error "Node.js not found."

info "All prerequisites met."

# ── Step 2: Interactive config ───────────────────────────────────────────

echo ""
ask "Your name (for agent context):"
read -r DEV_NAME

ask "Your GitHub username:"
read -r GH_USERNAME

ask "Bot GitHub account (create one if you don't have it — e.g., ${GH_USERNAME}-vultisig-bot):"
read -r BOT_ACCOUNT

ask "Your timezone (e.g., Europe/Berlin, America/New_York):"
read -r TIMEZONE

ask "Repos to work on (comma-separated, e.g., vultisig-sdk,vultisig-windows,docs):"
read -r REPOS_INPUT
IFS=',' read -ra ACTIVE_REPOS <<< "$REPOS_INPUT"

ask "Where to clone repos (default: ~/vultisig-repos):"
read -r BASE_DIR
BASE_DIR="${BASE_DIR:-~/vultisig-repos}"
BASE_DIR="${BASE_DIR/#\~/$HOME}"

ask "Primary model (default: anthropic/claude-sonnet-4-6):"
read -r MODEL_PRIMARY
MODEL_PRIMARY="${MODEL_PRIMARY:-anthropic/claude-sonnet-4-6}"

ask "Cron mode — nightshift (15min polls, recommended) or active (5min polls):"
read -r CRON_MODE
CRON_MODE="${CRON_MODE:-nightshift}"

ask "Telegram bot token (leave empty to skip notifications):"
read -r TELEGRAM_BOT_TOKEN
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

TELEGRAM_CHAT_ID=""
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
  ask "Telegram chat ID:"
  read -r TELEGRAM_CHAT_ID
fi

MODEL_POLLING="anthropic/claude-haiku-4-5"

echo ""
info "Config: ${DEV_NAME} (bot: ${BOT_ACCOUNT}), ${#ACTIVE_REPOS[@]} repos, ${CRON_MODE} mode"

# ── Step 3: Download workspace + brain ──────────────────────────────────

info "Setting up Vultisig workspace at ${VULTISIG_DIR}..."
mkdir -p "$VULTISIG_DIR"

# Clone workspace files from the vultisig-openclaw repo
if [ -d "${VULTISIG_DIR}/workspace" ]; then
  info "  Workspace already exists, pulling latest..."
  git -C "${VULTISIG_DIR}" pull --ff-only 2>/dev/null || true
else
  info "  Downloading workspace files..."
  git clone --depth 1 https://github.com/vultisig/vultisig-openclaw.git "${VULTISIG_DIR}/.tmp-clone"
  mv "${VULTISIG_DIR}/.tmp-clone/vultisig/workspace" "${VULTISIG_DIR}/workspace"
  rm -rf "${VULTISIG_DIR}/.tmp-clone"
fi

# Brain submodule (optional — adds extra context but agent works without it)
if [ ! -d "${VULTISIG_DIR}/brain" ]; then
  if git ls-remote https://github.com/vultisig/vultisig-coding-brain.git HEAD >/dev/null 2>&1; then
    info "  Cloning coding brain..."
    git clone --depth 1 https://github.com/vultisig/vultisig-coding-brain.git "${VULTISIG_DIR}/brain"
  else
    warn "  Brain repo not available yet. Agent will work without it."
    warn "  Run hire.sh again later to add brain when the repo is created."
  fi
else
  info "  Brain exists, pulling latest..."
  git -C "${VULTISIG_DIR}/brain" pull --ff-only 2>/dev/null || true
fi

# Template identity files
sed "s/{{AGENT_NAME}}/${BOT_ACCOUNT}-agent/g; s/{{BOT_ACCOUNT}}/${BOT_ACCOUNT}/g" \
  "${VULTISIG_DIR}/workspace/IDENTITY.md.tmpl" > "${VULTISIG_DIR}/workspace/IDENTITY.md"

sed "s/{{DEV_NAME}}/${DEV_NAME}/g; s/{{GH_USERNAME}}/${GH_USERNAME}/g; s/{{TIMEZONE}}/${TIMEZONE}/g" \
  "${VULTISIG_DIR}/workspace/USER.md.tmpl" > "${VULTISIG_DIR}/workspace/USER.md"

info "Workspace ready."

# ── Step 4: Register Vultisig agent in openclaw.json ─────────────────────

info "Registering Vultisig agent in openclaw.json..."

# Use node to non-destructively merge agent config
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
  workspace: '${VULTISIG_DIR}/workspace',
  model: {
    primary: '${MODEL_PRIMARY}',
    fallbacks: ['anthropic/claude-haiku-4-5']
  },
  tools: {
    profile: 'coding',
    alsoAllow: ['cron', 'gateway']
  }
});

// Inject env vars (merge, don't overwrite)
if (!config.env) config.env = {};
if ('${TELEGRAM_BOT_TOKEN}') config.env.TELEGRAM_BOT_TOKEN = '${TELEGRAM_BOT_TOKEN}';
if ('${TELEGRAM_CHAT_ID}') config.env.TELEGRAM_CHAT_ID = '${TELEGRAM_CHAT_ID}';
config.env.WORKSPACE_DIR = '${VULTISIG_DIR}/workspace';

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('  Vultisig agent added to openclaw.json');
"

# ── Step 5: Merge cron jobs ──────────────────────────────────────────────

info "Adding Vultisig cron jobs..."

CRON_DIR="${OPENCLAW_DIR}/cron"
mkdir -p "$CRON_DIR"

if [ "$CRON_MODE" = "active" ]; then
  POLL_INTERVAL="*/5"
  WORK_INTERVAL="*/7"
else
  POLL_INTERVAL="*/15"
  WORK_INTERVAL="*/20"
fi

REPO_LIST=$(printf ", %s" "${ACTIVE_REPOS[@]}")
REPO_LIST="${REPO_LIST:2}"

REPO_PATHS=""
for repo in "${ACTIVE_REPOS[@]}"; do
  REPO_PATHS="${REPO_PATHS}  - ${repo}: ${BASE_DIR}/${repo}\n"
done

# Generate cron jobs as JSON, then merge into existing jobs.json
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

// Remove old vultisig jobs (idempotent)
store.jobs = store.jobs.filter(j => !j.name?.startsWith('vultisig-'));

const uuid = () => crypto.randomUUID();

// Add vultisig jobs
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

# ── Step 6: Clone repos + configure git ──────────────────────────────────

info "Cloning repos to ${BASE_DIR}..."
mkdir -p "$BASE_DIR"

for repo in "${ACTIVE_REPOS[@]}"; do
  repo=$(echo "$repo" | xargs)  # trim whitespace
  REPO_DIR="${BASE_DIR}/${repo}"
  if [ -d "$REPO_DIR" ]; then
    info "  ${repo}: already cloned"
  else
    info "  ${repo}: cloning..."
    git clone "https://github.com/vultisig/${repo}.git" "$REPO_DIR"
  fi
  git -C "$REPO_DIR" config user.name "$BOT_ACCOUNT"
  git -C "$REPO_DIR" config user.email "${BOT_ACCOUNT}@users.noreply.github.com"
done

# ── Step 7: Create labels on repos ──────────────────────────────────────

info "Creating agent labels on repos..."

LABELS=(
  "agent:assigned:#0E8A16:Issue assigned to agent"
  "agent:in-progress:#FBCA04:Agent is working on this"
  "agent:review:#1D76DB:Agent PR ready for human review"
  "agent:blocked:#D93F0B:Agent is blocked and needs help"
)

for repo in "${ACTIVE_REPOS[@]}"; do
  repo=$(echo "$repo" | xargs)
  for label_def in "${LABELS[@]}"; do
    IFS=':' read -r name color desc <<< "$label_def"
    gh label create "$name" --repo "vultisig/${repo}" --color "${color#\#}" --description "$desc" 2>/dev/null \
      && info "  ${repo}: created ${name}" \
      || true  # Label may already exist
  done
done

# ── Step 8: Verify bot access ────────────────────────────────────────────

info "Checking bot account access..."

CURRENT_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
if [ "$CURRENT_USER" = "$BOT_ACCOUNT" ]; then
  info "  gh CLI authenticated as ${BOT_ACCOUNT}."
else
  warn "  gh CLI authenticated as '${CURRENT_USER}', not '${BOT_ACCOUNT}'."
  warn "  For the agent to push branches and open PRs, you need:"
  warn "    export GH_TOKEN=<bot-account-pat>"
  warn "    gh auth setup-git"
  warn "  Or switch: gh auth login --with-token <<< '<bot-pat>'"
fi

# ── Done ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════"
info "Vultisig agent hired!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "What was set up:"
echo "  [x] Workspace files at ${VULTISIG_DIR}/workspace/"
echo "  [x] Coding brain at ${VULTISIG_DIR}/brain/"
echo "  [x] Agent 'vultisig' registered in openclaw.json"
echo "  [x] 4 cron jobs added (vultisig-issue-watcher, vultisig-ci-monitor, vultisig-pr-feedback, vultisig-work-queue)"
echo "  [x] ${#ACTIVE_REPOS[@]} repos cloned to ${BASE_DIR}/"
echo "  [x] Agent labels created on repos"
echo ""
echo "To test:"
echo "  1. Restart OpenClaw: openclaw restart (or systemctl restart openclaw)"
echo "  2. Verify: openclaw cron list (should show 4 vultisig-* jobs)"
echo "  3. Create a test issue on vultisig/${ACTIVE_REPOS[0]}"
echo "  4. Label it 'agent:assigned' and assign ${BOT_ACCOUNT}"
echo "  5. Wait $([ "$CRON_MODE" = "active" ] && echo '5' || echo '15') minutes"
echo ""
echo "To remove the agent later:"
echo "  Run: ${VULTISIG_DIR}/fire.sh"
echo ""
