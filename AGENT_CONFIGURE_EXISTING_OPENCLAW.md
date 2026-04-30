# Agent Runbook: Configure Existing OpenClaw Railway Service

## Purpose

Use this runbook when a local agent works in a local clone of this repository and needs to configure an already existing Railway OpenClaw service.

The agent must not edit Docker/runtime infrastructure in this flow. The local script only:

```text
loads local .agent.env
checks repository consistency
sets Railway variables
runs railway up or railway redeploy
collects deployment logs
writes a local report
```

## Files

Public files in Git:

```text
installer.manifest.json
.agent.env.example
tools/configure-existing-openclaw-railway.sh
AGENT_CONFIGURE_EXISTING_OPENCLAW.md
```

Private local files, never commit:

```text
.agent.env
.agent-reports/
```

## First setup

From repository root:

```bash
cp .agent.env.example .agent.env
```

Fill `.agent.env` locally:

```env
RAILWAY_SERVICE=OpenClaw
RAILWAY_ENVIRONMENT=production

OPENCLAW_VERSION=2026.4.23
NODE_ENV=production

OPENCLAW_LLM_KEY=REPLACE_ME
OPENCLAW_LLM_MODEL=deepseek/deepseek-chat
OPENCLAW_LLM_BASE_URL=https://api.deepseek.com

OPENCLAW_ENABLE_VK=true
VK_COMMUNITY_TOKEN=REPLACE_ME
VK_GROUP_ID=REPLACE_ME

OPENCLAW_VERIFY_LIVE_MODEL=false
OPENCLAW_RUN_DOCTOR=true
OPENCLAW_SYNC_CONFIG_FROM_ENV=true
RAILWAY_HEALTHCHECK_TIMEOUT_SEC=600
```

Do not commit `.agent.env`.

## Commands

### Local consistency check only

```bash
bash tools/configure-existing-openclaw-railway.sh --check --no-railway
```

### Check Railway link and local repo

```bash
bash tools/configure-existing-openclaw-railway.sh --check
```

### Set Railway variables only

```bash
bash tools/configure-existing-openclaw-railway.sh --vars
```

### Set variables and deploy current local repo

Use when files changed locally and must be uploaded to Railway:

```bash
bash tools/configure-existing-openclaw-railway.sh --deploy
```

### Set variables and redeploy latest Railway deployment

Use when only variables changed and code did not change:

```bash
bash tools/configure-existing-openclaw-railway.sh --redeploy
```

### Collect logs only

```bash
bash tools/configure-existing-openclaw-railway.sh --logs
```

## Rules for the agent

1. Work from the repository root.
2. Do not commit `.agent.env`.
3. Do not paste secrets into chat.
4. Do not run `railway redeploy` after changing files. Use `railway up` through `--deploy`.
5. If `--check` fails, stop and return the report.
6. Return the latest report path and the important PASS/FAIL lines.

## Report

The script writes reports to:

```text
.agent-reports/YYYYMMDD-HHMMSS-configure-existing-openclaw-railway.log
```

Return this summary:

```text
RAILWAY CONFIGURE REPORT

Repo:
- branch:
- commit:
- dirty files:

Checks:
- required files:
- shell syntax:
- node syntax:
- toml parse:
- forbidden patterns:
- invariants:
- local env:
- Railway CLI:

Action:
- mode:
- service:
- environment:
- command:

Logs:
- [clawdbot-entrypoint]: found/not found
- generated/loaded OPENCLAW_GATEWAY_TOKEN: found/not found
- generated/loaded SETUP_PASSWORD: found/not found
- run OpenClaw doctor: found/not found
- [verify-runtime]: found/not found
- [verify-config]: found/not found
- ERROR lines:

Report file:
- .agent-reports/...
```

## Scope limits

This runbook does not change:

```text
Dockerfile
entrypoint.sh
src/*
client-pack runtime logic
Railway Template Composer metadata
```

Those are separate tasks.
