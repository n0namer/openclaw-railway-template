#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[seed-volume] %s\n' "$*"
}

STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${STATE_DIR}/openclaw.json}"
OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-${STATE_DIR}/skills}"
OPENCLAW_PLUGINS_DIR="${OPENCLAW_PLUGINS_DIR:-/data/openclaw-plugins}"
CLAWDBOT_STATE_DIR="${CLAWDBOT_STATE_DIR:-/data/.clawdbot}"
CLAWDBOT_SKILLS_DIR="${CLAWDBOT_SKILLS_DIR:-${CLAWDBOT_STATE_DIR}/skills}"
CLAWDBOT_PLUGINS_DIR="${CLAWDBOT_PLUGINS_DIR:-/data/clawdbot-plugins}"
BACKUP_DIR="${CLAWDBOT_BACKUP_DIR:-/data/backups}"
VK_PLUGIN_DIR="${OPENCLAW_VK_PLUGIN_DIR:-${OPENCLAW_PLUGINS_DIR}/openclaw-vk}"
VK_PLUGIN_REPO="${CLAWDBOT_VK_PLUGIN_REPO:-https://github.com/fibbersha-hub/openclaw-vk-plugin.git}"
AUTO_CONFIG="${CLAWDBOT_AUTO_CONFIG:-auto}"
INSTALL_VK_PLUGIN="${CLAWDBOT_INSTALL_VK_PLUGIN:-true}"

mkdir -p \
  "$STATE_DIR" \
  "$WORKSPACE_DIR" \
  "$OPENCLAW_SKILLS_DIR" \
  "$OPENCLAW_PLUGINS_DIR" \
  "$CLAWDBOT_STATE_DIR" \
  "$CLAWDBOT_SKILLS_DIR" \
  "$CLAWDBOT_PLUGINS_DIR" \
  "$BACKUP_DIR" \
  "$WORKSPACE_DIR/skills" \
  "$WORKSPACE_DIR/plugins" \
  "$WORKSPACE_DIR/agents" \
  "$STATE_DIR/agents" \
  "$STATE_DIR/logs"

seed_dir_if_empty() {
  local src="$1"
  local dst="$2"
  if [ ! -d "$src" ]; then
    log "skip seed: source missing: $src"
    return 0
  fi
  mkdir -p "$dst"
  if [ -z "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
    log "seed $dst from $src"
    cp -a "$src"/. "$dst"/
  else
    log "skip seed: destination already has content: $dst"
  fi
}

seed_dir_if_empty "/app/seed/skills" "$WORKSPACE_DIR/skills"
seed_dir_if_empty "/app/seed/agents" "$WORKSPACE_DIR/agents"
seed_dir_if_empty "/app/seed/config" "$CLAWDBOT_STATE_DIR/templates"

if [ "$INSTALL_VK_PLUGIN" = "true" ] && [ ! -d "$VK_PLUGIN_DIR" ]; then
  log "clone VK plugin into persistent volume: $VK_PLUGIN_DIR"
  git clone --depth 1 "$VK_PLUGIN_REPO" "$VK_PLUGIN_DIR" || {
    log "warning: failed to clone VK plugin from $VK_PLUGIN_REPO"
  }
fi

if [ -d "$VK_PLUGIN_DIR" ]; then
  if [ -f "$VK_PLUGIN_DIR/package.json" ]; then
    log "prepare VK plugin dependencies on volume"
    (
      cd "$VK_PLUGIN_DIR"
      if command -v pnpm >/dev/null 2>&1; then
        pnpm install --prod --frozen-lockfile=false || pnpm install --prod || true
      elif command -v npm >/dev/null 2>&1; then
        npm install --omit=dev || true
      fi
    )
  fi
else
  log "VK plugin directory absent: $VK_PLUGIN_DIR"
fi

has_model_secret=false
for var_name in \
  OPENAI_API_KEY \
  DEEPSEEK_API_KEY \
  OPENROUTER_API_KEY \
  LITELLM_API_KEY \
  CUSTOM_API_KEY; do
  if [ -n "${!var_name:-}" ]; then
    has_model_secret=true
  fi
done

should_write_config=false
case "$AUTO_CONFIG" in
  true|1|yes) should_write_config=true ;;
  false|0|no) should_write_config=false ;;
  auto) if [ "$has_model_secret" = "true" ]; then should_write_config=true; fi ;;
  *) log "unknown CLAWDBOT_AUTO_CONFIG=$AUTO_CONFIG; treating as auto"; if [ "$has_model_secret" = "true" ]; then should_write_config=true; fi ;;
esac

if [ ! -f "$CONFIG_PATH" ] && [ "$should_write_config" = "true" ]; then
  log "create first-boot OpenClaw config: $CONFIG_PATH"
  mkdir -p "$(dirname "$CONFIG_PATH")"
  node /app/scripts/render-openclaw-config.mjs > "$CONFIG_PATH"
  chmod 600 "$CONFIG_PATH" || true
elif [ -f "$CONFIG_PATH" ]; then
  log "skip config seed: existing config preserved: $CONFIG_PATH"
else
  log "skip config seed: no model secret found and CLAWDBOT_AUTO_CONFIG=$AUTO_CONFIG"
fi

cat > "$CLAWDBOT_STATE_DIR/client-pack.manifest.json" <<JSON
{
  "name": "clawdbot-client-pack",
  "version": "0.1.0",
  "seededAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stateDir": "$STATE_DIR",
  "workspaceDir": "$WORKSPACE_DIR",
  "configPath": "$CONFIG_PATH",
  "skillsDir": "$OPENCLAW_SKILLS_DIR",
  "pluginsDir": "$OPENCLAW_PLUGINS_DIR",
  "vkPluginDir": "$VK_PLUGIN_DIR"
}
JSON

log "done"
