#!/usr/bin/env bash
# hook-profile-gate.sh — Runtime hook profile control
# Source this at the top of any hook to respect profile settings.
#
# Profiles:
#   minimal  — Only safety-critical hooks (blast-radius-check, pre-commit-gate)
#   standard — Balanced quality + safety (default)
#   strict   — All hooks + extra reminders
#
# Usage in a hook:
#   source "$(dirname "$0")/hook-profile-gate.sh" || exit 0
#   hook_profile_require "standard" || exit 0
#
# Environment:
#   HCF_HOOK_PROFILE=minimal|standard|strict  (default: standard)
#   HCF_DISABLED_HOOKS="pre:bash:rtk,post:edit:governance"  (comma-separated)

set -euo pipefail

HCF_HOOK_PROFILE="${HCF_HOOK_PROFILE:-standard}"

# Check if a specific hook is disabled by name
hcf_hook_is_disabled() {
  local hook_id="$1"
  local disabled="${HCF_DISABLED_HOOKS:-}"

  [[ -z "$disabled" ]] && return 1

  IFS=',' read -ra DISABLED_LIST <<< "$disabled"
  for d in "${DISABLED_LIST[@]}"; do
    d=$(echo "$d" | tr -d ' ')
    if [[ "$d" == "$hook_id" ]]; then
      return 0  # Hook is disabled
    fi
  done
  return 1  # Not disabled
}

# Check if the current profile allows this hook tier
# Tiers: safety (always), standard (standard+strict), strict (strict only)
hook_profile_require() {
  local required_tier="$1"

  case "$required_tier" in
    safety)
      # Always runs regardless of profile
      return 0
      ;;
    standard)
      case "$HCF_HOOK_PROFILE" in
        standard|strict) return 0 ;;
        minimal) return 1 ;;
        *) return 0 ;;  # Default to standard
      esac
      ;;
    strict)
      case "$HCF_HOOK_PROFILE" in
        strict) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 0  # Unknown tier, allow
      ;;
  esac
}
