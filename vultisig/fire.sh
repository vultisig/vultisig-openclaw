#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }

OPENCLAW_DIR="${HOME}/.openclaw"

echo ""
echo "Removing Vultisig agent from OpenClaw..."
echo ""

# Remove agent from openclaw.json
node -e "
const fs = require('fs');
const p = '${OPENCLAW_DIR}/openclaw.json';
const c = JSON.parse(fs.readFileSync(p, 'utf8'));
if (c.agents?.list) {
  c.agents.list = c.agents.list.filter(a => a.id !== 'vultisig');
  fs.writeFileSync(p, JSON.stringify(c, null, 2));
  console.log('  Agent removed from openclaw.json');
}
"

# Remove cron jobs
node -e "
const fs = require('fs');
const p = '${OPENCLAW_DIR}/cron/jobs.json';
if (fs.existsSync(p)) {
  const raw = JSON.parse(fs.readFileSync(p, 'utf8'));
  const jobs = Array.isArray(raw) ? raw : (raw.jobs || []);
  const filtered = jobs.filter(j => !j.name?.startsWith('vultisig-'));
  const store = Array.isArray(raw) ? filtered : { ...raw, jobs: filtered };
  fs.writeFileSync(p, JSON.stringify(store, null, 2));
  console.log('  Cron jobs removed');
}
"

info "Vultisig agent removed. Restart OpenClaw to apply."
info "Workspace files left at ${OPENCLAW_DIR}/vultisig/ (delete manually if wanted)."
info "Cloned repos left in place (delete manually if wanted)."
