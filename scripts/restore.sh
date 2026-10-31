#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 1 && -f $1 ]] || fail 'Usage: bash scripts/restore.sh [--prod] /path/backup.tar.gz'
archive=$(realpath -- "$1")
python3 scripts/archive.py check "$archive"
printf 'Restore %s? Current data and .env will be kept in backups/.\nType RESTORE: ' "$archive"
read -r answer
[[ $answer == RESTORE ]] || fail 'Restore cancelled; no data changed.'
stop_cleanly
python3 scripts/archive.py restore "$ROOT" "$archive"
printf 'Server remains stopped. Review restored .env (IP/version/allowlist), then run deploy.sh.\n'
