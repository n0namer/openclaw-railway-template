#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="configure-existing-openclaw-railway"
MODE="check"
NO_RAILWAY=false
STRICT=true
ENV_FILE=".agent.env"
REPORT_DIR=".agent-reports"
MANIFEST_FILE="installer.manifest.json"

log() {
  printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
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

usage() {
  cat <<'USAGE'
Usage:
  bash tools/configure-existing-openclaw-railway.sh [mode] [options]

Modes:
  --check      Run local consistency checks only. Default.
  --vars       Run checks and set Railway variables.
  --deploy     Run checks, set Railway variables, then railway up.
  --redeploy   Run checks, set Railway variables, then railway redeploy.
  --logs       Collect latest Railway deployment logs.

Options:
  --env-file PATH   Load env from PATH. Default: .agent.env
  --no-railway      Skip Railway CLI checks and Railway actions.
  --no-strict       Downgrade some repo consistency checks to warnings. Not allowed for --deploy.
  --help            Show this help.

Required local file:
  .agent.env        Copy from .agent.env.example and fill locally. Never commit it.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check|--vars|--deploy|--redeploy|--logs)
      MODE="${1#--}"
      shift
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      [ -n "$ENV_FILE" ] || fail "--env-file requires a path"
      shift 2
      ;;
    --no-railway)
      NO_RAILWAY=true
      shift
      ;;
    --no-strict)
      STRICT=false
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [ "$MODE" = "deploy" ] && [ "$STRICT" != "true" ]; then
  fail "--deploy requires strict checks; remove --no-strict"
fi

ROOT_DIR="$(pwd)"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
REPORT_FILE="$REPORT_DIR/${TIMESTAMP}-${SCRIPT_NAME}.log"

mkdir -p "$REPORT_DIR"

run_and_log() {
  log "+ $*"
  "$@" 2>&1 | tee -a "$REPORT_FILE"
}

append_report_header() {
  {
    printf 'RAILWAY CONFIGURE REPORT\n'
    printf 'timestamp_utc=%s\n' "$TIMESTAMP"
    printf 'mode=%s\n' "$MODE"
    printf 'root=%s\n' "$ROOT_DIR"
    printf '\n'
  } > "$REPORT_FILE"
}

load_env() {
  [ -f "$ENV_FILE" ] || fail "missing $ENV_FILE; copy .agent.env.example to $ENV_FILE and fill it locally"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ] || [ "${!name:-}" = "REPLACE_ME" ]; then
    fail "missing required env: $name"
  fi
}

maybe_warn_env() {
  local name="$1"
  if [ -z "${!name:-}" ] || [ "${!name:-}" = "REPLACE_ME" ]; then
    warn "optional env is empty: $name"
  fi
}

require_file() {
  local file="$1"
  [ -f "$file" ] || fail "missing required file: $file"
}

require_grep() {
  local pattern="$1"
  local file="$2"
  grep -qE "$pattern" "$file" || fail "required pattern not found in $file: $pattern"
}

forbid_grep() {
  local pattern="$1"
  shift
  if grep -R -nE "$pattern" "$@" 2>/dev/null | tee -a "$REPORT_FILE"; then
    if [ "$STRICT" = "true" ]; then
      fail "forbidden pattern found: $pattern"
    fi
    warn "forbidden pattern found but --no-strict is enabled: $pattern"
  fi
}

count_exact() {
  local pattern="$1"
  local file="$2"
  local expected="$3"
  local count
  count="$(grep -cE "$pattern" "$file" || true)"
  if [ "$count" != "$expected" ]; then
    fail "unexpected count in $file for [$pattern]: got $count, expected $expected"
  fi
}

check_required_files() {
  log "check required files"
  require_file "$MANIFEST_FILE"

  local files
  files="$(node -e "const m=require('./${MANIFEST_FILE}'); for (const f of m.requiredFiles) console.log(f)")"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    require_file "$file"
  done <<< "$files"
}

check_syntax() {
  log "check syntax"
  bash -n entrypoint.sh
  bash -n client-pack/sync-skills.sh
  bash -n client-pack/verify-runtime.sh

  node --check client-pack/render-openclaw-config.mjs
  node --check client-pack/sync-config-from-env.mjs
  node --check client-pack/verify-config.mjs

  python3 - <<'PY'
try:
    import tomllib
except ModuleNotFoundError:
    print('WARN: tomllib unavailable; skip railway.toml parse')
    raise SystemExit(0)
with open('railway.toml', 'rb') as f:
    tomllib.load(f)
print('toml ok')
PY
}

check_forbidden_patterns() {
  log "check forbidden patterns"
  forbid_grep '<<<<<<<|=======|>>>>>>>' . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.agent-reports --exclude='.agent.env'
  forbid_grep 'VOLUME[[:space:]]*\["/data"\]' Dockerfile
  forbid_grep '/data/\.clawdbot' Dockerfile entrypoint.sh client-pack/*.sh client-pack/*.mjs
  forbid_grep '/data/openclaw-plugins|/data/clawdbot-plugins' Dockerfile entrypoint.sh client-pack/*.sh client-pack/*.mjs
}

check_invariants() {
  log "check repo invariants"
  require_grep '^ENV OPENCLAW_STATE_DIR=/data/\.openclaw$' Dockerfile
  require_grep '^ENV OPENCLAW_PACK_STATE_DIR=/data/\.openclaw/client-pack$' Dockerfile
  require_grep '^ENV OPENCLAW_CONFIG_PATH=/data/\.openclaw/openclaw\.json$' Dockerfile
  require_grep '^ENV OPENCLAW_PLUGINS_DIR=/data/\.openclaw/extensions$' Dockerfile
  require_grep '^ENV OPENCLAW_SKILLS_ALLOWLIST_PATH=/data/\.openclaw/client-pack/skills\.allowlist$' Dockerfile
  require_grep '^ENV OPENCLAW_ENABLE_VK=true$' Dockerfile

  count_exact '^ENV OPENCLAW_STATE_DIR=' Dockerfile 1
  count_exact '^ENV OPENCLAW_SKILLS_DIR=' Dockerfile 1
  count_exact '^ENV OPENCLAW_PACK_STATE_DIR=' Dockerfile 1

  require_grep '^builder = "DOCKERFILE"$' railway.toml
  require_grep '^healthcheckPath = "/setup/healthz"$' railway.toml
  require_grep '^requiredMountPath = "/data"$' railway.toml
}

check_env() {
  log "check local env"
  require_env RAILWAY_SERVICE
  require_env RAILWAY_ENVIRONMENT
  require_env OPENCLAW_LLM_KEY
  require_env OPENCLAW_LLM_MODEL
  require_env OPENCLAW_LLM_BASE_URL
  require_env OPENCLAW_ENABLE_VK

  if is_true "$OPENCLAW_ENABLE_VK"; then
    require_env VK_COMMUNITY_TOKEN
    require_env VK_GROUP_ID
  else
    maybe_warn_env VK_COMMUNITY_TOKEN
    maybe_warn_env VK_GROUP_ID
  fi
}

check_railway() {
  [ "$NO_RAILWAY" = "true" ] && { log "skip Railway checks (--no-railway)"; return 0; }
  log "check Railway CLI"
  command -v railway >/dev/null 2>&1 || fail "Railway CLI not found"
  railway status 2>&1 | tee -a "$REPORT_FILE" || fail "railway status failed; run railway login and railway link"
}

set_railway_var() {
  local key="$1"
  local value="$2"
  [ "$NO_RAILWAY" = "true" ] && { log "skip variable set $key (--no-railway)"; return 0; }
  log "set Railway variable: $key"
  railway variable set "${key}=${value}" --service "$RAILWAY_SERVICE" --environment "$RAILWAY_ENVIRONMENT" 2>&1 | tee -a "$REPORT_FILE"
}

set_railway_variables() {
  log "set Railway variables"
  set_railway_var OPENCLAW_VERSION "${OPENCLAW_VERSION:-2026.4.23}"
  set_railway_var NODE_ENV "${NODE_ENV:-production}"
  set_railway_var OPENCLAW_LLM_KEY "$OPENCLAW_LLM_KEY"
  set_railway_var OPENCLAW_LLM_MODEL "$OPENCLAW_LLM_MODEL"
  set_railway_var OPENCLAW_LLM_BASE_URL "$OPENCLAW_LLM_BASE_URL"
  set_railway_var OPENCLAW_ENABLE_VK "$OPENCLAW_ENABLE_VK"
  set_railway_var VK_COMMUNITY_TOKEN "${VK_COMMUNITY_TOKEN:-}"
  set_railway_var VK_GROUP_ID "${VK_GROUP_ID:-}"
  set_railway_var OPENCLAW_VERIFY_LIVE_MODEL "${OPENCLAW_VERIFY_LIVE_MODEL:-false}"
  set_railway_var OPENCLAW_RUN_DOCTOR "${OPENCLAW_RUN_DOCTOR:-true}"
  set_railway_var OPENCLAW_SYNC_CONFIG_FROM_ENV "${OPENCLAW_SYNC_CONFIG_FROM_ENV:-true}"
  set_railway_var RAILWAY_HEALTHCHECK_TIMEOUT_SEC "${RAILWAY_HEALTHCHECK_TIMEOUT_SEC:-600}"
}

deploy_local_repo() {
  [ "$NO_RAILWAY" = "true" ] && { log "skip railway up (--no-railway)"; return 0; }
  log "deploy local repo with railway up"
  railway up --service "$RAILWAY_SERVICE" --environment "$RAILWAY_ENVIRONMENT" 2>&1 | tee -a "$REPORT_FILE"
}

redeploy_service() {
  [ "$NO_RAILWAY" = "true" ] && { log "skip railway redeploy (--no-railway)"; return 0; }
  log "redeploy existing Railway service"
  railway redeploy --service "$RAILWAY_SERVICE" --environment "$RAILWAY_ENVIRONMENT" --yes 2>&1 | tee -a "$REPORT_FILE"
}

collect_logs() {
  [ "$NO_RAILWAY" = "true" ] && { log "skip logs (--no-railway)"; return 0; }
  log "collect latest deployment logs"
  railway logs --latest --deployment --lines 300 --service "$RAILWAY_SERVICE" --environment "$RAILWAY_ENVIRONMENT" 2>&1 | tee -a "$REPORT_FILE" || warn "failed to collect Railway logs"
}

write_repo_report() {
  {
    printf '\nRepo:\n'
    printf -- '- branch: '
    git rev-parse --abbrev-ref HEAD 2>/dev/null || true
    printf -- '- commit: '
    git rev-parse HEAD 2>/dev/null || true
    printf -- '- dirty files:\n'
    git status --short 2>/dev/null || true
    printf '\nRailway target:\n'
    printf -- '- service: %s\n' "${RAILWAY_SERVICE:-unset}"
    printf -- '- environment: %s\n' "${RAILWAY_ENVIRONMENT:-unset}"
    printf -- '- mode: %s\n' "$MODE"
  } >> "$REPORT_FILE"
}

main() {
  append_report_header
  load_env
  write_repo_report

  check_required_files
  check_syntax
  check_forbidden_patterns
  check_invariants
  check_env
  check_railway

  case "$MODE" in
    check)
      log "check ok"
      ;;
    vars)
      set_railway_variables
      ;;
    deploy)
      set_railway_variables
      deploy_local_repo
      collect_logs
      ;;
    redeploy)
      set_railway_variables
      redeploy_service
      collect_logs
      ;;
    logs)
      collect_logs
      ;;
    *)
      fail "unsupported mode: $MODE"
      ;;
  esac

  log "report: $REPORT_FILE"
}

main "$@"
