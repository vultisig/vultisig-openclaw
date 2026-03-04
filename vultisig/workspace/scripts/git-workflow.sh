#!/usr/bin/env bash
set -euo pipefail

# Deterministic git workflow for Vultisig Dev Agent.
# Usage:
#   git-workflow.sh branch <issue-number> <slug>
#   git-workflow.sh commit "<message>"
#   git-workflow.sh push
#   git-workflow.sh pr <issue-number> [title]

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
err() { echo -e "${RED}ERROR:${NC} $1" >&2; exit 1; }
ok()  { echo -e "${GREEN}OK:${NC} $1"; }

CMD="${1:-}"
shift || true

case "$CMD" in

  branch)
    ISSUE="${1:?Usage: git-workflow.sh branch <issue-number> <slug>}"
    SLUG="${2:?Usage: git-workflow.sh branch <issue-number> <slug>}"

    # Sanitize slug: lowercase, hyphens, max 50 chars, no trailing hyphen
    SLUG=$(echo "$SLUG" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | cut -c1-50 | sed 's/-$//')
    BRANCH="agent/${ISSUE}-${SLUG}"

    # Clean state: stash any dirty work from previous tasks
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Dirty working tree detected. Stashing before switching."
      git stash --include-untracked -m "auto-stash before agent/${ISSUE}"
    fi

    # Ensure on main and up to date
    git checkout main 2>/dev/null || git checkout master
    git pull --ff-only

    # Create branch
    git checkout -b "$BRANCH"
    ok "Created branch: $BRANCH"
    ;;

  commit)
    MSG="${1:?Usage: git-workflow.sh commit \"<message>\"}"

    # Validate conventional commit prefix
    if ! echo "$MSG" | grep -qE '^(fix|feat|refactor|docs|test|chore|ci|perf|build|style|revert):'; then
      err "Commit message must start with conventional prefix (fix:, feat:, refactor:, etc.)"
    fi

    # Validate length
    FIRST_LINE=$(echo "$MSG" | head -1)
    if [ ${#FIRST_LINE} -gt 72 ]; then
      err "First line must be ≤72 characters (got ${#FIRST_LINE})"
    fi

    # Check for secrets in staged files
    if git diff --cached --name-only | grep -qiE '\.(env|pem|key|p12|pfx|jks)$'; then
      err "Staged files contain potential secrets. Remove them before committing."
    fi

    if git diff --cached -U0 | grep -qiE '(sk-ant-|ghp_|sk-or-|PRIVATE.KEY|BEGIN RSA)'; then
      err "Staged diff contains potential secrets. Review and remove."
    fi

    # Commit with heredoc (preserves formatting)
    git commit -m "$(cat <<EOF
${MSG}

Co-Authored-By: Vultisig Agent <noreply@vultisig.com>
EOF
)"
    ok "Committed: ${FIRST_LINE}"
    ;;

  push)
    BRANCH=$(git branch --show-current)

    # Never push to main
    if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
      err "Cannot push to ${BRANCH}. Work on a branch."
    fi

    # Enforce pre-submit gate before pushing
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/pre-submit.sh" ]; then
      echo "Running pre-submit gate before push..."
      if ! "${SCRIPT_DIR}/pre-submit.sh"; then
        err "Pre-submit gate failed. Fix issues before pushing."
      fi
      # Write flag so PR creation can verify
      echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $BRANCH" > /tmp/.agent-presubmit-pass
    fi

    git push -u origin "$BRANCH"
    ok "Pushed: $BRANCH"
    ;;

  pr)
    ISSUE="${1:?Usage: git-workflow.sh pr <issue-number> [title]}"
    TITLE="${2:-}"
    BRANCH=$(git branch --show-current)

    # Verify pre-submit passed for this branch
    if [ -f /tmp/.agent-presubmit-pass ]; then
      PASS_BRANCH=$(tail -1 /tmp/.agent-presubmit-pass | awk '{print $2}')
      if [ "$PASS_BRANCH" != "$BRANCH" ]; then
        err "Pre-submit passed for '${PASS_BRANCH}' but current branch is '${BRANCH}'. Run push first."
      fi
    else
      err "No pre-submit pass recorded. Run 'git-workflow.sh push' first (it runs pre-submit automatically)."
    fi

    # Auto-generate title from branch if not provided
    if [ -z "$TITLE" ]; then
      # Extract slug from branch name, convert to title
      TITLE=$(echo "$BRANCH" | sed 's|agent/[0-9]*-||' | tr '-' ' ')
    fi

    # Gather context for PR body
    COMMITS=$(git log --oneline main..HEAD 2>/dev/null || git log --oneline master..HEAD)
    DIFF_STAT=$(git diff --stat main..HEAD 2>/dev/null || git diff --stat master..HEAD)

    # Determine PR type from first commit
    PR_TYPE="Bug fix"
    if echo "$COMMITS" | head -1 | grep -q "^.*feat:"; then PR_TYPE="Feature"; fi
    if echo "$COMMITS" | head -1 | grep -q "^.*refactor:"; then PR_TYPE="Refactor"; fi
    if echo "$COMMITS" | head -1 | grep -q "^.*docs:"; then PR_TYPE="Docs"; fi
    if echo "$COMMITS" | head -1 | grep -q "^.*test:"; then PR_TYPE="Test"; fi

    gh pr create --title "$TITLE" --body "$(cat <<PREOF
## Description

Fixes #${ISSUE}

## Type

- [$([ "$PR_TYPE" = "Bug fix" ] && echo 'x' || echo ' ')] Bug fix
- [$([ "$PR_TYPE" = "Feature" ] && echo 'x' || echo ' ')] Feature
- [$([ "$PR_TYPE" = "Refactor" ] && echo 'x' || echo ' ')] Refactor
- [$([ "$PR_TYPE" = "Docs" ] && echo 'x' || echo ' ')] Docs
- [$([ "$PR_TYPE" = "Test" ] && echo 'x' || echo ' ')] Test

## Changes

${DIFF_STAT}

## Commits

${COMMITS}

## Agent Metadata

- Agent: $(git config user.name)
- Issue: #${ISSUE}

## Checklist

- [x] Tests pass locally
- [x] Lint clean
- [ ] CodeRabbit feedback addressed
- [x] Self-review done
- [x] No secrets committed
- [x] Conventional commit messages used
PREOF
)"
    ok "PR created for issue #${ISSUE}"
    ;;

  *)
    echo "Usage: git-workflow.sh <command>"
    echo ""
    echo "Commands:"
    echo "  branch <issue-number> <slug>   Create branch from latest main"
    echo "  commit \"<message>\"             Commit with validation"
    echo "  push                           Push current branch"
    echo "  pr <issue-number> [title]      Create PR linking issue"
    exit 1
    ;;
esac
