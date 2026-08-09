#!/usr/bin/env bash
# Disaster recovery rehearsal.
#
# Restores a real archive into a SCRATCH Supabase project, then proves the
# restore was faithful by comparing row counts and photo checksums against
# the archive - rather than glancing at the admin panel and assuming.
#
#   BACKUP_PASSPHRASE=... \
#   TARGET_URL=https://<scratch-ref>.supabase.co \
#   TARGET_SERVICE_KEY=<scratch service_role key> \
#   ./rehearse.sh glowbyrica-20260809T173000Z.tar.gz.gpg
#
# Never point this at the live project. It writes data.

set -euo pipefail
cd "$(dirname "$0")"
. ./lib-list.sh

ARCHIVE="${1:-}"
BUCKET="patient-photos"
TABLES="clients appointments consent_records client_photos consent_forms blocked_days"

[ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ] || { echo "Usage: $0 <archive.tar.gz.gpg>" >&2; exit 1; }
: "${BACKUP_PASSPHRASE:?}" "${TARGET_URL:?}" "${TARGET_SERVICE_KEY:?}"

case "$TARGET_URL" in
  *kychrharobhmyzuywvpm*)
    echo "REFUSING: that is the live project. Rehearse against a scratch one." >&2
    exit 1 ;;
esac

PASSES=0; FAILS=0
ok()  { echo "  PASS  $1"; PASSES=$((PASSES+1)); }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS+1)); }

tapi() { curl -sS -H "apikey: $TARGET_SERVICE_KEY" -H "Authorization: Bearer $TARGET_SERVICE_KEY" "$@"; }

# Exact row count from PostgREST's Content-Range header
target_count() {
  tapi -D - -o /dev/null "$TARGET_URL/rest/v1/$1?select=*" \
       -H "Prefer: count=exact" -H "Range: 0-0" 2>/dev/null \
    | grep -i '^content-range:' | sed 's|.*/||' | tr -d '\r\n' || echo "?"
}

echo "==> Restoring into scratch project"
RESTORE_CONFIRM=RESTORE ./restore.sh "$ARCHIVE" --restore

echo ""
echo "==> Comparing restored data against the archive"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --yes --quiet --passphrase-fd 0 \
  --pinentry-mode loopback -o "$WORK/a.tar.gz" -d "$ARCHIVE"
tar -xzf "$WORK/a.tar.gz" -C "$WORK"
STAGE="$(find "$WORK" -maxdepth 1 -type d -name 'glowbyrica-*' | head -1)"

for t in $TABLES; do
  f="$STAGE/tables/$t.json"
  [ -f "$f" ] || continue
  # every row in this schema carries created_at, so it is a safe row marker
  want="$(grep -o '"created_at"' "$f" | wc -l | tr -d ' ' || true)"
  got="$(target_count "$t")"
  if [ "$want" = "$got" ]; then ok "$t: $got row(s) match"; else bad "$t: archive has $want, target has $got"; fi
done

echo ""
echo "==> Comparing photos"
archive_photos="$(find "$STAGE/photos" -type f 2>/dev/null | wc -l | tr -d ' ')"

root_json="$(curl -sS -X POST "$TARGET_URL/storage/v1/object/list/$BUCKET" \
  -H "apikey: $TARGET_SERVICE_KEY" -H "Authorization: Bearer $TARGET_SERVICE_KEY" \
  -H "Content-Type: application/json" -d '{"prefix":"","limit":10000}')"
folders="$(printf '%s' "$root_json" | names_without_id)"

target_photos=0
MISMATCH=0
while IFS= read -r fdr; do
  [ -z "$fdr" ] && continue
  files="$(curl -sS -X POST "$TARGET_URL/storage/v1/object/list/$BUCKET" \
    -H "apikey: $TARGET_SERVICE_KEY" -H "Authorization: Bearer $TARGET_SERVICE_KEY" \
    -H "Content-Type: application/json" -d "{\"prefix\":\"$fdr/\",\"limit\":10000}" | names_with_id)"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    target_photos=$((target_photos+1))
    # byte-for-byte: does the restored image match the archived one?
    tapi "$TARGET_URL/storage/v1/object/$BUCKET/$fdr/$file" -o "$WORK/dl.bin" || true
    if [ -f "$STAGE/photos/$fdr/$file" ]; then
      a="$(openssl dgst -sha256 -r "$STAGE/photos/$fdr/$file" | cut -d' ' -f1)"
      b="$(openssl dgst -sha256 -r "$WORK/dl.bin" | cut -d' ' -f1)"
      [ "$a" = "$b" ] || { echo "    differs: $fdr/$file"; MISMATCH=$((MISMATCH+1)); }
    fi
  done <<< "$files"
done <<< "$folders"

if [ "$archive_photos" = "$target_photos" ]; then
  ok "photos: $target_photos restored, matching the archive"
else
  bad "photos: archive has $archive_photos, target has $target_photos"
fi
if [ "$MISMATCH" -eq 0 ]; then ok "every restored photo is byte-identical"; else bad "$MISMATCH photo(s) differ"; fi

echo ""
echo "$PASSES passed, $FAILS failed"
if [ "$FAILS" -eq 0 ]; then
  echo "Recovery rehearsed successfully on $(date -u +%Y-%m-%d). Record the date."
fi
[ "$FAILS" -eq 0 ]
