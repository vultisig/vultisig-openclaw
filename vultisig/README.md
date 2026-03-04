# Vultisig Dev Agent (OpenClaw Fork)

Plug-and-play AI coding agent for Vultisig developers. Picks up GitHub issues,
implements solutions, raises PRs, iterates on CodeRabbit review.

Built as a fork of [OpenClaw](https://github.com/openclaw/openclaw) with
Vultisig-specific workspace, scripts, and coding brain baked in.

## Prerequisites

- A VPS or always-on machine (recommended: 2GB RAM, 1 vCPU)
  - Agents run 24/7 to poll and work on issues
  - A local dev machine works but the agent stops when the machine sleeps
- Node.js 22+
- GitHub CLI (`gh`) authenticated as the bot account
- A separate GitHub bot account (see below)
- API key (Anthropic direct or OpenRouter)

## API Key Setup

```bash
# Anthropic direct
export ANTHROPIC_API_KEY=sk-ant-...

# OR OpenRouter (update model strings in config.yml accordingly)
export OPENROUTER_API_KEY=sk-or-...
```

## Create Your Bot Account

Each developer creates their own bot account for clean audit trails:

1. **Create a new GitHub account** (e.g., `alice-vultisig-bot`)
   - Use a separate email (e.g., `alice+vultisig-bot@gmail.com`)
   - This is a regular GitHub account — no special setup needed

2. **Generate a Personal Access Token (PAT):**
   - Go to Settings → Developer Settings → Personal Access Tokens → Fine-grained
   - Scope: `repo` (full control of private repositories)
   - Save the token — you'll need it during setup

3. **Ask an org admin to add the bot as collaborator:**
   - Bot needs **write** access (not admin) to each active repo
   - This lets the bot push branches and open PRs
   - Branch protection on `main` prevents direct pushes

4. **Authenticate `gh` CLI on the VPS as the bot:**
   ```bash
   # If running on VPS (dedicated to the bot)
   gh auth login
   # Select: GitHub.com → HTTPS → Paste token

   # Configure git to use gh for authentication (enables git push)
   gh auth setup-git

   # If running on your dev machine alongside your personal account
   # Option A: Use GH_TOKEN env var for bot operations
   export GH_TOKEN=ghp_your_bot_token_here

   # Option B: Use gh auth switch (if both accounts are logged in)
   gh auth login --with-token <<< "ghp_your_bot_token_here"
   gh auth switch --user alice-vultisig-bot
   gh auth setup-git
   ```

## Two Ways to Set Up

Choose based on your situation:

| Path | For | Time |
|------|-----|------|
| **Fresh Install** (`setup.sh`) | New to OpenClaw, or want a dedicated VPS agent | ~10 min |
| **Hire** (`hire.sh`) | Already have OpenClaw running, want to add Vultisig | ~5 min |

Both paths make the agent **Vultisig-aware immediately** — it knows the product,
the repos, the security rules, the coding standards, and the task workflow. All
of that is baked into the workspace files that get loaded as system prompt context.

---

### Path A: Fresh Install

For developers setting up a dedicated Vultisig agent (recommended for VPS).

```
You ──→ clone fork ──→ fill config.yml ──→ run setup.sh ──→ openclaw start
```

**What `setup.sh` does:**
1. Validates prerequisites (node 22+, gh, openclaw, git)
2. Reads your `config.yml` (name, bot account, repos, model, cron mode)
3. Checks API key + git auth
4. Clones repos + configures git identity for bot
5. Creates agent labels on repos (`agent:assigned`, `agent:in-progress`, etc.)
6. Generates or **merges** OpenClaw config at `~/.openclaw/openclaw.json`
   - If no existing config → creates fresh
   - If existing config found → **merges** Vultisig agent in (preserves your setup)
7. Templates workspace identity files
8. Initializes brain submodule (optional — skips gracefully if repo not yet available)
9. **Merges** 4 cron jobs into `~/.openclaw/cron/jobs.json` (preserves existing jobs)
10. Generates systemd service file

**Steps:**

1. **Clone the fork:**
   ```bash
   git clone https://github.com/vultisig/vultisig-openclaw.git
   cd vultisig-openclaw
   ```

2. **Install OpenClaw:**
   ```bash
   pnpm install && pnpm build
   # Or: npm install -g openclaw@latest (if using upstream release)
   ```

3. **Copy and fill config:**
   ```bash
   cp vultisig/config.example.yml vultisig/config.yml
   # Edit vultisig/config.yml with your details
   ```

4. **Run setup:**
   ```bash
   ./vultisig/setup.sh
   ```

5. **Start the agent:**
   ```bash
   openclaw start
   ```

6. **Test it:**
   - Create an issue on one of your active repos
   - Add label `agent:assigned` and assign your bot account
   - Wait 15 min (nightshift) or 5 min (active)
   - Agent picks it up, creates branch, implements, opens PR

---

### Path B: Hire an Agent

For developers who already have OpenClaw running. One interactive script that
injects the Vultisig agent into your existing setup — no fork needed, nothing
gets overwritten.

```
You ──→ run hire.sh ──→ answer prompts ──→ openclaw restart
```

**What `hire.sh` does:**
1. Checks prerequisites (existing OpenClaw, gh, git, node)
2. Prompts you interactively (name, bot account, repos, model, cron mode, telegram)
3. Downloads workspace files + brain to `~/.openclaw/vultisig/`
4. Templates identity files from your answers
5. **Merges** a `vultisig` agent into your existing `openclaw.json` (non-destructive)
6. **Merges** 4 `vultisig-*` cron jobs into your existing `jobs.json` (non-destructive)
7. Clones repos + configures git identity
8. Creates agent labels on repos
9. Verifies bot access

**Steps:**

```bash
# Option 1: One-liner
curl -fsSL https://raw.githubusercontent.com/vultisig/vultisig-openclaw/main/vultisig/hire.sh | bash

# Option 2: Clone and run
git clone https://github.com/vultisig/vultisig-openclaw.git /tmp/vultisig-openclaw
/tmp/vultisig-openclaw/vultisig/hire.sh
```

Then restart OpenClaw:
```bash
openclaw restart
# or: sudo systemctl restart openclaw
```

**To remove later:**
```bash
~/.openclaw/vultisig/fire.sh
openclaw restart
```
`fire.sh` removes the agent + cron jobs from your config. Leaves workspace
files and cloned repos for manual cleanup.

---

### What Gets Preserved (Both Paths)

Both `setup.sh` and `hire.sh` use **non-destructive merges**:

| Config | Behavior |
|--------|----------|
| `openclaw.json` | Existing agents, env vars, settings preserved. Vultisig agent added/updated. |
| `jobs.json` | Existing cron jobs preserved. 4 `vultisig-*` jobs added/replaced. |
| Cloned repos | Skipped if already cloned. Git identity configured. |
| Labels | Created if missing, skipped if they already exist. |

Safe to re-run either script — both are idempotent.

## How It Works

### Issue Workflow
1. Create issue on `vultisig/{repo}` (use the issue template)
2. Add label `agent:assigned` + assign your bot account
3. Agent picks it up (within 15 min nightshift / 5 min active)
4. Agent reads the issue, repo CLAUDE.md, and relevant brain docs
5. Agent creates branch `agent/{issue-number}-{slug}`, implements, tests
6. Agent opens PR — notifies you via Telegram
7. CodeRabbit reviews → agent addresses feedback (up to 3 rounds)
8. CI passes → agent marks PR ready for review, notifies you
9. You review and merge (agent never merges)

### Architecture

**One agent.** Simple. The agent picks up issues, codes, tests, commits,
raises PRs, and iterates on feedback. No subagents, no orchestration layer.

| Agent | Model | Role |
|-------|-------|------|
| **main** | Your choice (Sonnet/Opus) | Code, test, PR, iterate |

Cron lookups use Haiku for cheap status checks. Real work uses your primary model.

For complex multi-step features that need structured workflows, Antfarm
can be added later (Phase 3) without changing the base setup.

### Safety

Safety is enforced at two levels:

1. **Repo-level hooks** (`.claude/settings.json` in every repo via repo-standards):
   - Blocks mainnet RPC interactions
   - Blocks edits to secret/credential files
   - Blocks force push and `--no-verify`
   - Blocks destructive git operations

2. **Agent-level tool restrictions** (OpenClaw tool profile):
   - Coding tools only (read, write, edit, bash, glob, grep)
   - No UI, image, TTS, or canvas tools

Branch protection on `main` prevents direct pushes. Agent never merges PRs.

### Cron Modes

Two modes, set via `cron_mode` in config.yml:

| Mode | Lookups (haiku) | Work Queue (your model) | Polling Cost/day | + Work |
|------|----------------|------------------------|-----------------|--------|
| **nightshift** (default) | every 15 min | every 20 min | ~$1-2 | +$3 |
| **active** | every 5 min | every 7 min | ~$3-5 | +$3 |

Lookups (haiku) just check for new issues/CI/feedback — cheap (~$0.01/poll).
Work queue (your primary model) does the actual coding, only when there's work.

**Nightshift** is recommended: assign issues at end of day, PRs ready in the morning.
**Active** for when you want faster turnaround during work hours.

### Cost

Lookups use Haiku (~$0.01/poll) — just checking for new issues, CI status, comments.
Real work uses your primary model (Sonnet ~$0.50-2.00/task, Opus ~$1-4/task).

Manage spend via your API provider's dashboard.

### Notifications

Agent sends Telegram notifications for key events:
- PR created
- PR ready for review
- Agent blocked (needs human help)

A separate team bot handles broader PR watching and team pings.

## Updating

Pull latest Brain + workspace files without overwriting your config:
```bash
./update.sh
```

## Structure

| Directory | Purpose |
|-----------|---------|
| `vultisig/workspace/` | Agent personality, security rules, tool config |
| `vultisig/brain/` | Shared knowledge base (git submodule) — reference docs |

## VPS Setup (Recommended)

A small VPS keeps the agent running 24/7 with automatic restarts:

1. **Provision** a VPS (any provider: DigitalOcean, Hetzner, etc.)
   - Minimum: 2GB RAM, 1 vCPU, 20GB disk
   - Ubuntu 22.04+ recommended

2. **Install dependencies:**
   ```bash
   # Node.js 22+
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
   sudo apt install -y nodejs

   # GitHub CLI
   curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
   sudo apt update && sudo apt install gh

   # Clone the Vultisig OpenClaw fork
   git clone https://github.com/vultisig/vultisig-openclaw.git
   cd vultisig-openclaw && pnpm install && pnpm build

   # Git
   sudo apt install -y git
   ```

3. **Authenticate `gh` as bot account:**
   ```bash
   gh auth login
   gh auth setup-git   # enables git push via gh credentials
   ```

4. **Follow Quick Start** (config, setup, start)

5. **Install as systemd service** (auto-start + auto-restart):
   ```bash
   # setup.sh generates this for you, but you can also do it manually:
   sudo cp vultisig/vultisig-agent.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable vultisig-agent
   sudo systemctl start vultisig-agent
   ```

   **Why systemd?** Without it, if the VPS reboots (kernel updates, provider
   maintenance) or the process crashes (OOM, unexpected error), the agent
   dies silently. No issues get picked up until someone manually SSHs in and
   restarts. Systemd auto-starts on boot, auto-restarts on crash, and
   collects logs via `journalctl -u vultisig-agent`.

## Monitoring

Check agent status:
```bash
./status.sh                           # Quick: running? auth? cron? open PRs?
sudo journalctl -u vultisig-agent -f  # Live logs (if using systemd)
```

## Troubleshooting

**Agent not picking up issues:**
- Check agent labels exist on the repo (`agent:assigned`, `agent:in-progress`,
  `agent:review`, `agent:blocked`). Create them manually or via repo-standards PRs (Pillar 2).
- Check label is exactly `agent:assigned`
- Check bot account is assigned to the issue
- Check `config.yml` lists the repo in `repos.active`
- Check cron is running: `openclaw cron list`

**PR not created:**
- Check bot account has write access to the repo
- Check `gh auth status` for bot account
- Check `gh auth setup-git` was run (needed for git push)

**CI not triggering on agent PRs:**
- Ensure CI workflows trigger on branches matching `agent/*`
- Check `.github/workflows/*.yml` for branch filters

**Agent stopped / not running:**
- Check systemd: `sudo systemctl status vultisig-agent`
- Restart: `sudo systemctl restart vultisig-agent`
- If not using systemd: `cd /path/to/vultisig-openclaw && openclaw start`
