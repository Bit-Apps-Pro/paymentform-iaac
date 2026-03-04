#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Install PostgreSQL
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-$${postgres_version} postgresql-contrib-$${postgres_version} pgbackrest

# Stop PostgreSQL initially
systemctl stop postgresql

# Configure PostgreSQL as replica
PGDATA_DIR="/var/lib/postgresql/$${postgres_version}/main"
PGCONF_FILE="/etc/postgresql/$${postgres_version}/main/postgresql.conf"

# Clear existing data directory
rm -rf "$${PGDATA_DIR}"
mkdir -p "$${PGDATA_DIR}"
chown -R postgres:postgres "$${PGDATA_DIR}"

# Configure as hot standby
echo "hot_standby = on" >> "$$PGCONF_FILE"

# Setup replication from primary
su - postgres -c "pg_basebackup -h $${primary_ip} -D $${PGDATA_DIR} -U replicator -v -P"

# Create recovery configuration
cat > "$${PGDATA_DIR}/postgresql.auto.conf" <<'EOF'
primary_conninfo = 'host=$${primary_ip} port=5432 user=replicator password=$${db_password}'
primary_slot_name = ''
hot_standby = on
EOF

chown -R postgres:postgres "$${PGDATA_DIR}"
chmod 700 "$${PGDATA_DIR}"

# Start PostgreSQL as replica
systemctl enable postgresql
systemctl start postgresql

echo "PostgreSQL replica setup complete"
