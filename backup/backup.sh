#!/usr/bin/env bash
# Glow By Rica - encrypted backup of clinical records.
#
# Exports every table and every patient photo, records checksums, then
# produces a single GPG-encrypted archive. Nothing unencrypted is ever
# uploaded anywhere.
#
# Required environment:
#   SUPABASE_URL          https://<ref>.supabase.co
#   SUPABASE_SERVICE_KEY  service_role key (bypasses RLS - keep secret)
#   BACKUP_PASSPHRASE     passphrase the archive is encrypted with
# Optional:
#   BACKUP_OUT            output directory (default ./backups)
#   RCLONE_REMOTE         e.g. gdrive:GlowByRicaBackups - upload if set
#   RETAIN_DAYS           delete remote backups older than this (default 90)
#
# Deliberately limited to curl/openssl/gpg/tar so it runs unchanged on
# Windows (Git Bash) and on a Linux CI runner.

set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL not set}"
: "${SUPABASE_SERVICE_KEY:?SUPABASE_SERVICE_KEY not set}"
: "${BACKUP_PASSPHRASE:?BACKUP_PASSPHRASE not set}"

BUCKET="patient-photos"
TABLES="clients appointments consent_records client_photos consent_forms blocked_days admin_users"
PAGE=1000
OUT_DIR="${BACKUP_OUT:-./backups}"
RETAIN_DAYS="${RETAIN_DAYS:-90}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NAME="glowbyrica-$STAMP"
WORK="$(mktemp -d)"
STAGE="$WORK/$NAME"
mkdir -p "$STAGE/tables" "$STAGE/photos" "$OUT_DIR"
trap 'rm -rf "$WORK"' EXIT

api() { curl -fsS -H "apikey: $SUPABASE_SERVICE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" "$@"; }

# Fetch and report the HTTP status, so failures say what actually happened
# instead of just exiting 1.
api_status() {
  curl -sS -o "$2" -w '%{http_code}' \
    -H "apikey: $SUPABASE_SERVICE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" "$1"
}

SKIPPED=""

# The anon key is NOT rejected by the API: row level security simply filters
# every row and returns 200 with []. A backup run with it would look like a
# success and contain nothing. admin_users always holds at least Rica's
# account, so an empty result there means the key is not service_role.
assert_service_role() {
  local f="$WORK/rolecheck.json"
  local c
  c="$(api_status "$SUPABASE_URL/rest/v1/admin_users?select=user_id&limit=1" "$f")"
  if [ "$c" = "404" ]; then
    echo "WARNING: admin_users missing, cannot confirm the key is service_role." >&2
    echo "         Run supabase/security-hardening.sql." >&2
    return 0
  fi
  if [ "$c" != "200" ]; then
    echo "ERROR: could not check key privileges (HTTP $c)" >&2
    exit 1
  fi
  if [ "$(tr -d '[:space:]' < "$f")" = "[]" ]; then
    echo "ERROR: this key cannot see any data - row level security is filtering" >&2
    echo "       everything, which means it is the anon key, not service_role." >&2
    echo "       Backing up now would produce an empty archive. Fix" >&2
    echo "       SUPABASE_SERVICE_KEY (Supabase, Settings, API, service_role)." >&2
    exit 1
  fi
}

echo "==> Checking credentials"
probe="$WORK/probe.json"
code="$(api_status "$SUPABASE_URL/rest/v1/clients?select=id&limit=1" "$probe")"
case "$code" in
  200) : ;;
  401|403)
    echo "ERROR: Supabase rejected the key (HTTP $code)." >&2
    echo "       SUPABASE_SERVICE_KEY must be the service_role key, not anon." >&2
    exit 1 ;;
  404)
    echo "ERROR: table 'clients' not found (HTTP 404). Is SUPABASE_URL correct?" >&2
    exit 1 ;;
  *)
    echo "ERROR: unexpected response (HTTP $code) from $SUPABASE_URL" >&2
    head -c 300 "$probe" >&2; echo >&2
    exit 1 ;;
esac
assert_service_role
echo "    service_role key confirmed"

echo "==> Exporting tables"
for t in $TABLES; do
  # A table that does not exist is not fatal: consent_forms is legacy and
  # client_photos only exists once client-photos.sql has been run.
  code="$(api_status "$SUPABASE_URL/rest/v1/$t?select=*&limit=1" "$WORK/check.json")"
  if [ "$code" = "404" ]; then
    echo "    $t: not present, skipped"
    SKIPPED="$SKIPPED $t"
    continue
  elif [ "$code" != "200" ]; then
    echo "ERROR: $t returned HTTP $code" >&2
    head -c 300 "$WORK/check.json" >&2; echo >&2
    exit 1
  fi

  offset=0
  : > "$STAGE/tables/$t.json"
  printf '[' >> "$STAGE/tables/$t.json"
  first=1
  while : ; do
    page="$WORK/page.json"
    api "$SUPABASE_URL/rest/v1/$t?select=*&limit=$PAGE&offset=$offset&order=id" -o "$page" 2>/dev/null \
      || api "$SUPABASE_URL/rest/v1/$t?select=*&limit=$PAGE&offset=$offset" -o "$page"

    # strip the outer [ ] so pages can be concatenated into one array
    body="$(sed -e 's/^\[//' -e 's/\]$//' "$page")"
    if [ -z "$body" ]; then break; fi

    if [ $first -eq 1 ]; then first=0; else printf ',' >> "$STAGE/tables/$t.json"; fi
    printf '%s' "$body" >> "$STAGE/tables/$t.json"

    # a short page means we reached the end
    rows="$(grep -o '"id"' "$page" | wc -l || true)"
    if [ "$rows" -lt "$PAGE" ]; then break; fi
    offset=$((offset + PAGE))
  done
  printf ']' >> "$STAGE/tables/$t.json"
  bytes=$(wc -c < "$STAGE/tables/$t.json")
  echo "    $t ($bytes bytes)"
done

echo "==> Listing photos"
list_folder() {
  # $1 = prefix ("" for root)
  curl -sS -X POST "$SUPABASE_URL/storage/v1/object/list/$BUCKET" \
      -H "apikey: $SUPABASE_SERVICE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"prefix\":\"$1\",\"limit\":10000,\"sortBy\":{\"column\":\"name\",\"order\":\"asc\"}}"
}

# Objects are stored as <client-slug>/<file>. Folder entries come back with
# a null id, so anything with an id is a real file.
PHOTO_LIST="$WORK/photos.txt"
: > "$PHOTO_LIST"
root_json="$(list_folder "")"

# The bucket only exists once client-photos.sql has been run
if printf '%s' "$root_json" | grep -q '"error"\|"statusCode"'; then
  echo "    bucket '$BUCKET' not reachable, skipping photos:"
  echo "    $(printf '%s' "$root_json" | head -c 200)"
  root_json='[]'
  SKIPPED="$SKIPPED $BUCKET"
fi
folders="$(printf '%s' "$root_json" | grep -o '{"name":"[^"]*","id":null' | sed 's/{"name":"//; s/","id":null//' || true)"

for f in $folders; do
  files_json="$(list_folder "$f/")"
  printf '%s' "$files_json" \
    | grep -o '{"name":"[^"]*","id":"[^"]*"' \
    | sed 's/{"name":"//; s/","id":".*//' \
    | while read -r file; do
        [ -n "$file" ] && echo "$f/$file" >> "$PHOTO_LIST"
      done
done

# Files sitting at the root, if any
printf '%s' "$root_json" | grep -o '{"name":"[^"]*","id":"[^"]*"' \
  | sed 's/{"name":"//; s/","id":".*//' \
  | while read -r file; do [ -n "$file" ] && echo "$file" >> "$PHOTO_LIST"; done

PHOTO_COUNT=$(wc -l < "$PHOTO_LIST" | tr -d ' ')
echo "    $PHOTO_COUNT photo(s)"

echo "==> Downloading photos"
while read -r p; do
  [ -z "$p" ] && continue
  mkdir -p "$STAGE/photos/$(dirname "$p")"
  api "$SUPABASE_URL/storage/v1/object/$BUCKET/$p" -o "$STAGE/photos/$p"
done < "$PHOTO_LIST"

echo "==> Writing manifest"
{
  echo "backup: $NAME"
  echo "taken_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "source: $SUPABASE_URL"
  echo "bucket: $BUCKET"
  echo "photo_count: $PHOTO_COUNT"
  echo "skipped:${SKIPPED:- none}"
  echo "schema_note: table structure and RLS policies live in supabase/*.sql in the site repo"
  echo ""
  echo "sha256:"
} > "$STAGE/MANIFEST.txt"

( cd "$STAGE" && find tables photos -type f | sort | while read -r f; do
    echo "  $(openssl dgst -sha256 -r "$f" | cut -d' ' -f1)  $f"
  done ) >> "$STAGE/MANIFEST.txt"

echo "==> Packing and encrypting"
ARCHIVE="$OUT_DIR/$NAME.tar.gz.gpg"
tar -czf "$WORK/$NAME.tar.gz" -C "$WORK" "$NAME"

printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --yes --quiet \
  --passphrase-fd 0 --pinentry-mode loopback \
  --symmetric --cipher-algo AES256 \
  -o "$ARCHIVE" "$WORK/$NAME.tar.gz"

SIZE=$(wc -c < "$ARCHIVE" | tr -d ' ')
echo "    $ARCHIVE ($SIZE bytes)"

if [ -n "${RCLONE_REMOTE:-}" ]; then
  echo "==> Uploading to $RCLONE_REMOTE"
  rclone copy "$ARCHIVE" "$RCLONE_REMOTE" --no-traverse
  echo "==> Pruning backups older than $RETAIN_DAYS days"
  rclone delete "$RCLONE_REMOTE" --min-age "${RETAIN_DAYS}d" || true
  # B2 keeps hidden previous versions, so a delete alone does not free the
  # space. cleanup purges them; it is a harmless no-op on backends that do
  # not version.
  rclone cleanup "$RCLONE_REMOTE" 2>/dev/null || true
else
  echo "==> RCLONE_REMOTE not set, keeping archive locally only"
fi

echo "Done."
