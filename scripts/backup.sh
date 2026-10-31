#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 0 ]] || fail 'Usage: bash scripts/backup.sh [--prod]'
archive="$ROOT/backups/bedrock-$(date -u +%Y%m%dT%H%M%SZ)-$$.tar.gz"
resume() {
  local status=$?
  trap - EXIT
  if [[ $was_running == true ]]; then
    "${COMPOSE[@]}" start bedrock || status=1
  fi
  exit "$status"
}
trap resume EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stop_cleanly
python3 scripts/archive.py create "$ROOT" "$archive"
printf 'Backup: %s\n' "$archive"
