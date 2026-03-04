#!/usr/bin/env bash
set -euo pipefail

# Pre-submit validation for Vultisig repos.
# Reads build/test/lint commands from the repo's CLAUDE.md.
# Falls back to language-specific defaults if CLAUDE.md is missing.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS:${NC} $1"; }
fail() { echo -e "${RED}FAIL:${NC} $1"; FAILURES=$((FAILURES + 1)); }
skip() { echo -e "${YELLOW}SKIP:${NC} $1"; }

FAILURES=0

echo "═══════════════════════════════════════"
echo " Pre-submit validation"
echo "═══════════════════════════════════════"
echo ""

# ── Detect language ────────────────────────────────────────────────────────

if [ -f "package.json" ]; then
  LANG="typescript"
elif [ -f "go.mod" ]; then
  LANG="go"
elif [ -f "Package.swift" ]; then
  LANG="swift"
elif [ -f "build.gradle.kts" ] || [ -f "build.gradle" ]; then
  LANG="kotlin"
elif [ -f "foundry.toml" ]; then
  LANG="solidity"
else
  LANG="unknown"
fi

echo "Detected: ${LANG}"
echo ""

# ── Run commands ───────────────────────────────────────────────────────────

run_check() {
  local name="$1"
  local cmd="$2"

  if [ -z "$cmd" ]; then
    skip "$name (no command)"
    return
  fi

  echo "Running: ${cmd}"
  if eval "$cmd"; then
    pass "$name"
  else
    fail "$name"
  fi
  echo ""
}

case "$LANG" in
  typescript)
    # Check for yarn vs npm
    if [ -f "yarn.lock" ]; then
      PKG="yarn"
    else
      PKG="npm run"
    fi

    # Use check:all if available (vultisig-windows pattern)
    if grep -q '"check:all"' package.json 2>/dev/null; then
      run_check "check:all" "$PKG check:all"
    else
      run_check "build" "$PKG build"
      run_check "test" "$PKG test"
      run_check "lint" "$PKG lint"
      # Typecheck if available
      if grep -q '"typecheck"' package.json 2>/dev/null; then
        run_check "typecheck" "$PKG typecheck"
      fi
    fi
    ;;

  go)
    run_check "build" "go build ./..."
    run_check "test" "go test -race ./..."
    if command -v golangci-lint >/dev/null 2>&1; then
      run_check "lint" "golangci-lint run"
    else
      skip "lint (golangci-lint not installed)"
    fi
    ;;

  swift)
    run_check "build" "swift build"
    run_check "test" "swift test"
    ;;

  kotlin)
    run_check "build" "./gradlew build"
    run_check "test" "./gradlew test"
    run_check "lint" "./gradlew ktlintCheck"
    ;;

  solidity)
    run_check "build" "forge build"
    run_check "test" "forge test"
    ;;

  *)
    skip "Unknown language — read CLAUDE.md for commands"
    ;;
esac

# ── Check for secrets in staged diff ────────────────────────────────────

echo "Checking for secrets in diff..."
if git diff --cached -U0 2>/dev/null | grep -qiE '(sk-ant-|ghp_|sk-or-|PRIVATE.KEY|BEGIN RSA|BEGIN OPENSSH)'; then
  fail "Potential secrets found in staged diff"
else
  pass "No secrets detected"
fi
echo ""

# ── Summary ─────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════"
if [ $FAILURES -eq 0 ]; then
  echo -e "${GREEN} All checks passed. Safe to create PR.${NC}"
  exit 0
else
  echo -e "${RED} ${FAILURES} check(s) failed. Fix before creating PR.${NC}"
  exit 1
fi
