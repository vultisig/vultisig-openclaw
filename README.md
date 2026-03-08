# Vultisig Dev Agent

AI coding agent for Vultisig developers. Picks up GitHub issues, implements
solutions, raises PRs, iterates on review feedback.

Built on [OpenClaw](https://github.com/openclaw/openclaw) — a self-hosted AI
coding agent platform. **New to OpenClaw?** Read the
[OpenClaw README](https://github.com/openclaw/openclaw#readme) first for
installation basics, CLI usage, and how agents work. This repo adds the
Vultisig-specific layer on top.

---

## How It Works

1. Create an issue on `vultisig/{repo}`
2. Add label `agent:assigned` + assign your bot account
3. Agent picks it up (15 min nightshift / 5 min active)
4. Agent creates branch, implements, tests, opens PR
5. CodeRabbit reviews → agent addresses feedback (up to 3 rounds)
6. CI passes → agent marks PR ready, notifies you
7. You review and merge (agent never merges)

```
 You                          GitHub                        Agent (VPS)
  │                             │                              │
  ├─ Create issue ─────────────►│                              │
  ├─ Add label: agent:assigned ►│                              │
  ├─ Assign: your-bot ─────────►│                              │
  │                             │                              │
  │                             │◄──── polls every 15 min ─────┤
  │                             │─── new issue found! ────────►│
  │                             │                              │
  │                             │         ┌────────────────────┤
  │                             │         │ 1. Read issue      │
  │                             │         │ 2. Load brain docs │
  │                             │         │ 3. Create branch   │
  │                             │         │ 4. Code + test     │
  │                             │         │ 5. Open PR         │
  │                             │         └────────────────────┤
  │                             │                              │
  │  ◄── Telegram: "PR ready" ──┼──────────────────────────────┤
  │                             │                              │
  │                             │◄── CodeRabbit reviews ───────│
  │                             │─── feedback ────────────────►│
  │                             │◄── agent pushes fixes ───────┤
  │                             │         (up to 3 rounds)     │
  │                             │                              │
  │  ◄── Telegram: "Ready for ──┼──────────────────────────────┤
  │      your review"           │                              │
  │                             │                              │
  ├─ Review + Merge ───────────►│                              │
  │                             │                  agent never merges
```

---

## Setup

### Prerequisites

- Node.js 22+
- GitHub CLI (`gh`) — [install](https://cli.github.com)
- API key: `export ANTHROPIC_API_KEY=sk-ant-...` (or `OPENROUTER_API_KEY`)
- A bot GitHub account (see [Bot Account](#bot-account) below)

### Fresh Install (recommended)

```bash
# 1. Install OpenClaw (the runtime)
npm i -g openclaw@latest
openclaw onboard

# 2. Clone this repo
git clone https://github.com/vultisig/vultisig-openclaw.git
cd vultisig-openclaw

# 3. Configure
cp config.example.yml config.yml
# Edit config.yml — set your name, bot account, repos, model

# 4. Run setup
./setup.sh

# 5. Start
openclaw start
```

`setup.sh` handles everything: clones repos, creates labels, generates config,
sets up cron jobs. If you already have an OpenClaw config, it merges
non-destructively (your existing setup is preserved).

### Hire (existing OpenClaw users)

Already running OpenClaw? One interactive script adds the Vultisig agent:

```bash
git clone https://github.com/vultisig/vultisig-openclaw.git /tmp/vultisig-openclaw
/tmp/vultisig-openclaw/hire.sh
# Answer the prompts, then:
openclaw restart
```

To remove later: `~/.openclaw/vultisig/fire.sh && openclaw restart`

Both paths are **idempotent** — safe to re-run. Both **merge non-destructively**
into existing OpenClaw configs.

---

## Bot Account

Each developer creates their own bot account for clean audit trails:

1. **Create a GitHub account** (e.g., `alice-vultisig-bot`)
2. **Generate a Fine-grained PAT** with `repo` scope
3. **Ask org admin** to add bot as collaborator (write access, not admin)
4. **Auth on your machine:**
   ```bash
   # Dedicated VPS:
   gh auth login          # paste bot token
   gh auth setup-git

   # Dev machine (alongside personal account):
   export GH_TOKEN=ghp_your_bot_token
   ```

---

## Config

Edit `config.yml` (copied from `config.example.yml`):

```yaml
developer:
  name: "Alice"
  github_username: "alice-dev"
  github_bot_account: "alice-vultisig-bot"
  timezone: "Europe/Berlin"

notifications:
  telegram_bot_token: ""    # optional — via @BotFather
  telegram_chat_id: ""

repos:
  active:
    - vultisig-sdk
    - vultisig-windows
    - docs
  base_dir: "~/vultisig-repos"

agent:
  model_primary: "anthropic/claude-sonnet-4-6"
  model_polling: "anthropic/claude-haiku-4-5"

cron_mode: "nightshift"     # or "active"
```

---

## Cron Modes

| Mode | Polling | Work Queue | Cost/day |
|------|---------|-----------|----------|
| **nightshift** (default) | every 15 min | every 20 min | ~$4-10 |
| **active** | every 5 min | every 7 min | ~$6-13 |

Polling uses Haiku (~$0.01/check). Work uses your primary model.

**Nightshift:** assign issues end of day, PRs ready in the morning.
**Active:** faster turnaround during work hours.

---

## VPS Setup

For 24/7 operation (recommended):

```bash
# 1. Provision VPS (2GB RAM, 1 vCPU, Ubuntu 22.04+)

# 2. Install deps
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs git
# Install gh: https://cli.github.com

# 3. Auth as bot
gh auth login && gh auth setup-git

# 4. Clone + setup (see Fresh Install above)

# 5. Install as systemd service (auto-start + restart)
sudo cp vultisig-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vultisig-agent
```

---

## Safety

- Agent **never merges PRs** — humans review and merge
- Agent **never pushes to main** — branch protection enforced
- Agent **never touches secrets** — checked at commit time
- Workspace scripts validate every commit, push, and PR
- See `workspace/SECURITY.md` for full rules

---

## Scripts

| Script | Purpose |
|--------|---------|
| `setup.sh` | Full setup from config.yml |
| `hire.sh` | Interactive setup for existing OpenClaw |
| `fire.sh` | Remove Vultisig agent cleanly |
| `update.sh` | Pull latest workspace + brain |
| `status.sh` | Check agent health, open PRs |

---

## Monitoring

```bash
./status.sh                                 # quick health check
sudo journalctl -u vultisig-agent -f        # live logs (systemd)
```

## Troubleshooting

**Agent not picking up issues:**
- Label must be exactly `agent:assigned`
- Bot account must be assigned to the issue
- Repo must be in `config.yml` → `repos.active`

**PR not created:**
- Check bot has write access: `gh api repos/vultisig/{repo}/collaborators/{bot} --jq .permissions`
- Check auth: `gh auth status`

**Agent stopped:**
- `sudo systemctl status vultisig-agent`
- `sudo systemctl restart vultisig-agent`

---

## Structure

```
vultisig-openclaw/
├── README.md                      → this file
├── LICENSE
├── setup.sh, hire.sh, fire.sh     → onboarding / removal
├── update.sh, status.sh           → maintenance
├── config.example.yml             → template config
├── vultisig-agent.service.tmpl    → systemd template
└── workspace/                     → agent's brain
    ├── SOUL.md                    → personality + task flow
    ├── CODING.md                  → coding standards
    ├── SECURITY.md                → hard safety rules
    ├── CONTEXT.md                 → Vultisig product knowledge
    ├── PATTERNS.md                → cross-repo conventions
    ├── AGENTS.md, TOOLS.md        → reference docs
    ├── IDENTITY.md.tmpl           → generated per-bot
    ├── USER.md.tmpl               → generated per-dev
    └── scripts/
        ├── git-workflow.sh        → branch, commit, push, PR
        ├── pre-submit.sh         → build + test + lint gate
        ├── verify-issue.sh        → issue quality check
        └── notify.sh              → Telegram notifications
```

This repo contains **only** the Vultisig agent config and workspace — no OpenClaw
source code. OpenClaw is a runtime dependency installed separately via npm.
