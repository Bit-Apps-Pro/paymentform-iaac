#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

DATA_VOLUME="${data_volume_device}"
MOUNT_POINT="/mnt/postgresql"

if [ -b "${DATA_VOLUME}" ]; then
    mkfs -t ext4 ${DATA_VOLUME}
    mkdir -p ${MOUNT_POINT}
    mount ${DATA_VOLUME} ${MOUNT_POINT}
    echo "${DATA_VOLUME} ${MOUNT_POINT} ext4 defaults,nofail 0 2" >> /etc/fstab
    mkdir -p ${MOUNT_POINT}/data
    chown -R postgres:postgres ${MOUNT_POINT}
    chmod 700 ${MOUNT_POINT}/data
fi

log "Installing PostgreSQL ${postgres_version} on AL2023..."

dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf module disable postgresql -y || true
dnf install -y postgresql${postgres_version} postgresql${postgres_version}-server pgbackrest

PGDATA_DIR="${MOUNT_POINT}/data"
PGCONF_FILE="/var/lib/pgsql/${postgres_version}/data/postgresql.conf"

mkdir -p /etc/pgbackrest
cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-type=s3
repo1-s3-bucket=${r2_bucket_name}
repo1-s3-endpoint=${r2_endpoint}
repo1-s3-key=${r2_access_key}
repo1-s3-key-secret=${r2_secret_key}
repo1-cipher-pass=${pgbackrest_cipher_pass}
repo1-retention-diff=7
repo1-retention-full=7

[db]
db-path=${PGDATA_DIR}
db-port=5432
db-user=postgres
EOF

RESTORE_BACKUP_VAL="false"
if [ -z "$(ls -A ${PGDATA_DIR} 2>/dev/null)" ]; then
    log "Data directory is empty, checking for backups..."
    if pgbackrest info 2>/dev/null | grep -q "backup"; then
        RESTORE_BACKUP_VAL="true"
    fi
fi

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "Restoring from pgbackrest backup..."
    chown -R postgres:postgres ${MOUNT_POINT}
    chmod 700 ${MOUNT_POINT}/data
    
    su - postgres -c "pgbackrest restore --type=latest --force"
    log "Backup restored successfully"
else
    log "Initializing new PostgreSQL data directory..."
    /usr/pgsql-${postgres_version}/bin/postgresql-${postgres_version} --initdb || true
    chown -R postgres:postgres ${MOUNT_POINT}
    chmod 700 ${MOUNT_POINT}/data
fi

echo "data_directory = '${PGDATA_DIR}'" >> "$PGCONF_FILE"
echo "listen_addresses = '*'" >> "$PGCONF_FILE"
echo "max_wal_senders = 3" >> "$PGCONF_FILE"
echo "max_replication_slots = 3" >> "$PGCONF_FILE"
echo "wal_level = replica" >> "$PGCONF_FILE"
echo "hot_standby = on" >> "$PGCONF_FILE"

PG_HBA_FILE="/var/lib/pgsql/${postgres_version}/data/pg_hba.conf"
echo "host     all             all             10.0.0.0/16           trust" >> $PG_HBA_FILE
echo "host     replication     replicator      10.0.0.0/16           md5" >> $PG_HBA_FILE

systemctl enable postgresql-${postgres_version}
systemctl start postgresql-${postgres_version}

sleep 5

if [ "$RESTORE_BACKUP_VAL" = "true" ]; then
    log "PostgreSQL restored from backup and started"
else
    su - postgres -c "psql -c \"CREATE DATABASE ${db_name};\" 2>/dev/null || true"
    su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${db_password}';\""
    log "PostgreSQL primary setup complete"
fi
