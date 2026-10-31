#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$ROOT"
COMPOSE=(docker compose --project-directory "$ROOT" --env-file "$ROOT/.env" -f "$ROOT/compose.yml")
if [[ ${1:-} == --prod ]]; then
  COMPOSE+=(-f "$ROOT/compose.prod.yml")
  shift
fi
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
for tool in docker python3 flock; do
  command -v "$tool" >/dev/null || fail "Missing command: $tool"
done
[[ -f .env && ! -L .env ]] || fail 'Create a regular .env file from .env.example first.'
[[ -d data && ! -L data && -d backups && ! -L backups ]] || fail 'data/ and backups/ must be real directories.'
# All maintenance scripts serialize; do not start/stop Compose manually during them.
exec 9> .maintenance.lock
flock -n 9 || fail 'Another maintenance operation is running.'
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" version >/dev/null
docker info >/dev/null

container_id() { "${COMPOSE[@]}" ps --all --quiet bedrock; }
was_running=false
stop_cleanly() {
  local id state
  id=$(container_id)
  [[ -n $id ]] || return 0
  state=$(docker inspect --format '{{.State.Status}}' "$id")
  case "$state" in
    running) was_running=true; "${COMPOSE[@]}" stop bedrock ;;
    exited|created) ;;
    *) fail "Container is $state; resolve this before maintenance." ;;
  esac
  [[ $(docker inspect --format '{{.State.Running}}' "$id") == false ]] || fail 'Container is still running.'
  [[ $(docker inspect --format '{{.State.ExitCode}}' "$id") == 0 ]] || fail 'Unclean server exit; backup/restore refused. Inspect logs first.'
}
