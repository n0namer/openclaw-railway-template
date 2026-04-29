#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[skills-sync] %s\n' "$*"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

safe_marker_name() {
  printf '%s' "$1" | sed 's#[^A-Za-z0-9_.-]#__#g'
}

OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
CLAWDBOT_STATE_DIR="${CLAWDBOT_STATE_DIR:-/data/.clawdbot}"
OPENCLAW_ENTRY="${OPENCLAW_ENTRY:-/usr/local/lib/node_modules/openclaw/dist/entry.js}"
ALLOWLIST_PATH="${CLAWDBOT_SKILLS_ALLOWLIST_PATH:-${CLAWDBOT_STATE_DIR}/skills.allowlist}"
MARKER_DIR="${CLAWDBOT_STATE_DIR}/installed-skills"
LOG_DIR="${CLAWDBOT_STATE_DIR}/logs"
LOCK_DIR="${CLAWDBOT_STATE_DIR}/locks"
SYNC_INTERVAL_SECONDS="${CLAWDBOT_SKILLS_SYNC_INTERVAL_SECONDS:-1800}"
OPENCLAW_BIN=(node "$OPENCLAW_ENTRY")

mkdir -p \
  "$CLAWDBOT_STATE_DIR" \
  "$MARKER_DIR" \
  "$LOG_DIR" \
  "$LOCK_DIR" \
  "$OPENCLAW_WORKSPACE_DIR/skills"

touch "$ALLOWLIST_PATH"

write_marker() {
  local marker="$1"
  local skill="$2"
  local tmp="${marker}.tmp.$$"
  {
    printf 'spec=%s\n' "$skill"
    printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'openclaw_version=%s\n' "$("${OPENCLAW_BIN[@]}" --version 2>/dev/null || true)"
  } > "$tmp"
  mv "$tmp" "$marker"
}

sync_body() {
  log "sync start: $ALLOWLIST_PATH"
  cd "$OPENCLAW_WORKSPACE_DIR"

  if is_true "${CLAWDBOT_SKILLS_UPDATE_ALL:-false}"; then
    log 'update tracked ClawHub skills: openclaw skills update --all'
    "${OPENCLAW_BIN[@]}" skills update --all || log 'warning: skills update --all failed'
  fi

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    skill="$(printf '%s' "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$skill" ] && continue
    case "$skill" in \#*) continue ;; esac

    marker_name="$(safe_marker_name "$skill")"
    marker="${MARKER_DIR}/${marker_name}.done"

    if [ -f "$marker" ]; then
      log "skip installed: $skill"
      continue
    fi

    log "install missing skill: $skill"
    if "${OPENCLAW_BIN[@]}" skills install "$skill"; then
      write_marker "$marker" "$skill"
      log "installed: $skill"
      log "warning: start a new OpenClaw session to ensure the skill is loaded: $skill"
    else
      rm -f "${marker}.tmp."* 2>/dev/null || true
      log "warning: install failed: $skill"
    fi
  done < "$ALLOWLIST_PATH"

  log 'sync done'
}

sync_once() {
  local lock="${LOCK_DIR}/skills-sync.lock"
  (
    flock -n 9 || {
      log 'another skills sync is running; skip'
      exit 0
    }
    sync_body
  ) 9>"$lock"
}

case "${1:-once}" in
  once)
    sync_once
    ;;
  daemon)
    log "daemon start, interval=${SYNC_INTERVAL_SECONDS}s"
    while true; do
      sync_once >> "${LOG_DIR}/skills-sync.log" 2>&1 || true
      sleep "$SYNC_INTERVAL_SECONDS"
    done
    ;;
  *)
    echo "usage: $0 [once|daemon]" >&2
    exit 2
    ;;
esac
