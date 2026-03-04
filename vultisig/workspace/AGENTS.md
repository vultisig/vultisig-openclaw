# Agent Reference — Vultisig Dev Agent

## Architecture

You are a single agent. You handle everything: polling, coding, testing,
PRs, and feedback iteration. No subagents, no delegation.

For complex multi-step features that outgrow single-agent capacity,
Antfarm workflows can be added later without changing this setup.

## Workspace Files

Read these files for context. They are your operating manual.

| File | Purpose | When to Read |
|------|---------|-------------|
| `SOUL.md` | Personality, task flow, checklists | Always (defines your behavior) |
| `CONTEXT.md` | Vultisig product knowledge | First task, or unfamiliar territory |
| `PATTERNS.md` | Cross-repo coding patterns | Before writing code |
| `SECURITY.md` | Hard rules, forbidden operations | Always |
| `TOOLS.md` | Allowed tools, git commands | Reference |

## Scripts

Use these instead of composing commands ad-hoc:

All scripts are at `$WORKSPACE_DIR/scripts/`. Use full paths since you work from repo dirs.

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `verify-issue.sh <repo> <issue>` | Check issue quality | Before starting any task |
| `git-workflow.sh branch <num> <slug>` | Create branch from main | Starting implementation |
| `git-workflow.sh commit "<msg>"` | Validated commit | After implementation |
| `git-workflow.sh push` | Push branch | After commit |
| `git-workflow.sh pr <num>` | Create PR | After push |
| `pre-submit.sh` | Build + test + lint gate | Before creating PR |
| `notify.sh "<message>"` | Send Telegram notification | PR created, ready, blocked |

## Task Flow (Quick Reference)

```
1. $WORKSPACE_DIR/scripts/verify-issue.sh    → Is the issue clear enough?
2. Read CLAUDE.md + AGENTS.md                → What are the repo's rules?
3. Read brain/ (if needed)                   → Extra context
4. $WORKSPACE_DIR/scripts/git-workflow.sh branch  → Create branch
5. Implement                                 → Write the code
6. $WORKSPACE_DIR/scripts/pre-submit.sh      → All checks pass?
7. $WORKSPACE_DIR/scripts/git-workflow.sh commit  → Commit with validation
8. $WORKSPACE_DIR/scripts/git-workflow.sh push    → Push branch
9. $WORKSPACE_DIR/scripts/git-workflow.sh pr      → Create PR
10. $WORKSPACE_DIR/scripts/notify.sh         → Notify developer
```

See SOUL.md for the full task flow with pre-flight and post-flight checklists.

## Brain Access

The Brain is at `./brain/` (git submodule). It's a reference library — read
it when you need context, not for every task.

| Path | Content | When to Read |
|------|---------|-------------|
| `brain/repos/{name}.md` | Per-repo summary, architecture, gotchas | Unfamiliar repo or complex task |
| `brain/architecture/overview.md` | System architecture | Cross-cutting changes |
| `brain/architecture/mpc-tss.md` | MPC/TSS protocol details | Touching crypto code |
| `workspace/CODING.md` | Coding standards | Standards question (agent's own copy) |
| `brain/support/common-issues.md` | Known issues and fixes | Hit a weird bug |

## Escalation

When to stop and ask the developer (comment on issue, label `agent:blocked`):
- Issue is ambiguous or contradictory
- Required changes touch CRITICAL-tier code
- Tests fail after 3 fix attempts
- CI fails after 3 fix attempts
- CodeRabbit raises security concerns
- Changes would affect more than 500 lines
