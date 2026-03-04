#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Install PostgreSQL
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-$${postgres_version} postgresql-contrib-$${postgres_version} pgbackrest

# Configure PostgreSQL
PGDATA_DIR="/var/lib/postgresql/$${postgres_version}/main"
PGCONF_FILE="/etc/postgresql/$${postgres_version}/main/postgresql.conf"

# Update postgresql.conf for replication and pgbackrest
echo "listen_addresses = '*'" >> "$$PGCONF_FILE"
echo "max_wal_senders = 3" >> "$$PGCONF_FILE"
echo "max_replication_slots = 3" >> "$$PGCONF_FILE"
echo "wal_level = replica" >> "$$PGCONF_FILE"
echo "hot_standby = on" >> "$$PGCONF_FILE"

# Create replication user
su - postgres -c "psql -c \"CREATE USER replicator WITH REPLICATION PASSWORD '${db_password}';\""

# Configure pg_hba.conf for replication
echo "host     all             all             10.0.0.0/16           trust" >> /etc/postgresql/$${postgres_version}/main/pg_hba.conf
echo "host     replication     replicator      10.0.0.0/16           md5" >> /etc/postgresql/$${postgres_version}/main/pg_hba.conf

# Configure pgbackrest
mkdir -p /etc/pgbackrest
cat > /etc/pgbackrest/pgbackrest.conf <<'EOF'
[global]
repo1-type=s3
repo1-s3-bucket=$${r2_bucket_name}
repo1-s3-endpoint=$${r2_endpoint}
repo1-s3-key=$${r2_access_key}
repo1-s3-key-secret=$${r2_secret_key}
repo1-cipher-pass=$${pgbackrest_cipher_pass}
repo1-retention-diff=7
repo1-retention-full=7

[db]
db-path=$${PGDATA_DIR}
db-port=5432
db-user=postgres
EOF

# Start PostgreSQL
systemctl enable postgresql
systemctl start postgresql

# Create database if not exists
su - postgres -c "psql -c \"CREATE DATABASE $${db_name};\" 2>/dev/null || true"

# Configure primary for replication
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '${db_password}';\""

sleep 10

echo "PostgreSQL primary setup complete"
