# Backup and disaster recovery

Clinical records must be retrievable for years, and Supabase's free plan has
no automated backups. This takes a nightly encrypted copy of every table and
every patient photo and stores it in a restricted Google Drive folder.

| | |
|---|---|
| What is backed up | All tables, plus every file in the `patient-photos` bucket |
| Encryption | GPG symmetric, AES-256, encrypted **before** it leaves the runner |
| Where it goes | A Google Drive folder shared only with a dedicated service account |
| Schedule | Daily at 02:30 UTC, via GitHub Actions |
| Retention | 90 days, then pruned automatically |
| Verified | Every run decrypts its own output and checks all checksums |

Table structure and security policies are **not** in the backup by design.
They live in `supabase/*.sql` in this repo, so a rebuild is: run the SQL
files, then restore the data.

## One-time setup

### 1. Choose a passphrase

Generate a long random passphrase and store it in a password manager. **If
this is lost, the backups are unreadable.** Store it somewhere separate from
the Google account, so one compromised account does not give access to both.

### 2. Storage destination

No service account is needed. Many Google organisations block service
account key creation ("An organisation policy that blocks service account
key creation has been enforced"), so this authorises with a normal login
instead.

Use a Google account **Rica controls**, not one belonging to an employer or
other organisation, whose admins may be able to reach its Drive.

1. Download rclone from <https://rclone.org/downloads/> (a single .exe, no
   installer needed).
2. In a terminal, run `rclone config`, then:
   - `n` for a new remote, name it `gdrive`
   - storage type: `drive`
   - leave client_id and client_secret blank
   - scope: `1` (full access)
   - leave root_folder_id and service_account_file blank
   - `n` to advanced config, `y` to use a browser to authorise
   - sign in and allow access
3. Create a folder in Drive, for example `GlowByRica Backups`.
4. Show the config file: `rclone config file` gives its path. Open it and
   copy the **entire contents** (it will include a `token = {...}` line).

The same steps work for Backblaze B2, Dropbox or OneDrive if you would
rather not use Drive. Only the remote name changes.

### 3. Repository secrets

In GitHub: Settings, Secrets and variables, Actions. Add:

| Secret | Value |
|---|---|
| `SUPABASE_URL` | `https://kychrharobhmyzuywvpm.supabase.co` |
| `SUPABASE_SERVICE_KEY` | Supabase, Settings, API, `service_role` key |
| `BACKUP_PASSPHRASE` | The passphrase from step 1 |
| `RCLONE_CONFIG` | Entire contents of rclone.conf from step 2 |
| `RCLONE_REMOTE` | `gdrive:GlowByRica Backups` (remote name, colon, folder) |

The `service_role` key bypasses all security rules. It belongs only in
GitHub secrets, never in the website code.

Because the archive is encrypted before upload, whoever hosts the files
cannot read them. The passphrase is what protects the contents; the storage
account only controls who can obtain the file at all.

### 4. First run

Actions tab, "Encrypted clinical backup", Run workflow. It backs up, then
verifies its own archive. Confirm a `.gpg` file appears in the Drive folder.

## Restoring

Download an archive from Drive, then:

```bash
export BACKUP_PASSPHRASE='...'

# Is it intact? Decrypts and checks every checksum. Writes nothing.
./backup/restore.sh glowbyrica-20260728T023000Z.tar.gz.gpg --verify

# What would it write?
./backup/restore.sh glowbyrica-20260728T023000Z.tar.gz.gpg --dry-run

# Write it into a project
export TARGET_URL='https://<ref>.supabase.co'
export TARGET_SERVICE_KEY='<service_role key for that project>'
./backup/restore.sh glowbyrica-20260728T023000Z.tar.gz.gpg --restore
```

The target is set through separate `TARGET_*` variables on purpose, so a
restore cannot be aimed at the live project by accident. `--restore` also
asks you to type `RESTORE` before writing anything.

Restores merge on primary key, so re-running one is safe.

### Recovering from accidental deletion

1. `--verify` the most recent archive from before the deletion.
2. Restore into a **scratch** Supabase project first and check the data there.
3. Once satisfied, restore into the live project. Existing rows are updated
   rather than duplicated, so only the missing records reappear.

### Rebuilding from nothing

1. Create a Supabase project.
2. Run `supabase/*.sql` in order (see the file headers).
3. Create Rica's login, add her to `admin_users`.
4. Restore the newest archive.
5. Update `supabase-client.js` with the new project URL and anon key.

## Rehearse it

A backup nobody has restored is a guess. Twice a year, restore the latest
archive into a scratch project and confirm the admin panel shows the records
and photos. Note the date you did it.

`./backup/test-roundtrip.sh` checks the format itself with synthetic data:
that archives are encrypted, wrong passphrases fail, corruption is detected,
and files survive byte-for-byte. It needs no credentials.

## What this does not protect against

- **A leak.** Backups guard against loss, not disclosure. Access control,
  2FA and the private photo bucket cover that.
- **Silent bad data.** If a record is wrongly edited and not noticed for over
  90 days, every retained backup will contain the bad version.
- **Passphrase loss.** There is no recovery. Store it properly.
