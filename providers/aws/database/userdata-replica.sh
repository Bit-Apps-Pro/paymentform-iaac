#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
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

if [ -b "$DATA_VOLUME" ]; then
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
    chown -R postgres:postgres "$MOUNT_POINT"
    chmod 700 "$PGDATA_DIR"
else
    log "Data volume $DATA_VOLUME not found, using default location"
    PGDATA_DIR="/var/lib/pgsql/data"
    mkdir -p "$PGDATA_DIR"
    chown -R postgres:postgres /var/lib/pgsql
    chmod 700 "$PGDATA_DIR"
fi
dnf update -y

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres $(dirname $PGDATA_DIR)
chmod 700 "$PGDATA_DIR"

mkdir -p "/etc/systemd/system/postgresql.service.d"
cat > "/etc/systemd/system/postgresql.service.d/override.conf" <<EOF
[Service]
Environment=PGDATA=$PGDATA_DIR
EOF
systemctl daemon-reload

PGCONF_FILE="$PGDATA_DIR/postgresql.conf"

rm -rf "$PGDATA_DIR" || true
mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres $(dirname $PGDATA_DIR)
chmod 700 $PGDATA_DIR

log "Starting base backup from primary ${primary_ip}..."

su - postgres -c "pg_basebackup -h ${primary_ip} -D '$PGDATA_DIR' -U replicator -v -P"

echo "hot_standby = on" >> "$PGCONF_FILE"

cat > "$PGDATA_DIR/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=${primary_ip} port=5432 user=replicator password=${db_password}'
primary_slot_name = ''
hot_standby = on
EOF

chown -R postgres:postgres $(dirname $PGDATA_DIR)
chmod 700 $PGDATA_DIR

systemctl enable postgresql
systemctl start postgresql

log "PostgreSQL replica setup complete"
