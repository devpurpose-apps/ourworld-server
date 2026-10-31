#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 0 ]] || fail 'Usage: bash scripts/deploy.sh [--prod]'
# Pull before downtime; world changes/upgrades always get a cold snapshot first.
"${COMPOSE[@]}" pull bedrock
was_running=false
recover() {
  local status=$?
  trap - EXIT
  if [[ $status != 0 && $was_running == true ]]; then
    printf 'Deployment failed. Server left stopped; inspect logs/backups before starting.\n' >&2
  fi
  exit "$status"
}
trap recover EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
stop_cleanly
if [[ -f data/server.properties ]]; then
  python3 scripts/archive.py create "$ROOT" "$ROOT/backups/pre-deploy-$(date -u +%Y%m%dT%H%M%SZ)-$$.tar.gz"
fi
"${COMPOSE[@]}" up -d --wait --wait-timeout 600 bedrock
"${COMPOSE[@]}" ps
