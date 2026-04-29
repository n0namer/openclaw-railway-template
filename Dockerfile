FROM node:24-bookworm

ARG OPENCLAW_VERSION=2026.4.26

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 \
    build-essential \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@${OPENCLAW_VERSION} clawhub@latest

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src

RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app \
  && mkdir -p /data && chown openclaw:openclaw /data \
  && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

RUN mkdir -p \
    /opt/clawdbot/seed/skills/bmad \
    /opt/clawdbot/seed/skills/client-intake \
    /opt/clawdbot/seed/skills/sales-qualification \
    /opt/clawdbot/seed/skills/objection-handling \
    /opt/clawdbot/seed/skills/lead-summary \
    /opt/clawdbot/seed/skills/handoff-human \
    /opt/clawdbot/seed/agents/life-router \
    /opt/clawdbot/seed/agents/sales-agent \
    /opt/clawdbot/seed/agents/support-agent \
    /opt/clawdbot/seed/agents/memory-agent \
    /opt/clawdbot/seed/agents/critic-agent \
    /opt/clawdbot/seed/agents/golden-tester

RUN printf '%s\n' \
  '# BMAD Skill' \
  '' \
  'Use for structured product/engineering work: brief, architecture, decision log, backlog, acceptance criteria, and 48-72 hour execution plan.' \
  > /opt/clawdbot/seed/skills/bmad/README.md
RUN printf '%s\n' \
  '# Client Intake Skill' \
  '' \
  'Use when a new business connects a channel. Collect business niche, offer, target audience, tone, forbidden topics, escalation rules, and success metric.' \
  > /opt/clawdbot/seed/skills/client-intake/README.md
RUN printf '%s\n' \
  '# Sales Qualification Skill' \
  '' \
  'Use when an incoming lead asks about price, terms, availability, service fit, consultation, booking, or purchase intent.' \
  > /opt/clawdbot/seed/skills/sales-qualification/README.md
RUN printf '%s\n' \
  '# Objection Handling Skill' \
  '' \
  'Use when a lead resists price, timing, trust, relevance, quality, or asks for proof before taking the next step.' \
  > /opt/clawdbot/seed/skills/objection-handling/README.md
RUN printf '%s\n' \
  '# Lead Summary Skill' \
  '' \
  'Use after meaningful dialogue. Summarize need, budget, urgency, objections, promised follow-up, and next action.' \
  > /opt/clawdbot/seed/skills/lead-summary/README.md
RUN printf '%s\n' \
  '# Handoff Human Skill' \
  '' \
  'Use when confidence is low, payment/legal/medical risk appears, client asks for human, or conversation becomes angry.' \
  > /opt/clawdbot/seed/skills/handoff-human/README.md
RUN printf '%s\n' \
  '# life-router' \
  '' \
  'Default channel router. Decide whether the request is sales, support, memory, criticism/quality, or human handoff. Keep the answer short and action-oriented.' \
  > /opt/clawdbot/seed/agents/life-router/README.md
RUN printf '%s\n' \
  '# sales-agent' \
  '' \
  'Qualify leads, answer basic commercial questions, move to application/booking/payment, and summarize the lead.' \
  > /opt/clawdbot/seed/agents/sales-agent/README.md
RUN printf '%s\n' \
  '# support-agent' \
  '' \
  'Handle FAQs, status questions, simple troubleshooting, and escalation to human when needed.' \
  > /opt/clawdbot/seed/agents/support-agent/README.md
RUN printf '%s\n' \
  '# memory-agent' \
  '' \
  'Maintain client context, facts, preferences, and reusable summaries in the workspace.' \
  > /opt/clawdbot/seed/agents/memory-agent/README.md
RUN printf '%s\n' \
  '# critic-agent' \
  '' \
  'Check quality, safety, tone, missing next actions, and whether the answer moves the client forward.' \
  > /opt/clawdbot/seed/agents/critic-agent/README.md
RUN printf '%s\n' \
  '# golden-tester' \
  '' \
  'Run smoke checks for version, health, plugins, skills, routing, and redeploy persistence.' \
  > /opt/clawdbot/seed/agents/golden-tester/README.md

RUN cat > /app/docker-entrypoint.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[clawdbot-entrypoint] %s\n' "$*"
}

export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
export OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-${OPENCLAW_STATE_DIR}/skills}"
export OPENCLAW_PLUGINS_DIR="${OPENCLAW_PLUGINS_DIR:-/data/openclaw-plugins}"
export CLAWDBOT_STATE_DIR="${CLAWDBOT_STATE_DIR:-/data/.clawdbot}"
export CLAWDBOT_WORKSPACE_DIR="${CLAWDBOT_WORKSPACE_DIR:-${OPENCLAW_WORKSPACE_DIR}}"
export CLAWDBOT_SKILLS_DIR="${CLAWDBOT_SKILLS_DIR:-${CLAWDBOT_STATE_DIR}/skills}"
export CLAWDBOT_PLUGINS_DIR="${CLAWDBOT_PLUGINS_DIR:-/data/clawdbot-plugins}"
export CLAWDBOT_BACKUP_DIR="${CLAWDBOT_BACKUP_DIR:-/data/backups}"
export OPENCLAW_VK_PLUGIN_DIR="${OPENCLAW_VK_PLUGIN_DIR:-${OPENCLAW_PLUGINS_DIR}/openclaw-vk}"
export CLAWDBOT_VK_PLUGIN_REPO="${CLAWDBOT_VK_PLUGIN_REPO:-https://github.com/fibbersha-hub/openclaw-vk-plugin.git}"
export CLAWDBOT_INSTALL_VK_PLUGIN="${CLAWDBOT_INSTALL_VK_PLUGIN:-true}"
export CLAWDBOT_AUTO_CONFIG="${CLAWDBOT_AUTO_CONFIG:-auto}"
export INTERNAL_GATEWAY_BIND="${INTERNAL_GATEWAY_BIND:-lan}"
export INTERNAL_GATEWAY_PORT="${INTERNAL_GATEWAY_PORT:-18789}"
export SELF_HEAL_MAX_ATTEMPTS="${SELF_HEAL_MAX_ATTEMPTS:-3}"

mkdir -p \
  "$OPENCLAW_STATE_DIR" \
  "$OPENCLAW_WORKSPACE_DIR" \
  "$OPENCLAW_SKILLS_DIR" \
  "$OPENCLAW_PLUGINS_DIR" \
  "$CLAWDBOT_STATE_DIR" \
  "$CLAWDBOT_SKILLS_DIR" \
  "$CLAWDBOT_PLUGINS_DIR" \
  "$CLAWDBOT_BACKUP_DIR" \
  "$OPENCLAW_WORKSPACE_DIR/skills" \
  "$OPENCLAW_WORKSPACE_DIR/plugins" \
  "$OPENCLAW_WORKSPACE_DIR/agents" \
  "$OPENCLAW_STATE_DIR/agents" \
  "$OPENCLAW_STATE_DIR/logs"

seed_dir_if_empty() {
  local src="$1"
  local dst="$2"
  if [ ! -d "$src" ]; then
    log "seed source missing: $src"
    return 0
  fi
  mkdir -p "$dst"
  if [ -z "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
    log "seed $dst from $src"
    cp -a "$src"/. "$dst"/
  else
    log "preserve existing volume data: $dst"
  fi
}

seed_dir_if_empty /opt/clawdbot/seed/skills "$OPENCLAW_WORKSPACE_DIR/skills"
seed_dir_if_empty /opt/clawdbot/seed/agents "$OPENCLAW_WORKSPACE_DIR/agents"

if [ "$CLAWDBOT_INSTALL_VK_PLUGIN" = "true" ] && [ ! -d "$OPENCLAW_VK_PLUGIN_DIR" ]; then
  log "install VK plugin on persistent volume: $OPENCLAW_VK_PLUGIN_DIR"
  git clone --depth 1 "$CLAWDBOT_VK_PLUGIN_REPO" "$OPENCLAW_VK_PLUGIN_DIR" || log "warning: VK plugin clone failed"
fi

if [ -d "$OPENCLAW_VK_PLUGIN_DIR" ] && [ -f "$OPENCLAW_VK_PLUGIN_DIR/package.json" ]; then
  log "prepare VK plugin dependencies on volume"
  (
    cd "$OPENCLAW_VK_PLUGIN_DIR"
    if command -v pnpm >/dev/null 2>&1; then
      pnpm install --prod --frozen-lockfile=false || pnpm install --prod || true
    elif command -v npm >/dev/null 2>&1; then
      npm install --omit=dev || true
    fi
  )
fi

has_model_secret=false
for var_name in OPENAI_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY LITELLM_API_KEY CUSTOM_API_KEY; do
  if [ -n "${!var_name:-}" ]; then
    has_model_secret=true
  fi
done

should_write_config=false
case "$CLAWDBOT_AUTO_CONFIG" in
  true|1|yes) should_write_config=true ;;
  false|0|no) should_write_config=false ;;
  auto) if [ "$has_model_secret" = "true" ]; then should_write_config=true; fi ;;
  *) if [ "$has_model_secret" = "true" ]; then should_write_config=true; fi ;;
esac

if [ ! -f "$OPENCLAW_CONFIG_PATH" ] && [ "$should_write_config" = "true" ]; then
  log "create first-boot openclaw.json on volume"
  node > "$OPENCLAW_CONFIG_PATH" <<'NODE'
const env = process.env;
const provider = env.DEEPSEEK_API_KEY ? "deepseek" : env.OPENROUTER_API_KEY ? "openrouter" : env.LITELLM_API_KEY ? "litellm" : env.CUSTOM_API_KEY ? "custom" : "openai";
const modelMap = {
  openai: env.OPENAI_MODEL || "openai/gpt-4.1-mini",
  deepseek: env.DEEPSEEK_MODEL || "deepseek/deepseek-chat",
  openrouter: env.OPENROUTER_MODEL || "openrouter/openai/gpt-4.1-mini",
  litellm: env.LITELLM_MODEL || "litellm/openai/gpt-4.1-mini",
  custom: env.CUSTOM_MODEL || "custom/default",
};
const primary = modelMap[provider];
const config = {
  meta: { template: "clawdbot-client-pack", clientPackVersion: "0.1.0", generatedAt: new Date().toISOString() },
  env: {
    OPENAI_API_KEY: env.OPENAI_API_KEY || undefined,
    OPENAI_BASE_URL: env.OPENAI_BASE_URL || "https://api.openai.com/v1",
    DEEPSEEK_API_KEY: env.DEEPSEEK_API_KEY || undefined,
    DEEPSEEK_BASE_URL: env.DEEPSEEK_BASE_URL || "https://api.deepseek.com/v1",
    OPENROUTER_API_KEY: env.OPENROUTER_API_KEY || undefined,
    OPENROUTER_BASE_URL: env.OPENROUTER_BASE_URL || "https://openrouter.ai/api/v1",
    LITELLM_API_KEY: env.LITELLM_API_KEY || undefined,
    LITELLM_BASE_URL: env.LITELLM_BASE_URL || undefined,
    CUSTOM_API_KEY: env.CUSTOM_API_KEY || undefined,
    CUSTOM_BASE_URL: env.CUSTOM_BASE_URL || undefined,
    BRAVE_SEARCH_API_KEY: env.BRAVE_SEARCH_API_KEY || undefined,
    SUPERMEMORY_API_KEY: env.SUPERMEMORY_API_KEY || undefined,
  },
  diagnostics: { otel: { enabled: env.OTEL_ENABLED !== "false" }, cacheTrace: { enabled: env.CACHE_TRACE_ENABLED === "true" } },
  agents: {
    defaults: { model: { primary }, models: { [primary]: {} }, compaction: { mode: "safeguard" } },
    list: [
      { id: "main" },
      { id: "life-router", name: "life-router", workspace: `${env.OPENCLAW_WORKSPACE_DIR}/life-router`, agentDir: `${env.OPENCLAW_STATE_DIR}/agents/life-router/agent`, allowedTools: ["message", "read", "grep", "search_code", "exec"] },
      { id: "sales-agent", name: "sales-agent", workspace: `${env.OPENCLAW_WORKSPACE_DIR}/sales-agent`, agentDir: `${env.OPENCLAW_STATE_DIR}/agents/sales-agent/agent` },
      { id: "support-agent", name: "support-agent", workspace: `${env.OPENCLAW_WORKSPACE_DIR}/support-agent`, agentDir: `${env.OPENCLAW_STATE_DIR}/agents/support-agent/agent` },
      { id: "memory-agent", name: "memory-agent", workspace: `${env.OPENCLAW_WORKSPACE_DIR}/memory-agent`, agentDir: `${env.OPENCLAW_STATE_DIR}/agents/memory-agent/agent` },
      { id: "critic-agent", name: "critic-agent", workspace: `${env.OPENCLAW_WORKSPACE_DIR}/critic-agent`, agentDir: `${env.OPENCLAW_STATE_DIR}/agents/critic-agent/agent` },
      { id: "golden-tester", name: "golden-tester", workspace: `${env.OPENCLAW_WORKSPACE_DIR}/golden-tester`, agentDir: `${env.OPENCLAW_STATE_DIR}/agents/golden-tester/agent` },
    ],
  },
  tools: { web: { search: { enabled: Boolean(env.BRAVE_SEARCH_API_KEY), apiKey: env.BRAVE_SEARCH_API_KEY || undefined }, fetch: { enabled: true } } },
  bindings: [
    { agentId: "life-router", match: { channel: "telegram" } },
    { agentId: "life-router", match: { channel: "vk" } },
  ],
  commands: { native: "auto", nativeSkills: "auto", restart: true },
  hooks: { internal: { enabled: true, entries: { "session-memory": { enabled: true }, "command-logger": { enabled: true }, "golden-router": { enabled: true }, "fsm-runtime": { enabled: true } } } },
  channels: {
    telegram: {
      enabled: env.TELEGRAM_ENABLED === "true",
      dmPolicy: "allowlist",
      botToken: env.TELEGRAM_BOT_TOKEN || undefined,
      allowFrom: (env.TELEGRAM_ALLOW_FROM || "").split(",").map(v => v.trim()).filter(Boolean).map(Number),
      groupPolicy: "allowlist",
      groupAllowFrom: (env.TELEGRAM_GROUP_ALLOW_FROM || "").split(",").map(v => v.trim()).filter(Boolean).map(Number),
      streamMode: env.TELEGRAM_STREAM_MODE || "partial",
    },
    vk: { enabled: env.VK_ENABLED !== "false" },
  },
  gateway: {
    port: Number(env.INTERNAL_GATEWAY_PORT || 18789),
    mode: "local",
    bind: env.INTERNAL_GATEWAY_BIND || "lan",
    controlUi: { allowInsecureAuth: env.CONTROL_UI_ALLOW_INSECURE_AUTH === "true" },
    auth: { mode: "token", token: env.OPENCLAW_GATEWAY_TOKEN || undefined },
    trustedProxies: ["100.64.0.0/10", "127.0.0.1"],
  },
  skills: {
    load: { extraDirs: [env.OPENCLAW_SKILLS_DIR, `${env.OPENCLAW_WORKSPACE_DIR}/skills`, env.CLAWDBOT_SKILLS_DIR].filter(Boolean), watch: true },
    entries: {
      bmad: { enabled: true },
      "client-intake": { enabled: true },
      "sales-qualification": { enabled: true },
      "objection-handling": { enabled: true },
      "lead-summary": { enabled: true },
      "handoff-human": { enabled: true },
      "brave-search": { enabled: Boolean(env.BRAVE_SEARCH_API_KEY), apiKey: env.BRAVE_SEARCH_API_KEY || undefined },
    },
  },
  plugins: {
    enabled: true,
    load: { paths: [env.OPENCLAW_VK_PLUGIN_DIR || `${env.OPENCLAW_PLUGINS_DIR}/openclaw-vk`] },
    entries: { telegram: { enabled: env.TELEGRAM_ENABLED === "true" }, fsm: { enabled: true }, "openclaw-channel-vk": { enabled: env.VK_ENABLED !== "false" } },
  },
};
function stripUndefined(value) {
  if (Array.isArray(value)) return value.map(stripUndefined).filter(v => v !== undefined);
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, val] of Object.entries(value)) {
      const clean = stripUndefined(val);
      if (clean !== undefined) out[key] = clean;
    }
    return out;
  }
  return value === undefined ? undefined : value;
}
process.stdout.write(JSON.stringify(stripUndefined(config), null, 2));
NODE
  chmod 600 "$OPENCLAW_CONFIG_PATH" || true
else
  log "preserve existing config or wait for setup wizard"
fi

if [ ! -d /data/.linuxbrew ]; then
  log "copy Homebrew to volume"
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

chown -R openclaw:openclaw /data
chmod 700 /data

log "OpenClaw version: $(node /usr/local/lib/node_modules/openclaw/dist/entry.js --version 2>/dev/null || true)"
exec gosu openclaw node src/server.js
EOF
RUN chmod +x /app/docker-entrypoint.sh

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json
ENV OPENCLAW_SKILLS_DIR=/data/.openclaw/skills
ENV OPENCLAW_PLUGINS_DIR=/data/openclaw-plugins
ENV OPENCLAW_VK_PLUGIN_DIR=/data/openclaw-plugins/openclaw-vk
ENV CLAWDBOT_STATE_DIR=/data/.clawdbot
ENV CLAWDBOT_WORKSPACE_DIR=/data/workspace
ENV CLAWDBOT_SKILLS_DIR=/data/.clawdbot/skills
ENV CLAWDBOT_PLUGINS_DIR=/data/clawdbot-plugins
ENV CLAWDBOT_AUTO_CONFIG=auto
ENV CLAWDBOT_INSTALL_VK_PLUGIN=true
ENV CLAWDBOT_VK_PLUGIN_REPO=https://github.com/fibbersha-hub/openclaw-vk-plugin.git
ENV INTERNAL_GATEWAY_BIND=lan
ENV INTERNAL_GATEWAY_PORT=18789
ENV SELF_HEAL_MAX_ATTEMPTS=3
ENV TELEGRAM_ENABLED=false
ENV VK_ENABLED=true

VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["/app/docker-entrypoint.sh"]
