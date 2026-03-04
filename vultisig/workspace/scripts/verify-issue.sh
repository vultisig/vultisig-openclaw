#!/usr/bin/env bash
set -euo pipefail

# Verify issue quality before starting work.
# Usage: verify-issue.sh <repo> <issue-number>

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

warn()  { echo -e "${YELLOW}WARN:${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
pass()  { echo -e "${GREEN}OK:${NC} $1"; }
block() { echo -e "${RED}BLOCK:${NC} $1"; BLOCKERS=$((BLOCKERS + 1)); }

REPO="${1:?Usage: verify-issue.sh <repo> <issue-number>}"
ISSUE="${2:?Usage: verify-issue.sh <repo> <issue-number>}"

WARNINGS=0
BLOCKERS=0

echo "═══════════════════════════════════════"
echo " Issue Quality Check: ${REPO}#${ISSUE}"
echo "═══════════════════════════════════════"
echo ""

# Fetch issue body
BODY=$(gh issue view "$ISSUE" --repo "vultisig/${REPO}" --json body --jq .body 2>/dev/null || echo "")
TITLE=$(gh issue view "$ISSUE" --repo "vultisig/${REPO}" --json title --jq .title 2>/dev/null || echo "")

if [ -z "$BODY" ]; then
  block "Could not fetch issue body"
  echo ""
  echo "Result: ${BLOCKERS} blockers, ${WARNINGS} warnings"
  exit 1
fi

# ── Check frontmatter ──────────────────────────────────────────────────

if echo "$BODY" | grep -q "^type:"; then
  pass "Has frontmatter type"
else
  warn "Missing frontmatter type (bugfix/feature/refactor)"
fi

if echo "$BODY" | grep -q "files:" ; then
  pass "Has files section"
  if echo "$BODY" | grep -qE "write:.*\[.*\S.*\]"; then
    pass "Has files.write (know which files to modify)"
  else
    warn "files.write is empty — may need to explore codebase"
  fi
else
  warn "Missing files frontmatter"
fi

if echo "$BODY" | grep -q "verify:"; then
  pass "Has verify commands"
else
  warn "Missing verify commands — will use default build/test/lint"
fi

# ── Check body sections ───────────────────────────────────────────────

if echo "$BODY" | grep -qi "## Problem\|## Description"; then
  pass "Has problem/description section"
else
  block "Missing problem description — can't understand what to fix"
fi

if echo "$BODY" | grep -qi "## Solution\|## Scope\|## Must Do"; then
  pass "Has solution/scope section"
else
  warn "Missing solution/scope — may need to determine approach"
fi

if echo "$BODY" | grep -qi "## Acceptance Criteria\|## Must NOT"; then
  pass "Has acceptance criteria or boundaries"
else
  warn "Missing acceptance criteria — will use build/test/lint as baseline"
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
if [ $BLOCKERS -gt 0 ]; then
  echo -e "${RED} ${BLOCKERS} blocker(s). Comment on issue asking for clarification.${NC}"
  exit 1
elif [ $WARNINGS -gt 3 ]; then
  echo -e "${YELLOW} ${WARNINGS} warnings. Consider asking for more detail before starting.${NC}"
  exit 0
else
  echo -e "${GREEN} Issue looks good. ${WARNINGS} minor warnings.${NC}"
  exit 0
fi
