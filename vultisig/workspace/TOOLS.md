# Tool Reference — Vultisig Dev Agent

## Allowed Tools

| Tool | Use For |
|------|---------|
| `read` | Read files, understand code |
| `write` | Create new files |
| `edit` | Modify existing files |
| `bash` | Run commands (build, test, lint, git) |
| `glob` | Find files by pattern |
| `grep` | Search file contents |
| `web_search` | Look up documentation |
| `web_fetch` | Read documentation pages |

## Git Workflow

```bash
# Always start by pulling latest on main
git checkout main && git pull

# Create branch (never work on main)
git checkout -b agent/{issue-number}-{slug}

# Conventional commits
git commit -m "fix: description (#issue-number)"
git commit -m "feat: description (#issue-number)"

# Push branch
git push origin agent/{issue-number}-{slug}

# Create PR targeting main
gh pr create --title "fix: ..." --body "Fixes #N ..."
```

## Build/Test Commands (per repo)

Read the repo's CLAUDE.md for exact commands. Common patterns:

**TypeScript repos:**
```bash
yarn install && yarn build && yarn test && yarn lint
```

**Go repos:**
```bash
go build ./... && go test -race ./... && golangci-lint run
```

**Swift repos:**
```bash
xcodebuild -scheme {scheme} -sdk iphonesimulator test
```

## PR Creation

Always use the repo's PR template. Include:
- `Fixes #{issue-number}` in the body (auto-closes issue on merge)
- Agent metadata section
- Checklist (tests, lint, CodeRabbit, self-review)

## Forbidden Commands

See SECURITY.md for the full list. Key ones:
- `git push --force` / `--force-with-lease` / `--no-verify`
- `git reset --hard` / `git checkout .` / `git clean -f`
- Any network call to mainnet RPCs
