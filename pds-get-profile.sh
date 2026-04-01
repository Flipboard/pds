#!/usr/bin/env bash
# Inspect app.bsky.actor.profile/self for one actor via store.sqlite.
#
# Runs two queries:
#   1) Healthy: record INNER JOIN repo_block (indexed row + leaf block present)
#   2) Dangling: record LEFT JOIN repo_block where block missing (busted index)
#
# Usage:
#   ./pds-get-profile.sh <DID> [ACTOR_STORE_ROOT]
#   PDS_DATA_DIRECTORY=/mnt/data/pds ./pds-get-profile.sh did:plc:...
#   VERBOSE=1 ./pds-get-profile.sh did:plc:... /path/to/actors
#
# Env (optional):
#   ACTOR_STORE_ROOT      Same as second argument (overrides env chain if set)
#   PDS_ACTOR_STORE_DIRECTORY
#   PDS_DATA_DIRECTORY    Used as ${PDS_DATA_DIRECTORY}/actors when set
#   PDS_ENV_FILE          If set, sourced: set -a; . "$PDS_ENV_FILE"; set +a
#   VERBOSE=1             Include hex(rb.content) for healthy profile rows
#
# Actor path matches PDS ActorStore.getLocation:
#   sha256(DID) hex -> first 2 chars / <DID> / store.sqlite

set -euo pipefail

# source pds.env variables
set -a
. /home/bluesky/pds.env
set +a

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: pds-get-profile.sh <DID> [ACTOR_STORE_ROOT]

Print profile/self from the actor store.sqlite: healthy join vs dangling rows.
EOF
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage
[[ -n "${1:-}" ]] || {
  echo "Usage: pds-get-profile.sh <DID> [ACTOR_STORE_ROOT]" >&2
  exit 1
}

DID="$1"
[[ "$DID" == did:* ]] || die "DID must start with did:"

ACTOR_ROOT_ARG="${2:-}"

if [[ -n "${PDS_ENV_FILE:-}" ]]; then
  [[ -f "$PDS_ENV_FILE" ]] || die "PDS_ENV_FILE not found: $PDS_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$PDS_ENV_FILE"
  set +a
fi

resolve_actor_root() {
  if [[ -n "${ACTOR_ROOT_ARG:-}" ]]; then
    printf '%s' "$ACTOR_ROOT_ARG"
  elif [[ -n "${ACTOR_STORE_ROOT:-}" ]]; then
    printf '%s' "$ACTOR_STORE_ROOT"
  elif [[ -n "${PDS_ACTOR_STORE_DIRECTORY:-}" ]]; then
    printf '%s' "$PDS_ACTOR_STORE_DIRECTORY"
  elif [[ -n "${PDS_DATA_DIRECTORY:-}" ]]; then
    printf '%s' "${PDS_DATA_DIRECTORY}/actors"
  else
    printf '%s' "./actors"
  fi
}

ACTOR_ROOT="$(resolve_actor_root)"
[[ -d "$ACTOR_ROOT" ]] || die "actor store directory not found: $ACTOR_ROOT"

command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not in PATH"

HASH="$(printf '%s' "$DID" | openssl dgst -sha256 | awk '{print $2}')"
SHARD="${HASH:0:2}"
DB="${ACTOR_ROOT}/${SHARD}/${DID}/store.sqlite"

[[ -f "$DB" ]] || die "store.sqlite not found: $DB"

VERBOSE="${VERBOSE:-0}"

echo "DID:     $DID"
echo "DB:      $DB"
echo ""

# --- Healthy: block bytes present (default: length only; VERBOSE=1: hex content)
echo "=== Profile with repo_block (healthy) ==="
if [[ "$VERBOSE" == "1" ]]; then
  sqlite3 -header -column "$DB" <<'SQL'
SELECT
  r.uri,
  r.cid,
  r.indexedAt,
  LENGTH(rb.content) AS content_bytes,
  hex(rb.content) AS content_hex
FROM record AS r
INNER JOIN repo_block AS rb ON rb.cid = r.cid
WHERE r.collection = 'app.bsky.actor.profile'
  AND r.rkey = 'self';
SQL
else
  sqlite3 -header -column "$DB" <<'SQL'
SELECT
  r.uri,
  r.cid,
  r.indexedAt,
  LENGTH(rb.content) AS content_bytes
FROM record AS r
INNER JOIN repo_block AS rb ON rb.cid = r.cid
WHERE r.collection = 'app.bsky.actor.profile'
  AND r.rkey = 'self';
SQL
fi

echo ""
echo "=== Profile index row without repo_block (dangling / busted) ==="
sqlite3 -header -column "$DB" <<'SQL'
SELECT r.uri, r.cid, r.indexedAt
FROM record AS r
LEFT JOIN repo_block AS rb ON rb.cid = r.cid
WHERE r.collection = 'app.bsky.actor.profile'
  AND r.rkey = 'self'
  AND rb.cid IS NULL;
SQL
