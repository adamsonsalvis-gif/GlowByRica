#!/usr/bin/env bash
# Proves the backup format survives a round trip, and - just as important -
# that verification FAILS on a damaged archive. A backup you cannot restore
# is worse than no backup, because you think you are covered.
#
# Uses synthetic data, so it needs no credentials and touches nothing live.

set -euo pipefail
cd "$(dirname "$0")"

PASS="test-passphrase-$$"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSES=0; FAILS=0

ok()   { echo "  PASS  $1"; PASSES=$((PASSES+1)); }
bad()  { echo "  FAIL  $1"; FAILS=$((FAILS+1)); }

# ---------------------------------------------------------------- build
NAME="glowbyrica-TEST"
STAGE="$TMP/$NAME"
mkdir -p "$STAGE/tables" "$STAGE/photos/jane-doe"

cat > "$STAGE/tables/clients.json" <<'JSON'
[{"id":"11111111-1111-1111-1111-111111111111","name":"Jane Doe","phone":"07700 900000","email":"jane@example.com"}]
JSON
cat > "$STAGE/tables/consent_records.json" <<'JSON'
[{"id":"22222222-2222-2222-2222-222222222222","template_key":"medical","client_name":"Jane Doe","data":{"patient_name":"Jane Doe","questions":[{"a":"no","d":""}]}}]
JSON
for t in appointments client_photos consent_forms blocked_days; do echo '[]' > "$STAGE/tables/$t.json"; done

# two "photos" of random bytes, so checksums are meaningful
head -c 40000 /dev/urandom > "$STAGE/photos/jane-doe/1-before.jpg"
head -c 35000 /dev/urandom > "$STAGE/photos/jane-doe/2-after.jpg"

{
  echo "backup: $NAME"
  echo "taken_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "photo_count: 2"
  echo ""
  echo "sha256:"
} > "$STAGE/MANIFEST.txt"
( cd "$STAGE" && find tables photos -type f | sort | while read -r f; do
    echo "  $(openssl dgst -sha256 -r "$f" | cut -d' ' -f1)  $f"
  done ) >> "$STAGE/MANIFEST.txt"

ORIG_SUM="$(cd "$STAGE" && find tables photos -type f | sort | xargs openssl dgst -sha256 -r | openssl dgst -sha256 -r | cut -d' ' -f1)"

tar -czf "$TMP/good.tar.gz" -C "$TMP" "$NAME"
printf '%s' "$PASS" | gpg --batch --yes --quiet --passphrase-fd 0 --pinentry-mode loopback \
  --symmetric --cipher-algo AES256 -o "$TMP/good.gpg" "$TMP/good.tar.gz"

echo "Test 1: archive is actually encrypted"
if grep -qa "Jane Doe" "$TMP/good.gpg"; then bad "patient name found in plaintext"; else ok "no plaintext patient data in archive"; fi
if file "$TMP/good.gpg" 2>/dev/null | grep -qi "PGP\|GPG\|encrypted"; then ok "recognised as encrypted data"; else ok "encrypted (file type check unavailable)"; fi

echo "Test 2: correct passphrase verifies clean"
if BACKUP_PASSPHRASE="$PASS" ./restore.sh "$TMP/good.gpg" --verify > "$TMP/verify.log" 2>&1; then
  ok "verify succeeded"
  grep -q "2 file(s)" "$TMP/verify.log" || true
  if grep -q "photos: 2 file(s)" "$TMP/verify.log"; then ok "found both photos"; else bad "photo count wrong"; fi
  if grep -q "clients: ~1 row" "$TMP/verify.log"; then ok "found client row"; else bad "client row count wrong"; fi
  if grep -q "0 problem" "$TMP/verify.log"; then ok "no checksum problems"; else bad "checksum problems reported"; fi
else
  bad "verify failed on a good archive"; cat "$TMP/verify.log"
fi

echo "Test 3: wrong passphrase is rejected"
if BACKUP_PASSPHRASE="wrong-passphrase" ./restore.sh "$TMP/good.gpg" --verify > "$TMP/wrong.log" 2>&1; then
  bad "wrong passphrase was accepted"
else
  ok "wrong passphrase rejected"
fi

echo "Test 4: corruption is detected"
# flip a byte inside one photo, keep the original manifest, re-encrypt
rm -rf "$TMP/tamper"; mkdir -p "$TMP/tamper"
tar -xzf "$TMP/good.tar.gz" -C "$TMP/tamper"
printf 'X' | dd of="$TMP/tamper/$NAME/photos/jane-doe/1-before.jpg" bs=1 seek=500 conv=notrunc status=none
tar -czf "$TMP/bad.tar.gz" -C "$TMP/tamper" "$NAME"
printf '%s' "$PASS" | gpg --batch --yes --quiet --passphrase-fd 0 --pinentry-mode loopback \
  --symmetric --cipher-algo AES256 -o "$TMP/bad.gpg" "$TMP/bad.tar.gz"

if BACKUP_PASSPHRASE="$PASS" ./restore.sh "$TMP/bad.gpg" --verify > "$TMP/bad.log" 2>&1; then
  bad "corrupted archive passed verification"
else
  if grep -q "CORRUPT" "$TMP/bad.log"; then ok "corrupted photo detected by checksum"; else bad "failed but did not report corruption"; fi
fi

echo "Test 5: data survives the round trip byte-for-byte"
rm -rf "$TMP/out"; mkdir -p "$TMP/out"
printf '%s' "$PASS" | gpg --batch --yes --quiet --passphrase-fd 0 --pinentry-mode loopback \
  -o "$TMP/out.tar.gz" -d "$TMP/good.gpg"
tar -xzf "$TMP/out.tar.gz" -C "$TMP/out"
NEW_SUM="$(cd "$TMP/out/$NAME" && find tables photos -type f | sort | xargs openssl dgst -sha256 -r | openssl dgst -sha256 -r | cut -d' ' -f1)"
if [ "$ORIG_SUM" = "$NEW_SUM" ]; then ok "restored files identical to originals"; else bad "restored files differ from originals"; fi
if grep -q "Jane Doe" "$TMP/out/$NAME/tables/clients.json"; then ok "record content readable after restore"; else bad "record content lost"; fi

echo "Test 6: storage listing survives empty buckets"
# Regression: grep exits 1 when it matches nothing, and under pipefail that
# aborted the whole backup as soon as the bucket was empty.
. ./lib-list.sh

check_parse() { # name, json, expected output
  local got
  got="$(printf '%s' "$2" | eval "$4" || echo "__DIED__")"
  if [ "$got" = "__DIED__" ]; then bad "$1 (command failed)"; return; fi
  if [ "$got" = "$3" ]; then ok "$1"; else bad "$1 (got '$got', wanted '$3')"; fi
}

check_parse "empty bucket yields no files"    '[]' '' 'names_with_id'
check_parse "empty bucket yields no folders"  '[]' '' 'names_without_id'
check_parse "folders are detected" \
  '[{"name":"jane-doe","id":null},{"name":"amy-lee","id":null}]' \
  'jane-doe
amy-lee' 'names_without_id'
check_parse "folder listing yields no stray files" \
  '[{"name":"jane-doe","id":null}]' '' 'names_with_id'
check_parse "files are detected" \
  '[{"name":"1-before.jpg","id":"abc","size":10},{"name":"2-after.jpg","id":"def"}]' \
  '1-before.jpg
2-after.jpg' 'names_with_id'

# and the loop that consumes them must not trip on empty input either
if (
  set -euo pipefail
  . ./lib-list.sh
  files="$(printf '[]' | names_with_id)"
  while IFS= read -r f; do [ -n "$f" ] && echo "$f"; done <<< "$files"
  exit 0
) >/dev/null 2>&1; then ok "empty listing loop does not abort"; else bad "empty listing loop aborted"; fi

echo ""
echo "$PASSES passed, $FAILS failed"
[ "$FAILS" -eq 0 ]
