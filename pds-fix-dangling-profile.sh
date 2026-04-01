#!/usr/bin/env bash

# Run this script to fix a dangling profile/self record in the actor store.
# This needs to be run directly on the PDS instance.
#
# This script will:
# Remove busted profile index rows (record + record_blob) for app.bsky.actor.profile/self,
# then rebuild the actor repo MST from the record table.
#
# Usage:
#   ./fix-dangling-profile.sh did:plc:xxxxxxxxxxxxxx
#   ACTOR_STORE_ROOT=/mnt/data/pds/actors ./fix-dangling-profile.sh did:plc:...
#   PDS_ENV_FILE=/home/bluesky/pds.env ./fix-dangling-profile.sh did:plc:...
#   DRY_RUN=1 ./fix-dangling-profile.sh did:plc:...
#
# Env:
#   ACTOR_STORE_ROOT  (default: $PDS_ACTOR_STORE_DIRECTORY or $PDS_DATA_DIRECTORY/actors)
#   REBUILD_SCRIPT    (default: /home/bluesky/current/service/bluesky-run-rebuild.js)
#   PDS_ENV_FILE      sourced before rebuild if set
#   YES=1             skip confirmation
#   DRY_RUN=1         print only

set -euo pipefail

# source pds.env variables
set -a
. /home/bluesky/pds.env
set +a

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '1,25p' "$0"; exit 0; }
[[ -n "${1:-}" ]] || { echo "Usage: $0 <DID>"; exit 1; }

DID="$1"
[[ "$DID" == did:* ]] || die "DID must start with did:"

resolve_actor_root() {
  if [[ -n "${ACTOR_STORE_ROOT:-}" ]]; then
    printf '%s' "$ACTOR_STORE_ROOT"
  elif [[ -n "${PDS_ACTOR_STORE_DIRECTORY:-}" ]]; then
    printf '%s' "$PDS_ACTOR_STORE_DIRECTORY"
  elif [[ -n "${PDS_DATA_DIRECTORY:-}" ]]; then
    printf '%s' "${PDS_DATA_DIRECTORY}/actors"
  else
    die "Set ACTOR_STORE_ROOT, PDS_ACTOR_STORE_DIRECTORY, or PDS_DATA_DIRECTORY"
  fi
}

ACTOR_ROOT="$(resolve_actor_root)"
[[ -d "$ACTOR_ROOT" ]] || die "actor store root not found: $ACTOR_ROOT"

command -v openssl >/dev/null 2>&1 || die "openssl required"
HASH="$(printf '%s' "$DID" | openssl dgst -sha256 | awk '{print $2}')"
SHARD="${HASH:0:2}"
DB="${ACTOR_ROOT}/${SHARD}/${DID}/store.sqlite"

PROFILE_URI="at://${DID}/app.bsky.actor.profile/self"
REBUILD_SCRIPT="${REBUILD_SCRIPT:-/ebsa/bluesky/current/service/run-rebuild.js}"
DRY_RUN="${DRY_RUN:-0}"
YES="${YES:-0}"

[[ -f "$DB" ]] || die "store.sqlite not found: $DB"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "DRY_RUN DB=$DB"
  echo "DELETE FROM record WHERE uri='$PROFILE_URI';"
  echo "DELETE FROM record_blob WHERE recordUri='$PROFILE_URI';"
  echo "node $REBUILD_SCRIPT $DID"
  exit 0
fi

echo "Actor DB: $DB"
echo "Profile URI: $PROFILE_URI"
echo "Rebuild: node $REBUILD_SCRIPT $DID"
if [[ "$YES" != "1" ]]; then
  read -r -p "Proceed? [y/N] " ans || true
  [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]] || die "aborted"
fi

command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not in PATH"

sqlite3 "$DB" <<SQL
BEGIN IMMEDIATE;
DELETE FROM record WHERE uri = '${PROFILE_URI}';
DELETE FROM record_blob WHERE recordUri = '${PROFILE_URI}';
COMMIT;
SQL

echo "Deleted profile record + record_blob rows."

[[ -f "$REBUILD_SCRIPT" ]] || die "REBUILD_SCRIPT not found: $REBUILD_SCRIPT"
command -v node >/dev/null 2>&1 || die "node not in PATH"

if [[ -n "${PDS_ENV_FILE:-}" ]]; then
  [[ -f "$PDS_ENV_FILE" ]] || die "PDS_ENV_FILE not found: $PDS_ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  . "$PDS_ENV_FILE"
  set +a
fi

echo "Rebuilding the actor repo..."
node "$REBUILD_SCRIPT" "$DID"
echo "Done rebuilding the actor repo."
echo "--------------------------------"
echo "Rechecking the profile..."
exec "./pds-get-profile.sh" "$DID"
echo "--------------------------------"