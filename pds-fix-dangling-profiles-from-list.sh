#!/usr/bin/env bash
# Run pds-fix-dangling-profile.sh once per non-empty line in dangling-profile-dids.txt.
#
# Usage:
#   ./pds-fix-dangling-from-profile-from-list.sh
#   DANGLING_PROFILE_DIDS_FILE=/tmp/dids.txt ./pds-fix-dangling-from-profile-from-list.sh
#   FIX_DANGLING_PROFILES_SCRIPT=/path/to/pds-fix-dangling-profile.sh ./pds-fix-dangling-from-profile-list.sh
#
# If fix-dangling-profiles.sh expects the DID on stdin instead of $1, set:
#   FIX_READS_STDIN=1 ./run-fix-dangling-from-list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${DANGLING_PROFILE_DIDS_FILE:-$SCRIPT_DIR/dangling-profile-dids.txt}"
FIX="${FIX_DANGLING_PROFILE_SCRIPT:-$SCRIPT_DIR/pds-fix-dangling-profile.sh}"
FIX_READS_STDIN="${FIX_READS_STDIN:-0}"

if [[ ! -f "$LIST" ]]; then
  echo "ERROR: DID list not found: $LIST" >&2
  exit 1
fi

if [[ ! -f "$FIX" ]]; then
  echo "ERROR: fix script not found: $FIX" >&2
  exit 1
fi

run_fix() {
  local did="$1"
  if [[ "$FIX_READS_STDIN" == "1" ]]; then
    printf '%s\n' "$did" | bash "$FIX"
  else
    bash "$FIX" "$did"
  fi
}

while IFS= read -r did || [[ -n "${did:-}" ]]; do
  [[ -z "${did// }" ]] && continue
  [[ "$did" =~ ^[[:space:]]*# ]] && continue
  run_fix "$did"
done <"$LIST"
