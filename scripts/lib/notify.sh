#!/bin/bash
# notify.sh — Notification dispatch for HCF scripts
# Source this file: . scripts/lib/notify.sh
#
# Supports: Slack, Discord, generic webhooks
# Configure via environment variables:
#   SLACK_WEBHOOK_URL        — Slack incoming webhook URL
#   DISCORD_WEBHOOK_URL      — Discord webhook URL
#   NOTIFICATION_WEBHOOK_URL — Generic webhook (receives JSON POST)
#   NOTIFY_ENABLED           — Set to "false" to disable (default: auto-detect)

# ─── Auto-fetch webhook URLs from Hartz Command API ──────────────────────

notify_fetch_command_settings() {
  # Only fetch once per session
  [[ "${_NOTIFY_SETTINGS_FETCHED:-}" == "true" ]] && return 0

  local command_url="${HARTZ_COMMAND_URL:-http://localhost:3001}"
  local auth_header=""
  if [[ -n "${HARTZ_AUTH_TOKEN:-}" ]]; then
    auth_header="-H \"Authorization: Bearer ${HARTZ_AUTH_TOKEN}\""
  fi

  local settings
  settings=$(eval curl -s --connect-timeout 2 --max-time 5 \
    "$auth_header" \
    "${command_url}/api/settings" 2>/dev/null) || { _NOTIFY_SETTINGS_FETCHED=true; return 1; }

  # Extract webhook URLs if not already set via env vars
  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
    SLACK_WEBHOOK_URL=$(echo "$settings" | node -e "process.stdin.on('data',d=>{try{const s=JSON.parse(d);console.log(s.data?.slack_webhook_url||'')}catch{console.log('')}})" 2>/dev/null || echo "")
    export SLACK_WEBHOOK_URL
  fi

  _NOTIFY_SETTINGS_FETCHED=true
}

# Attempt to fetch settings from Command on first load
notify_fetch_command_settings 2>/dev/null || true

# ─── Helpers ────────────────────────────────────────────────────────────────

notify_is_enabled() {
  if [[ "${NOTIFY_ENABLED:-}" == "false" ]]; then
    return 1
  fi
  # Auto-detect: enabled if any webhook URL is set
  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]] || [[ -n "${DISCORD_WEBHOOK_URL:-}" ]] || [[ -n "${NOTIFICATION_WEBHOOK_URL:-}" ]]; then
    return 0
  fi
  return 1
}

notify_sanitize() {
  # Strip home directory paths and sensitive info from messages
  local msg="$1"
  echo "$msg" | sed "s|$HOME|~|g" | sed 's|/c/Users/[^/]*/|~/|g'
}

notify_severity_color() {
  # Returns color hex for severity level
  case "${1:-info}" in
    info)     echo "#36a64f" ;;  # green
    warning)  echo "#ff9900" ;;  # orange
    critical) echo "#cc0000" ;;  # red
  esac
}

notify_severity_emoji() {
  case "${1:-info}" in
    info)     echo "white_check_mark" ;;
    warning)  echo "warning" ;;
    critical) echo "rotating_light" ;;
  esac
}

# ─── Slack ──────────────────────────────────────────────────────────────────

notify_slack() {
  local title="$1"
  local message="$2"
  local severity="${3:-info}"

  [[ -z "${SLACK_WEBHOOK_URL:-}" ]] && return 0

  local color
  color=$(notify_severity_color "$severity")
  local emoji
  emoji=$(notify_severity_emoji "$severity")
  local project
  project=$(basename "$(pwd)")
  local safe_message
  safe_message=$(notify_sanitize "$message")

  local payload
  payload=$(node -e "
    process.stdout.write(JSON.stringify({
      attachments: [{
        color: '$color',
        blocks: [
          {
            type: 'header',
            text: { type: 'plain_text', text: ':${emoji}: ${title}', emoji: true }
          },
          {
            type: 'section',
            text: { type: 'mrkdwn', text: process.argv[1] }
          },
          {
            type: 'context',
            elements: [
              { type: 'mrkdwn', text: 'Project: *${project}* | ' + new Date().toLocaleString() }
            ]
          }
        ]
      }]
    }));
  " "$safe_message" 2>/dev/null || echo "{\"text\":\"${title}: ${safe_message}\"}")

  curl -s -X POST -H "Content-Type: application/json" \
    --max-time 10 \
    -d "$payload" \
    "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
}

# ─── Discord ────────────────────────────────────────────────────────────────

notify_discord() {
  local title="$1"
  local message="$2"
  local severity="${3:-info}"

  [[ -z "${DISCORD_WEBHOOK_URL:-}" ]] && return 0

  local color_hex
  color_hex=$(notify_severity_color "$severity")
  # Discord needs decimal color, not hex
  local color_dec
  color_dec=$(node -e "console.log(parseInt('${color_hex}'.replace('#',''), 16))" 2>/dev/null || echo "3066993")
  local project
  project=$(basename "$(pwd)")
  local safe_message
  safe_message=$(notify_sanitize "$message")

  local payload
  payload=$(node -e "
    process.stdout.write(JSON.stringify({
      embeds: [{
        title: process.argv[1],
        description: process.argv[2],
        color: ${color_dec},
        footer: { text: 'HCF | ${project}' },
        timestamp: new Date().toISOString()
      }]
    }));
  " "$title" "$safe_message" 2>/dev/null || echo "{\"content\":\"${title}: ${safe_message}\"}")

  curl -s -X POST -H "Content-Type: application/json" \
    --max-time 10 \
    -d "$payload" \
    "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1 || true
}

# ─── Generic Webhook ────────────────────────────────────────────────────────

notify_generic_webhook() {
  local event_type="$1"
  local title="$2"
  local message="$3"
  local severity="${4:-info}"

  [[ -z "${NOTIFICATION_WEBHOOK_URL:-}" ]] && return 0

  local project
  project=$(basename "$(pwd)")
  local safe_message
  safe_message=$(notify_sanitize "$message")

  local payload
  payload=$(node -e "
    process.stdout.write(JSON.stringify({
      event: process.argv[1],
      title: process.argv[2],
      message: process.argv[3],
      severity: '$severity',
      project: '$project',
      timestamp: new Date().toISOString()
    }));
  " "$event_type" "$title" "$safe_message" 2>/dev/null || echo "{}")

  curl -s -X POST -H "Content-Type: application/json" \
    --max-time 10 \
    -d "$payload" \
    "$NOTIFICATION_WEBHOOK_URL" > /dev/null 2>&1 || true
}

# ─── Dispatcher ─────────────────────────────────────────────────────────────

notify_send() {
  # Usage: notify_send <event_type> <title> <message> [<severity>]
  # severity: info | warning | critical (default: info)
  # Dispatches to all configured channels. Never blocks.
  local event_type="$1"
  local title="$2"
  local message="$3"
  local severity="${4:-info}"

  notify_is_enabled || return 0

  notify_slack "$title" "$message" "$severity"
  notify_discord "$title" "$message" "$severity"
  notify_generic_webhook "$event_type" "$title" "$message" "$severity"
}
