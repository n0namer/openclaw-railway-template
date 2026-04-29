#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[clawdbot-entrypoint] %s\n' "$*"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
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
export CLAWDBOT_SKILLS_SYNC_ENABLED="${CLAWDBOT_SKILLS_SYNC_ENABLED:-true}"
export CLAWDBOT_SKILLS_SYNC_INTERVAL_SECONDS="${CLAWDBOT_SKILLS_SYNC_INTERVAL_SECONDS:-1800}"
export CLAWDBOT_SKILLS_UPDATE_ALL="${CLAWDBOT_SKILLS_UPDATE_ALL:-false}"
export CLAWDBOT_SKILLS_ALLOWLIST_PATH="${CLAWDBOT_SKILLS_ALLOWLIST_PATH:-${CLAWDBOT_STATE_DIR}/skills.allowlist}"
export CLAWDBOT_VERIFY_RUNTIME="${CLAWDBOT_VERIFY_RUNTIME:-true}"
export CLAWDBOT_DEFAULT_PROVIDER="${CLAWDBOT_DEFAULT_PROVIDER:-deepseek}"
export CLAWDBOT_DEFAULT_MODEL="${CLAWDBOT_DEFAULT_MODEL:-deepseek/deepseek-chat}"
export CLAWDBOT_VERIFY_LIVE_MODEL="${CLAWDBOT_VERIFY_LIVE_MODEL:-false}"
export CLAWDBOT_ENABLE_VK="${CLAWDBOT_ENABLE_VK:-false}"
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

if [ "${RAILWAY_VOLUME_MOUNT_PATH:-}" != "/data" ]; then
  log "ERROR: Railway volume must be mounted at /data"
  log "RAILWAY_VOLUME_MOUNT_PATH=${RAILWAY_VOLUME_MOUNT_PATH:-unset}"
  exit 1
fi

if ! mkdir -p /data/.clawdbot 2>/dev/null || ! touch /data/.clawdbot-write-test 2>/dev/null; then
  log "ERROR: /data is not writable"
  exit 1
fi
rm -f /data/.clawdbot-write-test

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
  "$CLAWDBOT_STATE_DIR/logs" \
  "$CLAWDBOT_STATE_DIR/locks" \
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

seed_skills_allowlist_if_missing() {
  local source_list="$CLIENT_PACK_DIR/skills.list"
  if [ -f "$CLAWDBOT_SKILLS_ALLOWLIST_PATH" ]; then
    log "preserve existing skills allowlist: $CLAWDBOT_SKILLS_ALLOWLIST_PATH"
    return 0
  fi
  mkdir -p "$(dirname "$CLAWDBOT_SKILLS_ALLOWLIST_PATH")"
  if [ -f "$source_list" ]; then
    log "seed skills allowlist from client pack: $CLAWDBOT_SKILLS_ALLOWLIST_PATH"
    cp -a "$source_list" "$CLAWDBOT_SKILLS_ALLOWLIST_PATH"
  else
    log "create empty skills allowlist: $CLAWDBOT_SKILLS_ALLOWLIST_PATH"
    touch "$CLAWDBOT_SKILLS_ALLOWLIST_PATH"
  fi
}

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

  if [ ! -f /app/client-pack/render-openclaw-config.mjs ]; then
    log "warning: config renderer missing; skip auto config"
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

write_plugin_marker() {
  local marker="$1"
  local spec="$2"
  local tmp="${marker}.tmp.$$"
  {
    printf 'spec=%s\n' "$spec"
    printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'openclaw_version=%s\n' "$(node "${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}" --version 2>/dev/null || true)"
  } > "$tmp"
  mv "$tmp" "$marker"
}

install_plugin_once() {
  local line="$1"
  [ -z "$line" ] && return 0
  case "$line" in \#*) return 0 ;; esac

  local spec plugin_id marker_name marker
  spec="${line%%|*}"
  plugin_id=""
  if [ "$line" != "$spec" ]; then
    plugin_id="${line#*|}"
  fi

  marker_name="$(safe_marker_name "$spec")"
  marker="$CLAWDBOT_STATE_DIR/installed-plugins/${marker_name}.done"

  cd "$OPENCLAW_WORKSPACE_DIR"
  if [ ! -f "$marker" ]; then
    log "install OpenClaw plugin: $spec"
    if gosu openclaw $OPENCLAW_BIN plugins install "$spec"; then
      mkdir -p "$(dirname "$marker")"
      write_plugin_marker "$marker" "$spec"
    else
      rm -f "${marker}.tmp."* 2>/dev/null || true
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

sync_skills_once() {
  if ! is_true "$CLAWDBOT_BOOTSTRAP_SKILLS"; then
    log 'skip skills bootstrap'
    return 0
  fi
  if [ ! -f /app/client-pack/sync-skills.sh ]; then
    log 'warning: skills sync script missing'
    return 0
  fi
  gosu openclaw bash /app/client-pack/sync-skills.sh once || log 'warning: skills sync once failed'
}

verify_runtime() {
  if ! is_true "$CLAWDBOT_VERIFY_RUNTIME"; then
    log 'skip runtime verifier'
    return 0
  fi
  if [ ! -f /app/client-pack/verify-runtime.sh ]; then
    log 'warning: runtime verifier missing'
    return 0
  fi
  log 'run runtime verifier'
  gosu openclaw bash /app/client-pack/verify-runtime.sh || {
    log 'ERROR: runtime verifier failed'
    exit 1
  }
}

start_skills_sync_daemon() {
  if ! is_true "$CLAWDBOT_SKILLS_SYNC_ENABLED"; then
    log 'skip skills hot-sync daemon'
    return 0
  fi
  if [ ! -f /app/client-pack/sync-skills.sh ]; then
    log 'warning: skills sync script missing'
    return 0
  fi
  log "start skills hot-sync daemon, interval=${CLAWDBOT_SKILLS_SYNC_INTERVAL_SECONDS}s"
  gosu openclaw bash /app/client-pack/sync-skills.sh daemon >> "$CLAWDBOT_STATE_DIR/logs/skills-sync-daemon.log" 2>&1 &
}

bootstrap_plugins() {
  if ! is_true "$CLAWDBOT_BOOTSTRAP_PLUGINS"; then
    log 'skip plugins bootstrap'
    return 0
  fi

  if is_true "$CLAWDBOT_ENABLE_VK"; then
    export VK_GROUP_TOKEN="${VK_GROUP_TOKEN:-${VK_COMMUNITY_TOKEN:-}}"
    if [ -z "${VK_GROUP_TOKEN:-}" ] || [ -z "${VK_GROUP_ID:-}" ]; then
      log 'warning: CLAWDBOT_ENABLE_VK=true, but VK_COMMUNITY_TOKEN/VK_GROUP_ID is missing'
    fi
    install_plugin_once 'clawhub:vk-plugin|vk' || true
  else
    log 'skip VK plugin: CLAWDBOT_ENABLE_VK=false'
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
cd "$OPENCLAW_WORKSPACE_DIR"

seed_skills_allowlist_if_missing
render_config_if_missing
sync_skills_once
bootstrap_plugins
verify_runtime
start_skills_sync_daemon

cat > "$CLAWDBOT_STATE_DIR/client-pack.manifest.json" <<JSON
{
  "clientPack": "$CLAWDBOT_CLIENT_PACK",
  "stateDir": "$OPENCLAW_STATE_DIR",
  "workspaceDir": "$OPENCLAW_WORKSPACE_DIR",
  "configPath": "$OPENCLAW_CONFIG_PATH",
  "skillsAllowlistPath": "$CLAWDBOT_SKILLS_ALLOWLIST_PATH",
  "skillsSyncEnabled": "$CLAWDBOT_SKILLS_SYNC_ENABLED",
  "skillsSyncIntervalSeconds": "$CLAWDBOT_SKILLS_SYNC_INTERVAL_SECONDS",
  "verifyRuntime": "$CLAWDBOT_VERIFY_RUNTIME",
  "defaultProvider": "$CLAWDBOT_DEFAULT_PROVIDER",
  "defaultModel": "$CLAWDBOT_DEFAULT_MODEL",
  "vkEnabled": "${CLAWDBOT_ENABLE_VK}",
  "bootstrappedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
chown openclaw:openclaw "$CLAWDBOT_STATE_DIR/client-pack.manifest.json" || true

log "OpenClaw version: $(node "${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}" --version 2>/dev/null || true)"
exec gosu openclaw node /app/src/server.js
