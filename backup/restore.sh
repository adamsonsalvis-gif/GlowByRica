#!/usr/bin/env bash
# Glow By Rica - restore from an encrypted backup.
#
# Usage:
#   ./restore.sh <archive.tar.gz.gpg> --verify           # decrypt + checksum only
#   ./restore.sh <archive.tar.gz.gpg> --dry-run          # show what would be written
#   ./restore.sh <archive.tar.gz.gpg> --restore          # actually write to TARGET
#
# Required environment:
#   BACKUP_PASSPHRASE     passphrase used at backup time
# Required for --restore (deliberately separate vars, so a restore cannot
# be aimed at production by leaving the backup vars set):
#   TARGET_URL            https://<ref>.supabase.co to restore INTO
#   TARGET_SERVICE_KEY    service_role key for that project
#
# Restore rehearsals should point at a scratch project, not the live one.

set -euo pipefail

ARCHIVE="${1:-}"
MODE="${2:---verify}"
BUCKET="patient-photos"
# clients before dependants; admin_users is environment-specific, skipped
TABLES="clients appointments consent_records client_photos consent_forms blocked_days"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "Usage: $0 <archive.tar.gz.gpg> [--verify|--dry-run|--restore]" >&2
  exit 1
fi
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE not set}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Decrypting"
printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --yes --quiet \
  --passphrase-fd 0 --pinentry-mode loopback \
  -o "$WORK/archive.tar.gz" -d "$ARCHIVE"

tar -xzf "$WORK/archive.tar.gz" -C "$WORK"
STAGE="$(find "$WORK" -maxdepth 1 -type d -name 'glowbyrica-*' | head -1)"
[ -d "$STAGE" ] || { echo "No backup directory inside archive" >&2; exit 1; }
echo "    $(basename "$STAGE")"

echo "==> Verifying checksums"
FAIL=0
CHECKED=0
while read -r sum file; do
  [ -z "${file:-}" ] && continue
  if [ ! -f "$STAGE/$file" ]; then
    echo "    MISSING: $file"; FAIL=$((FAIL+1)); continue
  fi
  actual="$(openssl dgst -sha256 -r "$STAGE/$file" | cut -d' ' -f1)"
  CHECKED=$((CHECKED+1))
  if [ "$actual" != "$sum" ]; then
    echo "    CORRUPT: $file"; FAIL=$((FAIL+1))
  fi
done < <(sed -n '/^sha256:/,$p' "$STAGE/MANIFEST.txt" | tail -n +2 | sed 's/^  //')

echo "    $CHECKED file(s) checked, $FAIL problem(s)"
[ "$FAIL" -eq 0 ] || { echo "Backup is NOT intact - stopping." >&2; exit 1; }

for t in $TABLES; do
  f="$STAGE/tables/$t.json"
  [ -f "$f" ] || continue
  # || true: grep exits 1 on an empty table, which set -e would treat as fatal
  n="$(grep -o '"id"' "$f" | wc -l | tr -d ' ' || true)"
  echo "    $t: ~$n row(s)"
done
PHOTOS=$(find "$STAGE/photos" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "    photos: $PHOTOS file(s)"

if [ "$MODE" = "--verify" ]; then
  echo "Backup verified intact. (Use --restore to write it somewhere.)"
  exit 0
fi

if [ "$MODE" = "--dry-run" ]; then
  echo "==> Dry run, nothing written"
  exit 0
fi

[ "$MODE" = "--restore" ] || { echo "Unknown mode $MODE" >&2; exit 1; }
: "${TARGET_URL:?TARGET_URL not set}"
: "${TARGET_SERVICE_KEY:?TARGET_SERVICE_KEY not set}"

echo ""
echo "About to restore into: $TARGET_URL"
printf "Type RESTORE to continue: "
read -r confirm
[ "$confirm" = "RESTORE" ] || { echo "Aborted."; exit 1; }

tapi() { curl -fsS -H "apikey: $TARGET_SERVICE_KEY" -H "Authorization: Bearer $TARGET_SERVICE_KEY" "$@"; }

echo "==> Restoring tables"
for t in $TABLES; do
  f="$STAGE/tables/$t.json"
  [ -f "$f" ] || continue
  if [ "$(tr -d '[:space:]' < "$f")" = "[]" ]; then echo "    $t: empty, skipped"; continue; fi
  # merge-duplicates so re-running a restore is safe
  tapi -X POST "$TARGET_URL/rest/v1/$t" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=minimal" \
    --data-binary "@$f" > /dev/null
  echo "    $t restored"
done

echo "==> Restoring photos"
count=0
while IFS= read -r f; do
  rel="${f#$STAGE/photos/}"
  tapi -X POST "$TARGET_URL/storage/v1/object/$BUCKET/$rel" \
    -H "Content-Type: image/jpeg" \
    -H "x-upsert: true" \
    --data-binary "@$f" > /dev/null
  count=$((count+1))
done < <(find "$STAGE/photos" -type f)
echo "    $count photo(s) restored"

echo "Restore complete. Check the admin panel."
