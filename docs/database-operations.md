# Database Operations

## PostgreSQL Setup Overview

The production database runs PostgreSQL 17 on Ubuntu EC2 instances in `us-east-1`.

- Primary: `prod-postgresql-primary` in `us-east-1a`
- Replica: `prod-postgresql-replica` in `us-east-1b`
- Cluster config: `/etc/postgresql/17/main/`
- Data directory: `/mnt/postgresql/data`
- EBS volume: gp3, 30GB, encrypted, 3000 IOPS, 125 MB/s throughput

Hetzner replicas in Helsinki (hel1) and Singapore (sin1) connect to the primary via Cloudflare Tunnel (`module.tunnel_db`).

## EBS Volume Mount

The data volume is mounted via a dedicated systemd service, not `/etc/fstab` directly.

### How It Works

1. `postgresql-data-mount.service` runs before `postgresql.service`.
2. The mount script (`/usr/local/bin/mount-postgresql-data.sh`) resolves the EBS device name (handles `/dev/sdf` vs `/dev/xvdf` naming), formats if needed, and mounts to `/mnt/postgresql`.
3. After mounting, the script adds a UUID-based entry to `/etc/fstab`:
   ```
   UUID=<uuid> /mnt/postgresql ext4 defaults,nofail 0 2
   ```
4. A systemd override at `/etc/systemd/system/postgresql.service.d/override.conf` sets `PGDATA=/mnt/postgresql/data` and adds `Requires=postgresql-data-mount.service`.

### Manual Mount Fix

If the volume is not mounted after a reboot:

```bash
# Check if mounted
mountpoint -q /mnt/postgresql && echo "mounted" || echo "not mounted"

# Try the mount service
systemctl start postgresql-data-mount.service

# If that fails, run the mount script directly
/usr/local/bin/mount-postgresql-data.sh /dev/sdf

# Verify
mountpoint /mnt/postgresql
ls /mnt/postgresql/data/PG_VERSION
```

If the device name changed (NVMe instances), the script auto-detects via `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol*`.

## Promote Replica to Primary

Use this when the primary is down and you need the replica to take over.

### Steps

1. Stop PostgreSQL on the replica:
   ```bash
   pg_ctlcluster 17 main stop
   ```

2. Remove standby signaling. Depending on the PostgreSQL version and setup:
   ```bash
   # If standby.signal exists (PG 12+)
   rm -f /mnt/postgresql/data/standby.signal

   # If recovery.conf exists (older setups)
   rm -f /mnt/postgresql/data/recovery.conf
   ```

3. Remove `primary_conninfo` from `postgresql.conf` if present:
   ```bash
   sed -i '/primary_conninfo/d' /etc/postgresql/17/main/postgresql.conf
   ```

4. Update `pg_hba.conf` to allow connections from application servers:
   ```bash
   # Edit /etc/postgresql/17/main/pg_hba.conf
   # Ensure these lines exist (adjust CIDR as needed):
   # host  all  all  10.0.0.0/16  trust
   # host  replication  replicator  10.0.0.0/16  md5
   ```

5. Start PostgreSQL as primary:
   ```bash
   pg_ctlcluster 17 main start
   ```

6. Verify it is running in primary mode:
   ```bash
   sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
   # Should return 'f' (false) for primary
   ```

7. Update application connection strings and DNS to point to the new primary.

8. Update the Cloudflare Tunnel configuration if the primary endpoint changes.

## Restore from Barman-Cloud Backup

Backups are stored in Cloudflare R2 using `barman-cloud-backup`. The bucket is `paymentform-prod-db-backups` (or the value of `var.backup_storage_bucket_name`), and the endpoint is Cloudflare R2 S3-compatible.

### List Available Backups

```bash
export AWS_ACCESS_KEY_ID="<from SSM or env>"
export AWS_SECRET_ACCESS_KEY="<from SSM or env>"
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

BARMAN_OPTS="--cloud-provider aws-s3 --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
DESTINATION="s3://paymentform-prod-db-backups/postgresql"
SERVER_NAME="prod-postgresql-primary"

barman-cloud-backup-list $BARMAN_OPTS --format json "$DESTINATION" "$SERVER_NAME"
```

### Restore Steps

1. Stop PostgreSQL:
   ```bash
   pg_ctlcluster 17 main stop
   ```

2. Clear the data directory:
   ```bash
   rm -rf /mnt/postgresql/data/*
   ```

3. Restore from backup:
   ```bash
   export AWS_ACCESS_KEY_ID="<key>"
   export AWS_SECRET_ACCESS_KEY="<secret>"
   export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
   export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

   BACKUP_ID="<from backup list>"

   barman-cloud-restore \
     --cloud-provider aws-s3 \
     --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com \
     "$DESTINATION" "$SERVER_NAME" "$BACKUP_ID" /mnt/postgresql/data
   ```

4. Fix ownership:
   ```bash
   chown -R postgres:postgres /mnt/postgresql/data
   ```

5. Start PostgreSQL:
   ```bash
   pg_ctlcluster 17 main start
   ```

6. Verify:
   ```bash
   sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
   ```

### Important Notes on Credentials

barman-cloud 3.x does not accept `--aws-access-key-id` / `--aws-secret-access-key` as CLI flags. Credentials must be set as environment variables:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
```

The `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` env vars are required for S3-compatible endpoints like Cloudflare R2.

## Backup Retention

Backups run on a nightly cron at 02:00 UTC, with cleanup at 02:30 UTC. Both are defined in `/etc/cron.d/barman-backup`:

```
0 2 * * * postgres <env_vars> barman-cloud-backup <opts> <destination> <server_name> >> /var/log/barman-backup.log 2>&1
30 2 * * * postgres <env_vars> barman-cloud-backup-delete <opts> --retention-policy 'RECOVERY WINDOW OF 15 DAYS' <destination> <server_name> >> /var/log/barman-backup.log 2>&1
```

Retention policy: 15 days. Backups older than 15 days are automatically pruned.

## WAL Archiving

WAL archiving is configured in `/etc/postgresql/17/main/postgresql.conf`:

```
archive_mode = on
archive_command = 'AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> barman-cloud-wal-archive --cloud-provider aws-s3 --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com s3://paymentform-prod-db-backups/postgresql prod-postgresql-primary %p'
archive_timeout = 300
```

WAL files are archived to the same R2 bucket under the server name `prod-postgresql-primary`. The 300-second timeout forces a WAL switch every 5 minutes, ensuring point-in-time recovery granularity of at most 5 minutes.

## Python 3.14 Tmp Dir Traceback

During `barman-cloud-backup` or `barman-cloud-restore`, you may see a traceback like:

```
Exception ignored in: <function ...>
FileNotFoundError: [Errno 2] No such file or directory: '/tmp/...'
```

This is a known harmless noise from Python 3.14's tmp dir cleanup. The backup or restore completes successfully. Ignore it.

## Manual Database Setup (Fresh Instance)

If building a new primary from scratch (no backup to restore):

1. The userdata script (`userdata-primary.sh`) handles this automatically on first boot.
2. It installs PostgreSQL 17, creates the data directory, sets up the EBS mount, configures `postgresql.conf` and `pg_hba.conf`, and creates the initial database and users.
3. If a backup exists in R2, it restores from the latest backup instead of initializing a fresh cluster.

Key user/database creation (from userdata):

```bash
su - postgres -c "psql -c \"CREATE DATABASE paymentform;\""
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '<password>';\""
su - postgres -c "psql -c \"CREATE USER replicator WITH REPLICATION PASSWORD '<password>';\""
```