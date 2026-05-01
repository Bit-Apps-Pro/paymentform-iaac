# Troubleshooting

## EBS Volume Not Mounted After Reboot

**Symptom**: PostgreSQL fails to start, data directory is empty or missing, `mountpoint /mnt/postgresql` returns "not a mount point".

**Cause**: The `postgresql-data-mount.service` unit may have failed, or the fstab entry is missing/incorrect.

**Fix**:

```bash
# Check mount service status
systemctl status postgresql-data-mount.service

# Try starting the mount service
systemctl start postgresql-data-mount.service

# If that fails, run the mount script manually
/usr/local/bin/mount-postgresql-data.sh /dev/sdf

# Verify fstab has a UUID-based entry
grep /mnt/postgresql /etc/fstab
# Should show: UUID=<uuid> /mnt/postgresql ext4 defaults,nofail 0 2

# If fstab entry is missing, add it manually
DEVICE=$(resolve_data_volume /dev/sdf)  # or find it via lsblk
UUID=$(blkid -s UUID -o value "$DEVICE")
echo "UUID=$UUID /mnt/postgresql ext4 defaults,nofail 0 2" >> /etc/fstab

# Then start PostgreSQL
pg_ctlcluster 17 main start
```

On NVMe instances, the device may appear as `/dev/nvme0n1` instead of `/dev/sdf`. The mount script handles this via `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol*` detection.

## PostgreSQL Shows `active (exited)` But Is Not Running

**Symptom**: `systemctl status postgresql` shows `active (exited)` but `pg_isready` fails or connections are refused.

**Cause**: The `postgresql` systemd unit is a meta-unit that only starts/stops the cluster manager. The actual cluster is managed by `pg_ctlcluster`.

**Fix**:

```bash
# Check the actual cluster status
pg_ctlcluster 17 main status

# Start the cluster directly
pg_ctlcluster 17 main start

# Stop it
pg_ctlcluster 17 main stop

# Restart it
pg_ctlcluster 17 main restart
```

## `data_directory` Points to Wrong Path

**Symptom**: PostgreSQL starts but uses `/var/lib/pgsql/data` instead of `/mnt/postgresql/data`, or vice versa.

**Cause**: The systemd override at `/etc/systemd/system/postgresql.service.d/override.conf` has the wrong `PGDATA` value, or the override file is missing.

**Fix**:

```bash
# Check current override
cat /etc/systemd/system/postgresql.service.d/override.conf

# It should contain:
# [Unit]
# After=postgresql-data-mount.service
# Requires=postgresql-data-mount.service
#
# [Service]
# Environment=PGDATA=/mnt/postgresql/data

# If PGDATA is wrong, fix it:
mkdir -p /etc/systemd/system/postgresql.service.d
cat > /etc/systemd/system/postgresql.service.d/override.conf <<'EOF'
[Unit]
After=postgresql-data-mount.service
Requires=postgresql-data-mount.service

[Service]
Environment=PGDATA=/mnt/postgresql/data
EOF

systemctl daemon-reload
pg_ctlcluster 17 main restart

# Verify
sudo -u postgres psql -c "SHOW data_directory;"
# Should return /mnt/postgresql/data
```

## barman-cloud `--aws-access-key-id` Unrecognized

**Symptom**: `barman-cloud-backup` or `barman-cloud-restore` fails with `unrecognized arguments: --aws-access-key-id`.

**Cause**: barman-cloud 3.x removed CLI flags for AWS credentials. They must be provided as environment variables.

**Fix**: Remove any `--aws-access-key-id` or `--aws-secret-access-key` flags and use environment variables instead:

```bash
# Wrong (barman 3.x)
barman-cloud-backup --aws-access-key-id=KEY ...

# Correct
export AWS_ACCESS_KEY_ID="KEY"
export AWS_SECRET_ACCESS_KEY="SECRET"
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required
barman-cloud-backup --cloud-provider aws-s3 --endpoint-url https://ACCOUNT.r2.cloudflarestorage.com ...
```

The `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` env vars are required for Cloudflare R2 (S3-compatible endpoint).

## barman-cloud FileNotFoundError on Tmp Dir

**Symptom**: During backup or restore, a Python traceback appears:

```
Exception ignored in: <function ...>
FileNotFoundError: [Errno 2] No such file or directory: '/tmp/...'
```

**Cause**: Python 3.14 tmp dir cleanup race condition. The backup or restore operation completes successfully despite this traceback.

**Fix**: None needed. This is harmless noise. Verify the backup succeeded by checking the exit code or listing backups:

```bash
barman-cloud-backup-list --format json "$DESTINATION" "$SERVER_NAME"
```

## Worker Not Deploying

**Symptom**: CDN worker changes are not appearing, or `tofu plan` shows no changes for the worker module.

**Cause**: `worker_enabled` is set to `false` in the module configuration.

**Fix**: Set `worker_enabled = true` in `environments/prod/main.tf`:

```hcl
module "paymentform_storage_cdn" {
  # ...
  worker_enabled = true   # must be true for worker to deploy
  # ...
}
```

Then apply:

```bash
cd environments/prod
tofu apply -target=module.paymentform_storage_cdn
```

## PostgreSQL Replication Not Working

**Symptom**: Replica is not receiving WAL data from primary.

**Checks**:

```bash
# On primary: check replication status
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# On replica: check if in recovery mode
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# Should return 't' (true) for replica

# Check primary_conninfo in postgresql.conf on replica
grep primary_conninfo /etc/postgresql/17/main/postgresql.conf

# Check that the replication user exists on primary
sudo -u postgres psql -c "\du replicator"
```

Common issues: wrong `primary_conninfo`, firewall blocking port 5432, or `pg_hba.conf` not allowing replication connections.

## Cloudflare Tunnel Down (Hetzner Replicas)

**Symptom**: Hetzner backend servers cannot connect to the PostgreSQL primary.

**Checks**:

```bash
# On the primary EC2 instance
systemctl status cloudflared

# Check tunnel logs
journalctl -u cloudflared --no-pager -n 50

# From Hetzner, test connectivity
psql -h <tunnel_cname> -U replicator -d paymentform
```

The tunnel token is provisioned via `module.tunnel_db` and passed to the primary userdata.