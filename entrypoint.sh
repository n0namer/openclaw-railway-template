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
export CLAWDBOT_CLIENT_PACK="${CLAWDBOT_CLIENT_PACK:-default}"
export CLAWDBOT_AUTO_CONFIG="${CLAWDBOT_AUTO_CONFIG:-auto}"
export CLAWDBOT_BOOTSTRAP_SKILLS="${CLAWDBOT_BOOTSTRAP_SKILLS:-true}"
export CLAWDBOT_BOOTSTRAP_PLUGINS="${CLAWDBOT_BOOTSTRAP_PLUGINS:-true}"
export INTERNAL_GATEWAY_BIND="${INTERNAL_GATEWAY_BIND:-lan}"
export INTERNAL_GATEWAY_PORT="${INTERNAL_GATEWAY_PORT:-18789}"
export SELF_HEAL_MAX_ATTEMPTS="${SELF_HEAL_MAX_ATTEMPTS:-3}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-/data/npm-cache}"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-/data/npm}"
export PNPM_HOME="${PNPM_HOME:-/data/pnpm}"
export PNPM_STORE_DIR="${PNPM_STORE_DIR:-/data/pnpm-store}"
export PATH="${NPM_CONFIG_PREFIX}/bin:${PNPM_HOME}:${PATH}"

CLIENT_PACK_DIR="/app/client-pack/${CLAWDBOT_CLIENT_PACK}"
OPENCLAW_BIN="node ${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}"

mkdir -p \
  "$OPENCLAW_STATE_DIR" \
  "$OPENCLAW_WORKSPACE_DIR" \
  "$OPENCLAW_SKILLS_DIR" \
  "$OPENCLAW_PLUGINS_DIR" \
  "$CLAWDBOT_STATE_DIR" \
  "$CLAWDBOT_SKILLS_DIR" \
  "$CLAWDBOT_PLUGINS_DIR" \
  "$CLAWDBOT_STATE_DIR/installed-skills" \
  "$CLAWDBOT_STATE_DIR/installed-plugins" \
  "$CLAWDBOT_STATE_DIR/templates" \
  "$OPENCLAW_WORKSPACE_DIR/skills" \
  "$OPENCLAW_WORKSPACE_DIR/plugins" \
  "$OPENCLAW_WORKSPACE_DIR/agents" \
  "$OPENCLAW_STATE_DIR/agents" \
  "$OPENCLAW_STATE_DIR/logs" \
  "$NPM_CONFIG_CACHE" \
  "$NPM_CONFIG_PREFIX" \
  "$PNPM_HOME" \
  "$PNPM_STORE_DIR" \
  /data/backups

if [ ! -d /data/.linuxbrew ]; then
  log 'copy Homebrew to persistent volume'
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

render_config_if_missing() {
  if [ -f "$OPENCLAW_CONFIG_PATH" ]; then
    log "preserve existing OpenClaw config: $OPENCLAW_CONFIG_PATH"
    return 0
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

  if [ "$should_write_config" != "true" ]; then
    log "skip auto config: no model key or CLAWDBOT_AUTO_CONFIG=$CLAWDBOT_AUTO_CONFIG"
    return 0
  fi

  log "create first-boot OpenClaw config: $OPENCLAW_CONFIG_PATH"
  mkdir -p "$(dirname "$OPENCLAW_CONFIG_PATH")"
  if [ -f "$CLIENT_PACK_DIR/openclaw.template.json" ]; then
    node /app/client-pack/render-openclaw-config.mjs "$CLIENT_PACK_DIR/openclaw.template.json" > "$OPENCLAW_CONFIG_PATH"
  else
    node /app/client-pack/render-openclaw-config.mjs > "$OPENCLAW_CONFIG_PATH"
  fi
  chmod 600 "$OPENCLAW_CONFIG_PATH" || true
}

safe_marker_name() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9_.-]#__#g'
}

install_skill_once() {
  local spec="$1"
  [ -z "$spec" ] && return 0
  case "$spec" in \#*) return 0 ;; esac

  local marker_name
  marker_name="$(safe_marker_name "$spec")"
  local marker="$CLAWDBOT_STATE_DIR/installed-skills/${marker_name}.done"

  if [ -f "$marker" ]; then
    log "skill already installed: $spec"
    return 0
  fi

  log "install ClawHub skill: $spec"
  if gosu openclaw $OPENCLAW_BIN skills install "$spec"; then
    mkdir -p "$(dirname "$marker")"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$marker"
  else
    log "warning: skill install failed: $spec"
    return 1
  fi
}

install_plugin_once() {
  local line="$1"
  [ -z "$line" ] && return 0
  case "$line" in \#*) return 0 ;; esac

  local spec="${line%%|*}"
  local plugin_id=""
  if [ "$line" != "$spec" ]; then
    plugin_id="${line#*|}"
  fi

  local marker_name
  marker_name="$(safe_marker_name "$spec")"
  local marker="$CLAWDBOT_STATE_DIR/installed-plugins/${marker_name}.done"

  if [ ! -f "$marker" ]; then
    log "install OpenClaw plugin: $spec"
    if gosu openclaw $OPENCLAW_BIN plugins install "$spec"; then
      mkdir -p "$(dirname "$marker")"
      date -u +%Y-%m-%dT%H:%M:%SZ > "$marker"
    else
      log "warning: plugin install failed: $spec"
      return 1
    fi
  else
    log "plugin already installed: $spec"
  fi

  if [ -n "$plugin_id" ]; then
    log "enable plugin: $plugin_id"
    gosu openclaw $OPENCLAW_BIN plugins enable "$plugin_id" || log "warning: plugin enable failed: $plugin_id"
  fi
}

bootstrap_skills() {
  if [ "$CLAWDBOT_BOOTSTRAP_SKILLS" != "true" ]; then
    log 'skip skills bootstrap'
    return 0
  fi
  local list_file="$CLIENT_PACK_DIR/skills.list"
  if [ ! -f "$list_file" ]; then
    log "skills list not found: $list_file"
    return 0
  fi
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line="$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    install_skill_once "$line" || true
  done < "$list_file"
}

bootstrap_plugins() {
  if [ "$CLAWDBOT_BOOTSTRAP_PLUGINS" != "true" ]; then
    log 'skip plugins bootstrap'
    return 0
  fi
  local list_file="$CLIENT_PACK_DIR/plugins.list"
  if [ ! -f "$list_file" ]; then
    log "plugins list not found: $list_file"
    return 0
  fi
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line="$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    install_plugin_once "$line" || true
  done < "$list_file"
}

if [ ! -d "$CLIENT_PACK_DIR" ]; then
  log "client pack not found: $CLIENT_PACK_DIR"
else
  cp -a "$CLIENT_PACK_DIR" "$CLAWDBOT_STATE_DIR/templates/${CLAWDBOT_CLIENT_PACK}" 2>/dev/null || true
fi

chown -R openclaw:openclaw /data
chmod 700 /data

render_config_if_missing
bootstrap_skills
bootstrap_plugins

cat > "$CLAWDBOT_STATE_DIR/client-pack.manifest.json" <<JSON
{
  "clientPack": "$CLAWDBOT_CLIENT_PACK",
  "stateDir": "$OPENCLAW_STATE_DIR",
  "workspaceDir": "$OPENCLAW_WORKSPACE_DIR",
  "configPath": "$OPENCLAW_CONFIG_PATH",
  "bootstrappedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
chown openclaw:openclaw "$CLAWDBOT_STATE_DIR/client-pack.manifest.json" || true

log "OpenClaw version: $(node "${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}" --version 2>/dev/null || true)"
exec gosu openclaw node src/server.js
