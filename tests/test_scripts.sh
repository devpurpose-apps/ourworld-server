#!/usr/bin/env bash
# Lifecycle checks with a fake Docker CLI; never touches the real daemon/world.
set -Eeuo pipefail
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/data/worlds/world" "$fixture/backups"
cp -R "$project/scripts" "$fixture/scripts"
cp "$project/compose.yml" "$project/compose.prod.yml" "$fixture/"
cp "$project/.env.example" "$fixture/.env"
printf 'level-name=world\n' > "$fixture/data/server.properties"
printf 'original-world' > "$fixture/data/worlds/world/level.dat"
export MOCK_LOG="$fixture/docker.log" MOCK_STOPPED="$fixture/stopped"
export PATH="$fixture/bin:$PATH"
cat > "$fixture/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_LOG"
if [[ $1 == inspect ]]; then
  case "$3" in
    '{{.State.Status}}') if [[ -f $MOCK_STOPPED ]]; then echo exited; else echo running; fi ;;
    '{{.State.Running}}') if [[ -f $MOCK_STOPPED ]]; then echo false; else echo true; fi ;;
    '{{.State.ExitCode}}') echo "${MOCK_EXIT_CODE:-0}" ;;
    *) exit 1 ;;
  esac
else
  case " $* " in
    *' ps --all --quiet bedrock '*) echo fake-container ;;
    *' stop bedrock '*) touch "$MOCK_STOPPED" ;;
    *' start bedrock '*) rm -f "$MOCK_STOPPED" ;;
    *' pull bedrock '*) [[ ${MOCK_PULL_FAIL:-false} == false ]] ;;
    *' up -d '*) [[ ${MOCK_UP_FAIL:-false} == false ]]; rm -f "$MOCK_STOPPED" ;;
    *' config --quiet '*|*' version '*|*' info '*|*' ps '*) ;;
    *) echo "Unexpected Docker call: $*" >&2; exit 1 ;;
  esac
fi
MOCK
chmod +x "$fixture/bin/docker"
cd -- "$fixture"

bash scripts/backup.sh
archives=(backups/bedrock-*.tar.gz)
[[ ${#archives[@]} == 1 && -f ${archives[0]} && ! -f $MOCK_STOPPED ]]
archive=${archives[0]}
python3 scripts/archive.py check "$archive"
grep -q ' stop bedrock$' "$MOCK_LOG"
grep -q ' start bedrock$' "$MOCK_LOG"

# An initially stopped server remains stopped after a successful backup.
touch "$MOCK_STOPPED"
: > "$MOCK_LOG"
bash scripts/backup.sh --prod
! grep -q ' start bedrock$' "$MOCK_LOG"
grep -q 'compose.prod.yml' "$MOCK_LOG"
rm "$MOCK_STOPPED"

# Refusing restore never stops the server or changes the active world.
printf 'newer-world' > data/worlds/world/level.dat
: > "$MOCK_LOG"
if printf 'NO\n' | bash scripts/restore.sh "$archive"; then exit 1; fi
[[ $(<data/worlds/world/level.dat) == newer-world ]]
! grep -q ' stop bedrock$' "$MOCK_LOG"

# Confirmed restore preserves old data and leaves BDS stopped for config review.
printf 'RESTORE\n' | bash scripts/restore.sh "$archive"
[[ $(<data/worlds/world/level.dat) == original-world && -f $MOCK_STOPPED ]]
previous=(backups/pre-restore-*)
[[ $(<"${previous[0]}/data/worlds/world/level.dat") == newer-world ]]
rm "$MOCK_STOPPED"

# Failed archive creation still resumes the original running container.
rm data/worlds/world/level.dat
: > "$MOCK_LOG"
if bash scripts/backup.sh; then exit 1; fi
[[ ! -f $MOCK_STOPPED ]]
grep -q ' start bedrock$' "$MOCK_LOG"
[[ -z $(find backups -name '*.partial' -print) ]]
printf 'original-world' > data/worlds/world/level.dat

# A forced/unclean shutdown must never publish a snapshot.
before=$(find backups -name '*.tar.gz' | wc -l)
if MOCK_EXIT_CODE=137 bash scripts/backup.sh; then exit 1; fi
[[ $(find backups -name '*.tar.gz' | wc -l) == "$before" ]]

# Network failure while pulling must happen before stopping the running server.
: > "$MOCK_LOG"
if MOCK_PULL_FAIL=true bash scripts/deploy.sh; then exit 1; fi
! grep -q ' stop bedrock$' "$MOCK_LOG"

bash scripts/deploy.sh --prod
snapshots=(backups/pre-deploy-*.tar.gz)
[[ -f ${snapshots[0]} && ! -f $MOCK_STOPPED ]]

if MOCK_UP_FAIL=true bash scripts/deploy.sh --prod; then exit 1; fi
[[ -f $MOCK_STOPPED ]]

# Competing maintenance operations must be rejected by the shared lock.
if flock .maintenance.lock bash scripts/backup.sh; then exit 1; fi
printf 'Lifecycle checks passed.\n'
