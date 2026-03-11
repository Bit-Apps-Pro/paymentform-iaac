#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"

if [ -b "$DATA_VOLUME" ]; then
    mkfs -t ext4 $DATA_VOLUME
    mkdir -p "$MOUNT_POINT"
    mount $DATA_VOLUME "$MOUNT_POINT"
    echo "$DATA_VOLUME $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
    mkdir -p $MOUNT_POINT/data
    chown -R postgres:postgres "$MOUNT_POINT"
    chmod 700 "$MOUNT_POINT/data"
fi

log "Installing PostgreSQL ${postgres_version} on AL2023..."

dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf module disable postgresql -y || true
dnf install -y postgresql${postgres_version} postgresql${postgres_version}-server pgbackrest

PGDATA_DIR="$MOUNT_POINT/data"
PGCONF_FILE="/var/lib/pgsql/${postgres_version}/data/postgresql.conf"

rm -rf "$PGDATA_DIR" || true
mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"

echo "hot_standby = on" >> "$PGCONF_FILE"

log "Starting base backup from primary ${primary_ip}..."

su - postgres -c "pg_basebackup -h ${primary_ip} -D "$PGDATA_DIR" -U replicator -v -P"

cat > "$PGDATA_DIR/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=${primary_ip} port=5432 user=replicator password=${db_password}'
primary_slot_name = ''
hot_standby = on
EOF

chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

systemctl enable postgresql-${postgres_version}
systemctl start postgresql-${postgres_version}

log "PostgreSQL replica setup complete"
