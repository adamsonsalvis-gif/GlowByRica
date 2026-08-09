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

Download rclone from <https://rclone.org/downloads/> first (a single .exe,
no installer needed). Then pick one of the options below.

Because the archive is encrypted before it is uploaded, the host cannot read
it. Choose based on which is least likely to break unattended.

#### Option A: Backblaze B2 (recommended)

No OAuth, no consent screens, no tokens that expire. 10 GB free, which is
far more than these backups need.

1. Create an account at <https://www.backblaze.com/b2/sign-up.html>
2. Create a **private** bucket, for example `glowbyrica-backups`
3. App Keys, "Add a New Application Key", restricted to that bucket, with
   read and write. Copy the keyID and applicationKey (shown once).
4. `rclone config`: new remote named `b2`, storage type `b2`, paste the
   keyID as Account ID and applicationKey as Key. Accept the defaults.
5. Test: `rclone lsd b2:`

Remote value for the secret below: `b2:glowbyrica-backups`

#### Option B: Google Drive

Workable, but Google needs more care:

- Many organisations block service account keys, so use a normal sign-in.
- rclone's shared client ID is being retired during 2026, so **make your own**
  or the backup will stop working: <https://rclone.org/drive/#making-your-own-client-id>
- Use an account **Rica controls**. On an employer or other organisation's
  account, its admins may be able to reach the Drive.

Making your own client ID, briefly:

1. <https://console.cloud.google.com>, create a project
2. APIs and Services, Library, enable **Google Drive API**
3. APIs and Services, OAuth consent screen:
   - On a Workspace account choose **Internal**. Simplest: no verification,
     and refresh tokens do not expire.
   - On a personal Gmail you must choose External, then **publish** the app.
     Left in "Testing" the refresh token expires after 7 days and the backup
     breaks weekly.
4. Credentials, Create Credentials, OAuth client ID, type **Desktop app**.
   Copy the client ID and client secret.
5. `rclone config`: new remote named `gdrive`, type `drive`, paste your own
   client_id and client_secret, scope `1`, browser sign-in.
6. Create a Drive folder, for example `GlowByRica Backups`.

Remote value for the secret below: `gdrive:GlowByRica Backups`

#### Either way

Show the config file with `rclone config file`, open it, and copy the
**entire contents**. It contains live credentials, so treat it like a
password: never commit it or paste it into a chat.

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
