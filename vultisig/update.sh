#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Update brain (skip gracefully if not initialized)
if [ -d "${SCRIPT_DIR}/brain/.git" ] || [ -f "${SCRIPT_DIR}/brain/.git" ]; then
  info "Updating Brain submodule..."
  git -C "$SCRIPT_DIR" submodule update --remote --merge vultisig/brain
elif git ls-remote https://github.com/vultisig/vultisig-coding-brain.git HEAD >/dev/null 2>&1; then
  info "Brain repo now available — cloning..."
  git clone --depth 1 https://github.com/vultisig/vultisig-coding-brain.git "${SCRIPT_DIR}/brain"
else
  warn "Brain repo not available yet. Skipping brain update."
fi

info "Updating workspace files (preserving IDENTITY.md, USER.md)..."
git -C "$SCRIPT_DIR" checkout -- \
  workspace/SOUL.md workspace/SECURITY.md workspace/TOOLS.md \
  workspace/AGENTS.md workspace/CONTEXT.md workspace/PATTERNS.md \
  workspace/CODING.md workspace/scripts/

info "Update complete. Config, generated files, and cron preserved."
