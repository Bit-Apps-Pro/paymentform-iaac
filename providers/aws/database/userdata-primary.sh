#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

validate_pgdata_dir() {
  case "$1" in
    /mnt/postgresql/data|/var/lib/pgsql/data) ;;
    *)
      log "Refusing to operate on unexpected PGDATA_DIR: $1"
      exit 1
      ;;
  esac
}

resolve_data_volume() {
  local requested="$1"
  local alternate=""
  local root_source=""
  local root_disk=""
  local candidate=""
  local disk_path=""
  local disk_name=""
  local disk_type=""

  if [[ "$requested" == /dev/sd* ]]; then
    alternate="/dev/xvd$${requested#/dev/sd}"
  elif [[ "$requested" == /dev/xvd* ]]; then
    alternate="/dev/sd$${requested#/dev/xvd}"
  fi

  root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  if [ -n "$root_source" ]; then
    root_disk="$(lsblk -no PKNAME "$root_source" 2>/dev/null || true)"
    if [ -z "$root_disk" ]; then
      root_disk="$(basename "$root_source")"
    fi
  fi

  for _ in $(seq 1 24); do
    for candidate in "$requested" "$alternate"; do
      if [ -n "$candidate" ] && [ -b "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done

    for candidate in /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol*; do
      [ -e "$candidate" ] || continue
      disk_path="$(readlink -f "$candidate")"
      if [ -b "$disk_path" ] && [ "$(basename "$disk_path")" != "$root_disk" ]; then
        printf '%s\n' "$disk_path"
        return 0
      fi
    done

    while read -r disk_name disk_type; do
      [ "$disk_type" = "disk" ] || continue
      [ "$disk_name" = "$root_disk" ] && continue
      disk_path="/dev/$disk_name"
      if [ -b "$disk_path" ]; then
        printf '%s\n' "$disk_path"
        return 0
      fi
    done < <(lsblk -dn -o NAME,TYPE 2>/dev/null)

    sleep 5
  done

  return 1
}

DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"
PGDATA_DIR="$MOUNT_POINT/data"

if ! getent group postgres >/dev/null; then
    groupadd --system postgres
fi

if ! id postgres >/dev/null 2>&1; then
    useradd --system --gid postgres --home-dir /var/lib/pgsql --shell /bin/bash postgres
fi

REQUESTED_DATA_VOLUME="$DATA_VOLUME"
DATA_VOLUME="$(resolve_data_volume "$REQUESTED_DATA_VOLUME" || true)"

if [ -n "$DATA_VOLUME" ] && [ -b "$DATA_VOLUME" ]; then
    log "Using data volume $DATA_VOLUME"
    if ! blkid "$DATA_VOLUME" >/dev/null 2>&1; then
        mkfs -t ext4 "$DATA_VOLUME"
    fi

    mkdir -p "$MOUNT_POINT"

    if ! mountpoint -q "$MOUNT_POINT"; then
        mount "$DATA_VOLUME" "$MOUNT_POINT"
    fi

    if ! grep -q "^$DATA_VOLUME $MOUNT_POINT ext4 defaults,nofail 0 2$" /etc/fstab; then
        echo "$DATA_VOLUME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    fi

    mkdir -p "$PGDATA_DIR"
    chown postgres:postgres "$MOUNT_POINT"
    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
else
    log "Data volume $REQUESTED_DATA_VOLUME not found, using default location"
    PGDATA_DIR="/var/lib/pgsql/data"
    mkdir -p "$PGDATA_DIR"
    chown postgres:postgres /var/lib/pgsql
    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
fi

validate_pgdata_dir "$PGDATA_DIR"

# Avoid full system upgrades during first boot; they can leave core packages
# in a bad state if cloud-init is interrupted or a reboot is deferred.

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

mkdir -p "/etc/systemd/system/postgresql.service.d"
cat > "/etc/systemd/system/postgresql.service.d/override.conf" <<EOF
[Service]
Environment=PGDATA=$PGDATA_DIR
EOF
systemctl daemon-reload

PGCONF_FILE="$PGDATA_DIR/postgresql.conf"

mkdir -p /etc/pgbackrest
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=${database_backup_bucket_name}
repo1-s3-endpoint=${database_backup_bucket_endpoint}
repo1-s3-key=${database_backup_bucket_access_key_id}
repo1-s3-key-secret=${database_backup_bucket_access_key}
repo1-cipher-pass=${pgbackrest_cipher_pass}
repo1-retention-diff=7
repo1-retention-full=7

[db]
db-path=$PGDATA_DIR
db-port=5432
db-user=postgres
EOF

RESTORE_BACKUP_VAL="false"
if [ -z "$(ls -A $PGDATA_DIR 2>/dev/null)" ]; then
    log "Data directory is empty, checking for backups..."
    if pgbackrest info 2>/dev/null | grep -q "backup"; then
        RESTORE_BACKUP_VAL="true"
    fi
fi

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "Restoring from pgbackrest backup..."
    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
    
    su - postgres -c "pgbackrest restore --type=latest --force"
    log "Backup restored successfully"
else
    log "Initializing new PostgreSQL data directory..."
    su - postgres -c "initdb -D '$PGDATA_DIR'"
    chown -R postgres:postgres "$PGDATA_DIR"
    chmod 700 "$PGDATA_DIR"
fi

echo "data_directory = '$PGDATA_DIR'" >> "$PGCONF_FILE"
echo "listen_addresses = '*'" >> "$PGCONF_FILE"
echo "max_wal_senders = 3" >> "$PGCONF_FILE"
echo "max_replication_slots = 3" >> "$PGCONF_FILE"
echo "wal_level = replica" >> "$PGCONF_FILE"
echo "hot_standby = on" >> "$PGCONF_FILE"

PG_HBA_FILE="$PGDATA_DIR/pg_hba.conf"
echo "host     all             all             10.0.0.0/16           trust" >> $PG_HBA_FILE
echo "host     replication     replicator      10.0.0.0/16           md5" >> $PG_HBA_FILE
echo "host     replication     replicator      127.0.0.1/32          md5" >> $PG_HBA_FILE
${peer_vpc_cidrs_hba}

systemctl enable postgresql
systemctl start postgresql

%{ if tunnel_token != "" ~}
log "Installing cloudflared for DB tunnel"
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
apt-get update -y
apt-get install -y cloudflared

cat > /etc/systemd/system/cloudflared.service <<'EOF'
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Restart=on-failure
RestartSec=10
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token ${tunnel_token}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cloudflared
systemctl start cloudflared
log "cloudflared DB tunnel started"
%{ endif ~}

sleep 5

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "PostgreSQL restored from backup and started"
else
    su - postgres -c "psql -c \"CREATE DATABASE ${db_name};\" 2>/dev/null || true"
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${db_password}';\""
su - postgres -c "psql -c \"CREATE USER replicator WITH REPLICATION PASSWORD '${db_password}';\" 2>/dev/null || true"
    log "PostgreSQL primary setup complete"
fi
