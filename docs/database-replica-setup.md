# PostgreSQL Streaming Replication Setup Guide

Step-by-step guide for setting up PostgreSQL 17 streaming replication. Works across AWS, Hetzner, DigitalOcean, GCP, Azure, or bare metal.

## Section 1: Prerequisites

### Version Requirements

- **Primary and replica must run the same major version** (e.g., both PostgreSQL 17)
- Minor version differences are fine (17.2 primary, 17.4 replica works)
- Upgrading major version requires a full dump/restore, not replication

### Network

- The replica must be able to reach the primary on PostgreSQL's port (default `5432`)
- Latency under 10ms is ideal for streaming replication; higher latency works but increases lag
- For cross-region setups, a VPN, private network, or encrypted tunnel (WireGuard, Cloudflare Tunnel) is strongly recommended

### Disk Space

- Replica needs at least as much disk as the primary's data directory
- Add 20% headroom for WAL accumulation during replication catch-up
- Check primary size: `sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('paymentform'));"`

### Required Packages (Ubuntu/Debian)

```bash
# Add PostgreSQL 17 APT repository
sudo apt update
sudo apt install -y wget gnupg2 lsb-release

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

sudo apt update
sudo apt install -y postgresql-17

# For pg_basebackup, the client tools are included with postgresql-17
# Verify installation
psql --version
pg_basebackup --version
```

### Checklist Before Starting

- [ ] Primary and replica run same PostgreSQL major version
- [ ] Network path between primary and replica is open on port 5432
- [ ] Replica has sufficient disk space (primary size + 20%)
- [ ] PostgreSQL 17 installed on both servers
- [ ] You have sudo/root access on both servers
- [ ] You have the postgres user password or sudo access

---

## Section 2: Primary Server Configuration

All commands run on the **primary** server.

### 2.1 Edit `postgresql.conf`

Find your config file. On Ubuntu with the Debian layout, it's typically at `/etc/postgresql/17/main/postgresql.conf`. If using a custom data directory (like our EBS mount at `/mnt/postgresql/data`), check `data_directory` in the config to confirm.

```bash
sudo nano /etc/postgresql/17/main/postgresql.conf
```

Add or uncomment these settings:

```ini
# Replication settings
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on

# Network - listen on all interfaces so replicas can connect
# For production, restrict to specific interfaces if possible
listen_addresses = '*'

# WAL retention - keep WAL files long enough for replicas to catch up
# Prevents replicas from falling too far behind after disconnects
wal_keep_size = 256MB

# Optional but recommended: reduce replication lag visibility
wal_receiver_status_interval = 1s
```

**What each setting does:**

| Setting | Purpose |
|---------|---------|
| `wal_level = replica` | Writes enough WAL data for replication to work. `minimal` won't cut it. |
| `max_wal_senders = 10` | Allows up to 10 simultaneous replication connections. Adjust if you have more replicas. |
| `max_replication_slots = 10` | Replication slots prevent WAL deletion until the replica has consumed it. |
| `hot_standby = on` | Lets the replica accept read-only queries while replicating. |
| `listen_addresses = '*'` | Accepts connections on all network interfaces. Tighten this if you can. |
| `wal_keep_size = 256MB` | Keeps 256MB of WAL beyond what replicas need, as a safety buffer. |

### 2.2 Create a Replication User

```bash
sudo -u postgres psql -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'CHANGE_ME_STRONG_PASSWORD';"
```

Use a strong password. Store it in a password manager or AWS SSM Parameter Store.

Verify the user was created:

```bash
sudo -u postgres psql -c "\du replicator"
```

You should see `replication` in the "Attributes" column.

### 2.3 Configure `pg_hba.conf`

This is the most common source of replication failures. If the replica can't authenticate, replication won't start.

```bash
sudo nano /etc/postgresql/17/main/pg_hba.conf
```

Add this line **before** any catch-all rules:

```
# TYPE   DATABASE        USER            ADDRESS                 METHOD
host     replication     replicator      <REPLICA_IP>/32         md5
```

Replace `<REPLICA_IP>` with the replica's actual IP address. Examples:

```
# Single replica on a specific IP
host    replication     replicator      10.0.1.50/32            md5

# Replicas in a VPC subnet (AWS private network)
host    replication     replicator      10.0.0.0/16             md5

# Hetzner private network (vSwitch)
host    replication     replicator      10.10.0.0/16            md5

# Multiple replicas - add one line per replica or use CIDR ranges
host    replication     replicator      10.0.1.50/32            md5
host    replication     replicator      10.0.2.100/32           md5
host    replication     replicator      172.16.0.0/12           md5
```

**Important:** The `pg_hba.conf` file is processed top to bottom. The **first** matching rule wins. Put your replication rules above any generic rules.

If the replica connects through a tunnel or VPN, use the tunnel's IP range, not the replica's public IP.

### 2.4 Create a Replication Slot (Recommended)

Replication slots prevent the primary from deleting WAL files that a replica hasn't consumed yet. Without a slot, if a replica disconnects for too long, the primary might recycle WAL the replica still needs.

```bash
sudo -u postgres psql -c "SELECT pg_create_physical_replication_slot('replica_slot_1');"
```

Verify:

```bash
sudo -u postgres psql -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"
```

You should see `replica_slot_1` with `slot_type = physical` and `active = f` (false, until the replica connects).

### 2.5 Reload PostgreSQL

```bash
sudo systemctl reload postgresql
```

Or with the Debian/Ubuntu cluster command:

```bash
pg_ctlcluster 17 main reload
```

Verify the settings took effect:

```bash
sudo -u postgres psql -c "SHOW wal_level;"
# Should show: replica

sudo -u postgres psql -c "SHOW max_wal_senders;"
# Should show: 10
```

---

## Section 3: Preparing the Base Backup

Run these commands on the **replica** server.

### 3.1 Stop PostgreSQL on the Replica

```bash
sudo systemctl stop postgresql
# Or:
pg_ctlcluster 17 main stop
```

### 3.2 Clear the Data Directory

```bash
# WARNING: This deletes all existing data on the replica.
# Make sure this is a fresh server or you've backed up anything you need.

# Default data directory:
sudo rm -rf /var/lib/postgresql/17/main/*

# If using a custom data directory (like our EBS mount):
sudo rm -rf /mnt/postgresql/data/*
```

### 3.3 Run pg_basebackup

This copies the entire primary data directory to the replica over the network.

```bash
sudo -u postgres pg_basebackup \
  -h <PRIMARY_IP_OR_HOSTNAME> \
  -p 5432 \
  -U replicator \
  -D /var/lib/postgresql/17/main \
  -Fp \
  -Xs \
  -P \
  -R \
  -S replica_slot_1
```

**If using a custom data directory**, replace the `-D` path:

```bash
sudo -u postgres pg_basebackup \
  -h <PRIMARY_IP_OR_HOSTNAME> \
  -p 5432 \
  -U replicator \
  -D /mnt/postgresql/data \
  -Fp \
  -Xs \
  -P \
  -R \
  -S replica_slot_1
```

**Flag breakdown:**

| Flag | Meaning |
|------|---------|
| `-h` | Primary server hostname or IP |
| `-p` | Port (default 5432) |
| `-U` | Replication user we created in Section 2.2 |
| `-D` | Destination data directory on the replica |
| `-Fp` | Plain format (file-by-file copy, not a tarball) |
| `-Xs` | Stream WAL while backing up (keeps primary's WAL available) |
| `-P` | Show progress percentage |
| `-R` | Create `standby.signal` and write `primary_conninfo` to `postgresql.auto.conf` |
| `-S` | Use the replication slot we created in Section 2.4 |

You'll be prompted for the replicator user's password. Enter the password you set in Section 2.2.

For large databases, this can take a while. Progress is shown as a percentage.

### 3.4 Verify the Backup Completed

```bash
# Check that the data directory has content
ls -la /var/lib/postgresql/17/main/
# Or for custom data directory:
ls -la /mnt/postgresql/data/

# Should show: PG_VERSION, base, pg_wal, postgresql.auto.conf, standby.signal, etc.

# Verify standby.signal was created
ls -la /var/lib/postgresql/17/main/standby.signal
# Or:
ls -la /mnt/postgresql/data/standby.signal

# Verify primary_conninfo was written
cat /var/lib/postgresql/17/main/postgresql.auto.conf
# Or:
cat /mnt/postgresql/data/postgresql.auto.conf
```

The `postgresql.auto.conf` should contain something like:

```
primary_conninfo = 'user=replicator password=CHANGE_ME_STRONG_PASSWORD host=<PRIMARY_IP> port=5432 sslmode=prefer channel_binding=prefer'
primary_slot_name = 'replica_slot_1'
```

If `-R` didn't create `standby.signal` (rare, but can happen with older pg_basebackup versions), create it manually:

```bash
sudo -u postgres touch /var/lib/postgresql/17/main/standby.signal
```

---

## Section 4: Replica Server Setup

### 4.1 Install PostgreSQL (Same Version as Primary)

If you haven't already:

```bash
# Add PostgreSQL 17 APT repository (same as Section 1)
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update
sudo apt install -y postgresql-17
```

Verify the version matches the primary:

```bash
psql --version
# Must match: psql (PostgreSQL) 17.x
```

### 4.2 Stop PostgreSQL Service

```bash
sudo systemctl stop postgresql
# Or:
pg_ctlcluster 17 main stop
```

### 4.3 Clear/Clean the Data Directory

```bash
# Default data directory
sudo rm -rf /var/lib/postgresql/17/main/*

# Custom data directory (our EBS setup)
sudo rm -rf /mnt/postgresql/data/*
```

### 4.4 Restore the Base Backup

If you ran `pg_basebackup` directly on the replica (Section 3.3), the data is already in place. Skip to step 4.5.

If you created the backup on a different machine and need to copy it:

```bash
# On the primary or a staging machine, create a tar backup:
sudo -u postgres pg_basebackup \
  -h <PRIMARY_IP> \
  -p 5432 \
  -U replicator \
  -D /tmp/pg_backup \
  -Ft \
  -z \
  -P

# Transfer to replica:
rsync -avz /tmp/pg_backup/ replica-host:/tmp/pg_backup/

# On the replica, extract:
sudo -u postgres tar xzf /tmp/pg_backup/base.tar.gz -C /var/lib/postgresql/17/main/
sudo -u postgres tar xzf /tmp/pg_backup/pg_wal.tar.gz -C /var/lib/postgresql/17/main/pg_wal/
```

### 4.5 Create `standby.signal` (If Not Created by `-R`)

```bash
# Check if it exists first
ls /var/lib/postgresql/17/main/standby.signal 2>/dev/null || \
  sudo -u postgres touch /var/lib/postgresql/17/main/standby.signal

# For custom data directory:
ls /mnt/postgresql/data/standby.signal 2>/dev/null || \
  sudo -u postgres touch /mnt/postgresql/data/standby.signal
```

### 4.6 Configure `postgresql.conf` for Hot Standby

On the replica, edit the PostgreSQL config:

```bash
sudo nano /etc/postgresql/17/main/postgresql.conf
```

Add or uncomment these settings:

```ini
# Hot standby settings
hot_standby = on

# Connection to primary (if not already in postgresql.auto.conf from -R flag)
# primary_conninfo is usually set by pg_basebackup -R in postgresql.auto.conf
# Only set this manually if -R didn't work:
# primary_conninfo = 'host=<PRIMARY_IP> port=5432 user=replicator password=CHANGE_ME_STRONG_PASSWORD sslmode=require'

# Replication slot (if not already in postgresql.auto.conf)
# primary_slot_name = 'replica_slot_1'

# Reduce WAL receiver status interval for faster lag detection
wal_receiver_status_interval = 1s

# Hot standby feedback prevents vacuum conflicts
hot_standby_feedback = on
```

If using a custom data directory, make sure `data_directory` points to it:

```ini
data_directory = '/mnt/postgresql/data'
```

### 4.7 Start PostgreSQL on the Replica

```bash
sudo systemctl start postgresql
# Or:
pg_ctlcluster 17 main start
```

Check the logs for errors:

```bash
# Default log location on Ubuntu:
sudo tail -f /var/log/postgresql/postgresql-17-main.log

# Common success message:
# "entering standby mode"
# "started streaming from <PRIMARY_IP>"

# Common error messages:
# "could not connect to the primary server" → network or pg_hba.conf issue
# "FATAL: no pg_hba.conf entry for replication connection" → pg_hba.conf missing or wrong
# "FATAL: password authentication failed" → wrong password in primary_conninfo
```

### 4.8 Verify Replication Is Working

**On the primary**, check replication status:

```bash
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
```

You should see a row with:
- `pid` - the WAL sender process ID
- `state` - should be `streaming`
- `client_addr` - the replica's IP address
- `sent_lsn` and `write_lsn` - should be close or identical to the primary's current LSN

```bash
# Quick check: is the replica streaming?
sudo -u postgres psql -c "SELECT pid, state, client_addr, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

**On the replica**, check WAL receiver status:

```bash
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"
```

You should see:
- `status` = `streaming`
- `conn_info` showing the primary's address
- `sender_host` and `sender_port` matching the primary

```bash
# Quick check: is this server in recovery (replica mode)?
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# Should return: t (true)
```

**Test data replication:**

```bash
# On the primary, create a test table:
sudo -u postgres psql -d paymentform -c "CREATE TABLE _replication_test (id int, created_at timestamp default now()); INSERT INTO _replication_test VALUES (1);"

# On the replica, check it appeared:
sudo -u postgres psql -d paymentform -c "SELECT * FROM _replication_test;"

# Clean up (on primary):
sudo -u postgres psql -d paymentform -c "DROP TABLE _replication_test;"
```

---

## Section 5: Provider-Specific Notes

### AWS EC2

**Security Groups:**

The replica's security group needs outbound access to the primary on port 5432, and the primary's security group needs an inbound rule allowing the replica's IP/CIDR on port 5432.

```bash
# Example: Allow replica (10.0.2.0/24) to reach primary on 5432
# On the primary's security group, add:
# Type: Custom TCP, Port: 5432, Source: 10.0.2.0/24
```

**Cross-AZ replication:**

- Replicas in the same VPC but different AZs (e.g., `us-east-1a` to `us-east-1b`) use private IPs. No additional network config needed.
- Cross-AZ traffic incurs AWS data transfer charges ($0.01/GB).

**Cross-region replication:**

- Use VPC Peering or AWS Transit Gateway to connect VPCs in different regions.
- Consider Cloudflare Tunnel or WireGuard for encrypted cross-region traffic.
- Cross-region data transfer costs $0.02/GB (varies by region pair).

**Using private IPs:**

Always use private IPs for intra-VPC replication. The `pg_hba.conf` entry and `primary_conninfo` should reference the private IP:

```
# pg_hba.conf on primary
host    replication     replicator      10.0.0.0/16             md5
```

```
# primary_conninfo on replica
primary_conninfo = 'host=10.0.1.10 port=5432 user=replicator password=... sslmode=require'
```

### Hetzner Cloud

**Firewall rules:**

In the Hetzner Cloud Console, create a firewall rule allowing inbound TCP 5432 from the primary's IP:

```
# Hetzner Cloud Firewall
# Direction: Inbound
# Protocol: TCP
# Port: 5432
# Source: <PRIMARY_PUBLIC_IP>/32 or private network CIDR
```

**Private networks (vSwitch):**

Hetzner vSwitch provides private networking between servers. Use it for replication traffic:

1. Create a vSwitch network in the Hetzner Cloud Console
2. Add both primary and replica servers to the vSwitch
3. Assign private IPs (e.g., 10.10.0.1 for primary, 10.10.0.2 for replica)
4. Use these private IPs in `pg_hba.conf` and `primary_conninfo`

```bash
# Verify vSwitch connectivity (from replica):
ping 10.10.0.1

# Check which interface the vSwitch uses:
ip addr show | grep 10.10
```

**Public IP considerations:**

If you can't use vSwitch (e.g., cross-provider replication), use Cloudflare Tunnel or WireGuard to encrypt traffic. Never expose PostgreSQL on a public IP without encryption.

For our setup, Hetzner replicas connect to the AWS primary via Cloudflare Tunnel (`module.tunnel_db` in Terraform). The tunnel handles encryption and routing.

### DigitalOcean

**Managed Database replicas:**

DigitalOcean Managed Databases offer built-in read replicas. These are the easiest option if you're using DO Managed PostgreSQL:

```bash
# Create a read replica via doctl
doctl databases create-replica <database-id> --name replica-1 --region nyc1
```

Limitations: Managed replicas are same-provider only, and you don't get shell access to the replica.

**Self-hosted on Droplets:**

For cross-provider replication or full control, run PostgreSQL on a Droplet and follow this guide. Use DigitalOcean VPC (Private Network) for intra-region traffic:

1. Create a VPC in the same region as your Droplets
2. Assign Droplets to the VPC
3. Use the VPC private IP for replication traffic
4. Add a firewall rule allowing TCP 5432 from the primary's VPC IP

```bash
# Check Droplet's private IP:
curl -s http://169.254.169.254/metadata/v1.json | python3 -c "import sys,json; print(json.load(sys.stdin)['interfaces'][0]['ipv4']['private_address'])"
```

### GCP

**Cloud SQL read replicas:**

Google Cloud SQL supports read replicas natively:

```bash
# Create a read replica
gcloud sql instances create replica-1 --master-instance-name=primary-1 --region=us-east1
```

Limitations: Same project, same organization. No cross-cloud replication. You don't get shell access.

**Self-hosted on Compute Engine:**

For cross-cloud replication, run PostgreSQL on a GCE VM. Use VPC firewall rules:

```bash
# Create a firewall rule allowing replication traffic
gcloud compute firewall-rules create allow-pg-replication \
  --network=default \
  --allow=tcp:5432 \
  --source-ranges=<PRIMARY_IP>/32 \
  --direction=INGRESS
```

Use private IPs within the same VPC. For cross-cloud, set up VPN or use Cloudflare Tunnel.

### Azure

**Flexible Server geo-replicas:**

Azure Database for PostgreSQL Flexible Server supports geo-redundant backups and read replicas:

```bash
# Create a read replica
az postgres flexible-server replica create --replica-name replica-1 --source-server primary-1 --resource-group myRG --location eastus
```

Limitations: Same subscription, limited cross-cloud options.

**Self-hosted on Azure VMs:**

Use Azure Virtual Network (VNet) for private connectivity. Configure Network Security Groups (NSG) to allow TCP 5432 from the primary's VNet IP:

```bash
# Create NSG rule
az network nsg rule create \
  --resource-group myRG \
  --nsg-name myNSG \
  --name AllowPGReplication \
  --priority 200 \
  --direction Inbound \
  --protocol Tcp \
  --destination-port-range 5432 \
  --source-address-prefixes <PRIMARY_VNET_IP>/32
```

### On-Premise / Other Providers

**General networking:**

1. Ensure the replica can reach the primary on port 5432
2. Use `telnet` or `nc` to verify connectivity:

```bash
# From the replica, test connectivity to the primary:
nc -zv <PRIMARY_IP> 5432

# If this fails, check:
# - Firewall rules on both servers (iptables, ufw, cloud firewalls)
# - Network routing (VPN, tunnel, direct connection)
# - PostgreSQL listen_addresses (must not be 'localhost' only)
```

**Encryption:**

If replicating over the internet or an untrusted network, encrypt the connection. Options:

- **SSL in PostgreSQL**: Add `sslmode=require` to `primary_conninfo`
- **WireGuard VPN**: Lightweight, easy to set up, works across providers
- **Cloudflare Tunnel**: Already used in our setup for Hetzner replicas
- **SSH tunnel**: Quick and dirty, not ideal for production

```ini
# postgresql.auto.conf on replica - SSL connection
primary_conninfo = 'host=<PRIMARY_IP> port=5432 user=replicator password=... sslmode=require'
```

---

## Section 6: Monitoring Replication

### Check Replication Lag

**On the primary:**

```bash
# Overall replication status
sudo -u postgres psql -x -c "SELECT pid, state, client_addr, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
```

Key columns:
- `sent_lsn`: Last WAL position sent to the replica
- `replay_lsn`: Last WAL position the replica has applied
- `replay_lag`: Time the replica is behind (should be under a few seconds)
- `state`: Should be `streaming`

**On the replica:**

```bash
# WAL receiver status
sudo -u postgres psql -x -c "SELECT status, sender_host, sender_port, latest_end_lsn FROM pg_stat_wal_receiver;"

# Replication lag in bytes
sudo -u postgres psql -c "
  SELECT
    now() - pg_last_xact_replay_timestamp() AS replay_delay,
    pg_last_wal_receive_lsn() AS received_lsn,
    pg_last_wal_replay_lsn() AS replayed_lsn,
    pg_is_in_recovery() AS is_replica;
"
```

### Quick Health Check Script

Save this as `/usr/local/bin/check-replication.sh` on the primary:

```bash
#!/bin/bash
# Quick replication health check - run on the primary

echo "=== Replication Status ==="
sudo -u postgres psql -c "
  SELECT
    client_addr,
    state,
    sent_lsn,
    replay_lsn,
    replay_lag,
    sync_priority,
    sync_state
  FROM pg_stat_replication;
"

echo ""
echo "=== Replication Slots ==="
sudo -u postgres psql -c "
  SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn
  FROM pg_replication_slots;
"

echo ""
echo "=== WAL Generation Rate ==="
sudo -u postgres psql -c "
  SELECT
    pg_current_wal_lsn() AS current_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS total_wal_bytes;
"
```

```bash
sudo chmod +x /usr/local/bin/check-replication.sh
```

### Common Replication Issues and Fixes

**Replica falling behind:**

```bash
# Check if WAL is accumulating on the primary
sudo -u postgres psql -c "SELECT pg_current_wal_lsn();"
# Run again after 10 seconds
sudo -u postgres psql -c "SELECT pg_current_wal_lsn();"
# If LSN is advancing but replay_lsn on replica is stuck, the replica is slow

# Check disk I/O on the replica
iostat -x 5 3

# Check if the replica is under heavy read load (blocking replay)
sudo -u postgres psql -c "SELECT query, state, wait_event FROM pg_stat_activity WHERE state = 'active';"
```

**Replication slot not active:**

```bash
# Check slot status
sudo -u postgres psql -c "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"

# If a slot is inactive and the replica is disconnected, WAL accumulates
# Drop the slot if the replica is permanently gone:
sudo -u postgres psql -c "SELECT pg_drop_replication_slot('replica_slot_1');"
```

---

## Section 7: Promoting a Replica to Primary

Use this when the primary is down and you need the replica to take over.

### 7.1 Emergency Promotion

**On the replica:**

```bash
# Stop PostgreSQL
pg_ctlcluster 17 main stop

# Remove standby signal
rm -f /var/lib/postgresql/17/main/standby.signal
# Or for custom data directory:
rm -f /mnt/postgresql/data/standby.signal

# Remove primary_conninfo from postgresql.auto.conf
# This file was created by pg_basebackup -R
sed -i '/primary_conninfo/d' /var/lib/postgresql/17/main/postgresql.auto.conf
sed -i '/primary_slot_name/d' /var/lib/postgresql/17/main/postgresql.auto.conf

# Or for custom data directory:
sed -i '/primary_conninfo/d' /mnt/postgresql/data/postgresql.auto.conf
sed -i '/primary_slot_name/d' /mnt/postgresql/data/postgresql.auto.conf

# Start PostgreSQL as primary
pg_ctlcluster 17 main start

# Verify it's running as primary
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# Should return: f (false) - this server is now the primary
```

### 7.2 Update Application Connections

Point all application connection strings to the new primary:

```bash
# Update Laravel .env on backend servers
DB_HOST=<NEW_PRIMARY_IP>

# Update any connection poolers (PgBouncer, etc.)
# Update DNS records if using a hostname
# Update Cloudflare Tunnel configuration if applicable
```

If using a floating IP or DNS hostname for the database, update it to point to the new primary:

```bash
# Example: Update a DNS record
# In Cloudflare dashboard or via API:
# db.internal.paymentform.com → <NEW_PRIMARY_IP>
```

### 7.3 Re-establishing Replication After Promotion

Once the old primary is back online (or you've provisioned a new server), set it up as a replica of the new primary:

1. Follow Sections 2-4 of this guide, but with the **new primary** as the source
2. Create a new replication slot on the new primary:

```bash
# On the new primary
sudo -u postgres psql -c "SELECT pg_create_physical_replication_slot('replica_slot_2');"
```

3. Run `pg_basebackup` on the old primary (now replica) pointing to the new primary
4. Start the old primary in standby mode

**Alternative: Use `pg_rewind`** if the old primary's data directory is mostly intact:

```bash
# On the old primary (now being converted to a replica)
pg_ctlcluster 17 main stop

# Run pg_rewind to sync with the new primary
sudo -u postgres pg_rewind \
  --target-pgdata=/var/lib/postgresql/17/main \
  --source-server="host=<NEW_PRIMARY_IP> port=5432 user=postgres dbname=postgres"

# Create standby.signal
sudo -u postgres touch /var/lib/postgresql/17/main/standby.signal

# Configure primary_conninfo
echo "primary_conninfo = 'host=<NEW_PRIMARY_IP> port=5432 user=replicator password=CHANGE_ME_STRONG_PASSWORD'" | \
  sudo -u postgres tee -a /var/lib/postgresql/17/main/postgresql.auto.conf

echo "primary_slot_name = 'replica_slot_2'" | \
  sudo -u postgres tee -a /var/lib/postgresql/17/main/postgresql.auto.conf

# Start as replica
pg_ctlcluster 17 main start
```

`pg_rewind` is much faster than a full `pg_basebackup` when the data directories are mostly in sync.

---

## Section 8: Troubleshooting

### Connection Refused

**Symptom:** Replica logs show `could not connect to the primary server: Connection refused`

**Checks:**

```bash
# From the replica, test connectivity to the primary:
nc -zv <PRIMARY_IP> 5432

# If this fails:
# 1. Check PostgreSQL is running on the primary
sudo systemctl status postgresql

# 2. Check listen_addresses on the primary
sudo -u postgres psql -c "SHOW listen_addresses;"
# Should NOT be 'localhost' only

# 3. Check firewall on the primary
sudo ufw status          # Ubuntu UFW
sudo iptables -L -n      # iptables
# Or cloud provider firewall/security group rules

# 4. Check that PostgreSQL is actually listening on port 5432
sudo ss -tlnp | grep 5432
```

### Authentication Failures

**Symptom:** `FATAL: password authentication failed for user replicator` or `FATAL: no pg_hba.conf entry for replication connection`

**Checks:**

```bash
# 1. Verify pg_hba.conf has the replication entry
sudo -u postgres psql -c "SELECT * FROM pg_hba_file_rules WHERE database = '{replication}';"

# Or check the file directly:
grep replication /etc/postgresql/17/main/pg_hba.conf

# 2. Verify the replica's IP is in the allowed range
# The IP in pg_hba.conf must match the IP the replica connects FROM
# If the replica connects through a VPN/tunnel, use the tunnel IP, not the public IP

# 3. Test the replication user's password
sudo -u postgres psql -h <PRIMARY_IP> -U replicator -d replication -c "SELECT 1;"
# Enter password when prompted. If this fails, the password is wrong.

# 4. Check pg_hba.conf rule order
# PostgreSQL processes pg_hba.conf top to bottom. First match wins.
# Make sure no rule above yours is rejecting the connection.
```

### WAL Accumulation on Primary

**Symptom:** Disk space filling up on the primary. `pg_wal/` directory growing rapidly.

**Checks:**

```bash
# Check WAL directory size
du -sh /var/lib/postgresql/17/main/pg_wal/
# Or:
du -sh /mnt/postgresql/data/pg_wal/

# Check replication slots
sudo -u postgres psql -c "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"

# If a slot is inactive (active = f), WAL is being retained for a disconnected replica
# This will eventually fill the disk

# Check which slot is holding WAL
sudo -u postgres psql -c "
  SELECT
    slot_name,
    active,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS bytes_behind
  FROM pg_replication_slots;
"
```

**Fixes:**

```bash
# If the replica is permanently gone, drop the slot:
sudo -u postgres psql -c "SELECT pg_drop_replication_slot('replica_slot_1');"

# If the replica is temporarily disconnected but will reconnect:
# Increase wal_keep_size to give more buffer, and wait for the replica to reconnect

# If you need to free disk space immediately:
# 1. Drop inactive replication slots
# 2. Force a WAL switch and checkpoint
sudo -u postgres psql -c "SELECT pg_switch_wal();"
sudo -u postgres psql -c "CHECKPOINT;"
```

### Replication Lag Troubleshooting

**Symptom:** `replay_lag` in `pg_stat_replication` is growing, not shrinking.

**Diagnosis:**

```bash
# On the primary: check lag
sudo -u postgres psql -c "
  SELECT
    client_addr,
    state,
    replay_lag,
    write_lag,
    flush_lag,
    sent_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_behind
  FROM pg_stat_replication;
"

# On the replica: check if it's receiving WAL
sudo -u postgres psql -c "SELECT status, latest_end_lsn FROM pg_stat_wal_receiver;"
```

**Common causes and fixes:**

| Cause | Symptom | Fix |
|-------|---------|-----|
| Slow network | High `write_lag` | Check bandwidth between primary and replica |
| Heavy read load on replica | High `replay_lag`, low `write_lag` | Reduce read queries, add `hot_standby_feedback = on` |
| Long-running queries on replica | `replay_lag` spikes | Check `pg_stat_activity` for long queries |
| Disk I/O bottleneck on replica | All lag metrics high | Check `iostat`, upgrade disk |
| Network interruption | `state` not `streaming` | Check network, firewall, tunnel |

**Force catch-up:**

```bash
# On the replica, temporarily reduce read load:
# 1. Stop applications reading from the replica
# 2. Set a higher priority for WAL replay:
sudo -u postgres psql -c "ALTER SYSTEM SET max_standby_streaming_delay = '30s';"
sudo -u postgres psql -c "SELECT pg_reload_conf();"

# 3. Once caught up, revert:
sudo -u postgres psql -c "ALTER SYSTEM RESET max_standby_streaming_delay;"
sudo -u postgres psql -c "SELECT pg_reload_conf();"
```

### Replication Won't Start After pg_basebackup

**Symptom:** Replica starts but `pg_stat_wal_receiver` is empty, `pg_stat_replication` on primary shows no entry.

**Checks:**

```bash
# 1. Check standby.signal exists
ls -la /var/lib/postgresql/17/main/standby.signal
# Or:
ls -la /mnt/postgresql/data/standby.signal

# 2. Check primary_conninfo in postgresql.auto.conf
cat /var/lib/postgresql/17/main/postgresql.auto.conf
# Or:
cat /mnt/postgresql/data/postgresql.auto.conf

# 3. Check PostgreSQL logs
sudo tail -100 /var/log/postgresql/postgresql-17-main.log

# 4. Verify the data directory ownership
ls -la /var/lib/postgresql/17/main/ | head -5
# All files should be owned by postgres:postgres

# 5. Verify the data directory matches what PostgreSQL expects
sudo -u postgres psql -c "SHOW data_directory;"  # If you can start in single-user mode
# Or check postgresql.conf:
grep data_directory /etc/postgresql/17/main/postgresql.conf
```

### SSL/TLS Issues

**Symptom:** `SSL error` or `certificate verify failed` in replica logs.

**Fix:**

```bash
# If you don't need SSL (private network / VPN):
# In postgresql.auto.conf on the replica, set:
primary_conninfo = 'host=<PRIMARY_IP> port=5432 user=replicator password=... sslmode=disable'

# If you need SSL (public network):
# 1. Ensure the primary has SSL configured
sudo -u postgres psql -c "SHOW ssl;"
# Should be 'on'

# 2. Use sslmode=require (verify-ca and verify-full need certificates)
primary_conninfo = 'host=<PRIMARY_IP> port=5432 user=replicator password=... sslmode=require'
```

---

## Quick Reference: Common Commands

```bash
# Check if server is primary or replica
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
# f = primary, t = replica

# Check replication status (primary)
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

# Check WAL receiver (replica)
sudo -u postgres psql -c "SELECT * FROM pg_stat_wal_receiver;"

# Check replication slots
sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"

# Current WAL position
sudo -u postgres psql -c "SELECT pg_current_wal_lsn();"

# Replication lag in bytes (run on primary)
sudo -u postgres psql -c "
  SELECT
    client_addr,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"

# Promote replica to primary (emergency)
pg_ctlcluster 17 main promote

# Reload config without restart
sudo systemctl reload postgresql
# Or:
pg_ctlcluster 17 main reload

# Restart PostgreSQL (required for some config changes)
sudo systemctl restart postgresql
# Or:
pg_ctlcluster 17 main restart
```