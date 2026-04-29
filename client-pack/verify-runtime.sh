#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"
CLAWDBOT_STATE_DIR="${CLAWDBOT_STATE_DIR:-/data/.clawdbot}"
CLAWDBOT_SKILLS_ALLOWLIST_PATH="${CLAWDBOT_SKILLS_ALLOWLIST_PATH:-${CLAWDBOT_STATE_DIR}/skills.allowlist}"
OPENCLAW_LLM_KEY="${OPENCLAW_LLM_KEY:-${DEEPSEEK_API_KEY:-}}"
DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY:-${OPENCLAW_LLM_KEY:-}}"
OPENCLAW_LLM_MODEL="${OPENCLAW_LLM_MODEL:-${CLAWDBOT_DEFAULT_MODEL:-deepseek/deepseek-chat}}"
OPENCLAW_LLM_BASE_URL="${OPENCLAW_LLM_BASE_URL:-https://api.deepseek.com}"
CLAWDBOT_DEFAULT_PROVIDER="${CLAWDBOT_DEFAULT_PROVIDER:-deepseek}"
CLAWDBOT_DEFAULT_MODEL="$OPENCLAW_LLM_MODEL"
OPENCLAW_VERIFY_LIVE_MODEL="${OPENCLAW_VERIFY_LIVE_MODEL:-false}"
export OPENCLAW_LLM_KEY DEEPSEEK_API_KEY OPENCLAW_LLM_MODEL OPENCLAW_LLM_BASE_URL CLAWDBOT_DEFAULT_MODEL OPENCLAW_VERIFY_LIVE_MODEL
OPENCLAW_ENTRY="${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}"
OPENCLAW_BIN=(node "$OPENCLAW_ENTRY")
LOG_DIR="${CLAWDBOT_STATE_DIR}/logs"
LOG_FILE="${LOG_DIR}/verify-runtime.log"

mkdir -p "$LOG_DIR"

ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

log() {
  printf '[verify-runtime] %s %s\n' "$(ts)" "$*" | tee -a "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  exit 1
}

warn() {
  log "warning: $*"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

require_writable_dir() {
  require_dir "$1"
  local probe="$1/.verify-runtime-write-test.$$"
  if ! touch "$probe" 2>/dev/null; then
    fail "directory is not writable: $1"
  fi
  rm -f "$probe"
}

validate_config_if_present() {
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    warn "OpenClaw config missing: $OPENCLAW_CONFIG_PATH"
    return 0
  fi

  log "validate config: $OPENCLAW_CONFIG_PATH"
  cd "$OPENCLAW_WORKSPACE_DIR"
  "${OPENCLAW_BIN[@]}" config validate >> "$LOG_FILE" 2>&1 || fail "openclaw config validate failed"
  log "config valid"
}

verify_config_invariants() {
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    warn "skip config invariant verifier: config missing"
    return 0
  fi
  if [ ! -f /app/client-pack/verify-config.mjs ]; then
    warn "skip config invariant verifier: /app/client-pack/verify-config.mjs missing"
    return 0
  fi

  log "run config invariant verifier"
  node /app/client-pack/verify-config.mjs >> "$LOG_FILE" 2>&1 || fail "config invariant verifier failed"
  log "config invariants valid"
}

ensure_deepseek_default_model() {
  if [ "$CLAWDBOT_DEFAULT_PROVIDER" != "deepseek" ]; then
    log "default provider is not deepseek; skip DeepSeek checks: $CLAWDBOT_DEFAULT_PROVIDER"
    return 0
  fi

  if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
    warn "DEEPSEEK_API_KEY missing; DeepSeek provider not configured"
    return 0
  fi

  log "DeepSeek key present"
  cd "$OPENCLAW_WORKSPACE_DIR"

  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    log "create DeepSeek config via openclaw onboard"
    "${OPENCLAW_BIN[@]}" onboard \
      --non-interactive \
      --mode local \
      --auth-choice deepseek-api-key \
      --deepseek-api-key "$DEEPSEEK_API_KEY" \
      --skip-health \
      --accept-risk >> "$LOG_FILE" 2>&1 || fail "DeepSeek onboard failed"
  fi

  current_model="$("${OPENCLAW_BIN[@]}" config get agents.defaults.model.primary 2>/dev/null || true)"
  if printf '%s' "$current_model" | grep -Fq "$CLAWDBOT_DEFAULT_MODEL"; then
    log "default model ok: $CLAWDBOT_DEFAULT_MODEL"
  else
    log "set default model: $CLAWDBOT_DEFAULT_MODEL"
    "${OPENCLAW_BIN[@]}" config set agents.defaults.model.primary "$CLAWDBOT_DEFAULT_MODEL" >> "$LOG_FILE" 2>&1 || fail "failed to set default model"
  fi

  "${OPENCLAW_BIN[@]}" config validate >> "$LOG_FILE" 2>&1 || fail "config invalid after DeepSeek setup"

  if is_true "$CLAWDBOT_VERIFY_LIVE_MODEL"; then
    log "live model check enabled: openclaw models list --provider deepseek"
    "${OPENCLAW_BIN[@]}" models list --provider deepseek >> "$LOG_FILE" 2>&1 || fail "DeepSeek live model check failed"
  else
    log "live model check disabled"
  fi
}

verify_vk_inputs() {
  if is_true "${CLAWDBOT_ENABLE_VK:-false}"; then
    [ -n "${VK_COMMUNITY_TOKEN:-}" ] || warn "CLAWDBOT_ENABLE_VK=true but VK_COMMUNITY_TOKEN missing"
    [ -n "${VK_GROUP_ID:-}" ] || warn "CLAWDBOT_ENABLE_VK=true but VK_GROUP_ID missing"
    log "VK enabled"
  else
    log "VK disabled"
  fi
}

main() {
  log "verify start"

  if [ "${RAILWAY_VOLUME_MOUNT_PATH:-}" != "/data" ]; then
    fail "Railway volume must be mounted at /data; got '${RAILWAY_VOLUME_MOUNT_PATH:-unset}'"
  fi

  require_writable_dir /data
  require_writable_dir "$OPENCLAW_STATE_DIR"
  require_writable_dir "$OPENCLAW_WORKSPACE_DIR"
  require_writable_dir "$CLAWDBOT_STATE_DIR"
  require_dir "${CLAWDBOT_STATE_DIR}/installed-skills"

  [ -f "$CLAWDBOT_SKILLS_ALLOWLIST_PATH" ] || fail "missing skills allowlist: $CLAWDBOT_SKILLS_ALLOWLIST_PATH"

  cd "$OPENCLAW_WORKSPACE_DIR"
  "${OPENCLAW_BIN[@]}" --version >> "$LOG_FILE" 2>&1 || fail "openclaw binary unavailable"
  log "openclaw version ok"

  active_config="$("${OPENCLAW_BIN[@]}" config file 2>/dev/null || true)"
  log "active config: ${active_config:-unknown}"

  validate_config_if_present
  ensure_deepseek_default_model
  validate_config_if_present
  verify_config_invariants
  verify_vk_inputs

  log "verify ok"
}

main "$@"
