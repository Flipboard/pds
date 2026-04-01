#!/usr/bin/env bash
# Scan all actor store.sqlite files for dangling record rows (record.cid missing in repo_block).
# Optionally filter to busted app.bsky.actor.profile/self only.
# DIDs with a dangling profile/self record are appended to a file (reset each run).
#
# Usage:
#   ./scan-dangling-profiles.sh [ACTOR_STORE_ROOT]
#   ONLY_PROFILE=1 ./scan-dangling-profiles.sh /mnt/data/pds/actors
#   VERBOSE=1 ONLY_PROFILE=1 ./scan-dangling-profiles.sh
#   DANGLING_PROFILE_DIDS_FILE=/tmp/busted-dids.txt ./scan-dangling-profiles.sh
#
# Resolution order for ACTOR_STORE_ROOT:
#   $1 > $PDS_ACTOR_STORE_DIRECTORY > $PDS_DATA_DIRECTORY/actors > ./actors

set -euo pipefail

# source pds.env variables
set -a
. /home/bluesky/pds.env
set +a

resolve_actor_root() {
  if [[ -n "${1:-}" ]]; then
    printf '%s' "$1"
  elif [[ -n "${PDS_ACTOR_STORE_DIRECTORY:-}" ]]; then
    printf '%s' "$PDS_ACTOR_STORE_DIRECTORY"
  elif [[ -n "${PDS_DATA_DIRECTORY:-}" ]]; then
    printf '%s' "${PDS_DATA_DIRECTORY}/actors"
  else
    printf '%s' "./actors"
  fi
}

ACTOR_ROOT="$(resolve_actor_root "${1:-}")"

if [[ ! -d "$ACTOR_ROOT" ]]; then
  echo "ERROR: actor store directory not found: $ACTOR_ROOT" >&2
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "ERROR: sqlite3 not in PATH" >&2
  exit 1
fi

DANGLING_PROFILE_DIDS_FILE="${DANGLING_PROFILE_DIDS_FILE:-./dangling-profile-dids.txt}"
: >"$DANGLING_PROFILE_DIDS_FILE"

# total dangling: record row whose cid has no repo_block row
SQL_TOTAL='SELECT COUNT(*) FROM record AS r LEFT JOIN repo_block AS rb ON rb.cid = r.cid WHERE rb.cid IS NULL;'

# dangling specifically for profile/self
SQL_PROFILE='SELECT COUNT(*) FROM record AS r LEFT JOIN repo_block AS rb ON rb.cid = r.cid WHERE rb.cid IS NULL AND r.uri LIKE "%/app.bsky.actor.profile/self";'


# sample of dangling URIs (for debugging)
SQL_LIST='SELECT r.uri || " | " || r.cid FROM record AS r LEFT JOIN repo_block AS rb ON rb.cid = r.cid WHERE rb.cid IS NULL LIMIT 50;'

ONLY_PROFILE="${ONLY_PROFILE:-0}"
VERBOSE="${VERBOSE:-0}"

actors_any=0
actors_profile=0

while IFS= read -r -d '' db; do
  tot="$(sqlite3 "$db" "$SQL_TOTAL" 2>/dev/null)" || {
    echo "WARN: sqlite3 failed (skip): $db" >&2
    continue
  }

  if [[ -z "${tot:-}" ]] || [[ "$tot" -eq 0 ]]; then
    continue
  fi

  prof="$(sqlite3 "$db" "$SQL_PROFILE" 2>/dev/null)" || prof=0
  if [[ "${ONLY_PROFILE}" == "1" ]] && [[ "${prof:-0}" -eq 0 ]]; then
    continue
  fi

  rel="${db#"$ACTOR_ROOT"/}"
  echo "DANGLING  store=$rel"
  echo "  total_dangling_rows=$tot  profile_self_dangling=$prof"

  if [[ "${prof:-0}" -gt 0 ]]; then
    # PDS layout: ACTOR_ROOT/<shard>/<did>/store.sqlite
    did="$(basename "$(dirname "$rel")")"
    printf '%s\n' "$did" >>"$DANGLING_PROFILE_DIDS_FILE"
  fi

  if [[ "$VERBOSE" == "1" ]]; then
    sqlite3 "$db" "$SQL_LIST" 2>/dev/null | sed 's/^/  /' || true
    echo
  fi

  actors_any=$((actors_any + 1))
  if [[ "${prof:-0}" -gt 0 ]]; then
    actors_profile=$((actors_profile + 1))
  fi
done < <(find "$ACTOR_ROOT" -name store.sqlite -type f -print0)

echo "---"
echo "summary: actor_dbs_with_dangling=${actors_any}"
echo "summary: actor_dbs_with_busted_profile_self=${actors_profile}"
echo "scanned_root=${ACTOR_ROOT}"
echo "dangling_profile_dids_file=${DANGLING_PROFILE_DIDS_FILE}"