# Parsing helpers for Supabase Storage listings and the client_photos table.
#
# Kept in their own file so they can be tested without credentials.
#
# Two things these must survive:
#  1. grep exits 1 when it matches nothing, which is the normal case for an
#     empty bucket or table, and under `set -euo pipefail` that would abort
#     the whole backup. Every pipeline here ends in `|| true`.
#  2. The API's JSON layout. These used to assume the keys came in one exact
#     order ("name" immediately followed by "id"). When that assumption stopped
#     holding, every photo silently vanished from the backup. They now look at
#     each object on its own, in any key order and with any whitespace.

# stdin: JSON array -> stdout: one object per line
_objects() {
  tr -d '\n\r' | sed 's/}[[:space:]]*,[[:space:]]*{/}\n{/g'
}

# stdin: one object per line -> stdout: each object's "name"
_name_of() {
  sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# A real file has a string id. Folders come back with a null id (or none).
_HAS_ID='"id"[[:space:]]*:[[:space:]]*"[^"]'

# stdin: a storage list JSON array -> stdout: names of real files
names_with_id() {
  _objects | grep -E "$_HAS_ID" | _name_of || true
}

# stdin: a storage list JSON array -> stdout: names of folders
names_without_id() {
  _objects | grep -vE "$_HAS_ID" | _name_of || true
}

# stdin: the exported client_photos table (JSON array) -> stdout: the storage
# path of every photo the database knows about. This is a second, independent
# source of truth: the database is the record of which photos exist, so a
# change in how the storage listing looks can no longer hide them.
paths_from_table() {
  grep -oE '"path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/^"path"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

# stdin: the exported client_photos table -> stdout: how many photo rows
count_db_photo_rows() {
  paths_from_table | wc -l | tr -d ' '
}
