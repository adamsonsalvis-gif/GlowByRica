# Parsing helpers for Supabase Storage listings.
#
# Kept in their own file so they can be tested without credentials. Both
# guard against grep's exit status: grep returns 1 when it matches nothing,
# which is the normal case for an empty bucket or folder, and under
# `set -euo pipefail` that would abort the whole backup.

# stdin: a storage list JSON array -> stdout: names of real files
names_with_id() {
  grep -o '{"name":"[^"]*","id":"[^"]*"' | sed 's/{"name":"//; s/","id":".*//' || true
}

# stdin: a storage list JSON array -> stdout: names of folders (null id)
names_without_id() {
  grep -o '{"name":"[^"]*","id":null' | sed 's/{"name":"//; s/","id":null//' || true
}
