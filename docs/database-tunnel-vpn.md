# Database Tunnel & VPN Guide

Connecting to the PostgreSQL primary on AWS (us-east-1) from Hetzner servers (hel1, sin1) and other remote locations.

## Section 1: Understanding the Options

| Option | Latency (EU→us-east-1) | Complexity | Security | Cost |
|--------|----------------------|------------|----------|------|
| Cloudflare Tunnel | ~100-130ms | Low | High | Free |
| WireGuard VPN | ~90-110ms | Medium | High | Free |
| AWS Site-to-Site VPN | ~95-115ms | High | High | ~$36/mo+ |
| Tailscale / ZeroTier | ~95-120ms | Low | High | Free tier / $5/mo |
| Direct public IP + TLS | ~90-110ms | Low | Low | Free |
| Transit Gateway + VPN | ~95-115ms | Very high | High | ~$73/mo+ |

### Key Takeaway

Trans-Atlantic latency is physics-limited. No tunnel or VPN will make packets cross the ocean faster than ~90ms round trip. The real reasons to use a tunnel or VPN are **security** (never expose port 5432 to the internet) and **reliability** (stable connection, automatic reconnection). If you need lower read latency in EU/AP, the answer is **read replicas**, not a different tunnel.

### Option Details

**1. Cloudflare Tunnel (cloudflared)**

Current setup. The `cloudflared` daemon on the DB server makes an outbound connection to Cloudflare's edge. Remote servers connect via a Cloudflare CNAME. Traffic is encrypted end to end. Adds ~10-20ms over direct because packets route through Cloudflare's network before reaching the DB server.

- Pros: Zero open inbound ports, easy setup, free, Cloudflare handles TLS
- Cons: Extra latency hop, depends on Cloudflare availability, limited control over routing

**2. WireGuard VPN**

Modern kernel-space VPN. Runs as a peer-to-peer tunnel between AWS and Hetzner servers. Minimal overhead (crypto is fast, UDP-based). Same latency as direct IP because it's a straight UDP tunnel between the two endpoints.

- Pros: Lowest overhead, fast, simple config, kernel performance, free
- Cons: Manual key management, no built-in NAT traversal (needs at least one side with public IP), manual monitoring

**3. AWS Site-to-Site VPN**

AWS-managed IPSec VPN. Creates a Virtual Private Gateway in your VPC and a Customer Gateway for the remote network. Uses IKEv2/IPSec. AWS charges per connection hour and per GB.

- Pros: AWS-managed, integrates with VPC routing, redundant tunnels by default
- Cons: Expensive for small setups (~$36/mo per connection), complex to configure, IPSec overhead

**4. Transit Gateway + VPN**

For connecting multiple remote sites (e.g., both hel1 and sin1) to AWS. Adds a Transit Gateway as a central hub. Overkill for two sites unless you plan to add many more.

- Pros: Scales to many sites, central routing
- Cons: Most expensive option, complex, overkill for 2-3 sites

**5. Direct Public IP + TLS**

Open PostgreSQL port 5432 to the world, require SSL, restrict source IPs in the security group. Technically works but violates security best practices. PostgreSQL authentication is not designed for public exposure.

- Pros: Simplest setup, lowest latency
- Cons: Attack surface, no defense in depth, PostgreSQL protocol is not hardened for public internet exposure

**6. Tailscale / ZeroTier**

Mesh VPN overlays built on WireGuard (Tailscale) or custom protocol (ZeroTier). Each node authenticates to a central control plane and establishes direct peer-to-peer connections. Tailscale uses DERP relay servers as fallback.

- Pros: Easiest setup, automatic NAT traversal, mesh topology, ACLs built in
- Cons: Depends on third-party service, DERP relay adds latency if direct connection fails, free tier limits

---

## Section 2: Option A — Cloudflare Tunnel (Current Setup)

### How It Works

```
Hetzner Server ──► Cloudflare Edge ──► Cloudflare Network ──► cloudflared (DB server) ──► PostgreSQL:5432
```

1. `cloudflared` runs on the AWS DB server as a daemon
2. It establishes an **outbound** connection to Cloudflare's edge network
3. Cloudflare assigns a CNAME (e.g., `db-tunnel.paymentform.com`) that routes to this tunnel
4. Hetzner servers connect to PostgreSQL using this CNAME as the host
5. Traffic flows: Hetzner → Cloudflare edge → Cloudflare backbone → cloudflared → localhost:5432

### Configuration Steps

**On the DB server (AWS):**

1. Install cloudflared:
   ```bash
   # Debian/Ubuntu
   curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
   sudo dpkg -i cloudflared.deb
   ```

2. Authenticate:
   ```bash
   cloudflared tunnel login
   ```

3. Create a tunnel:
   ```bash
   cloudflared tunnel create db-tunnel
   # Note the tunnel ID from the output
   ```

4. Create the config file at `/etc/cloudflared/config.yml`:
   ```yaml
   tunnel: <TUNNEL_ID>
   credentials-file: /etc/cloudflared/<TUNNEL_ID>.json

   ingress:
     - hostname: db-tunnel.paymentform.com
       service: postgresql://localhost:5432
     - service: http_status:404
   ```

5. Create DNS record:
   ```bash
   cloudflared tunnel route dns db-tunnel db-tunnel.paymentform.com
   ```

6. Install as systemd service:
   ```bash
   sudo cloudflared service install
   sudo systemctl enable cloudflared
   sudo systemctl start cloudflared
   ```

**On Hetzner servers:**

Set the database host in your application config:
```env
DB_HOST=db-tunnel.paymentform.com
DB_PORT=5432
```

The Terraform module `module.tunnel_db` manages this configuration. Check `iaac/providers/cloudflare/` for the tunnel resource definitions.

### Latency Considerations

- Each request traverses: Hetzner → Cloudflare edge (nearest PoP) → Cloudflare backbone → Cloudflare edge (near AWS) → cloudflared → PostgreSQL
- This adds 2-3 extra network hops compared to a direct connection
- Typical overhead: 10-20ms per query
- For batch operations or long-running queries, the overhead is negligible
- For many small queries (ORM patterns), the cumulative overhead matters

### When to Keep Using It

- You value simplicity over latency optimization
- Your query patterns are mostly write-heavy (writes must go to primary anyway)
- You don't want to manage VPN infrastructure
- Cloudflare availability meets your SLA requirements

### When to Upgrade

- Read-heavy workloads from EU/AP that need lower latency
- You need more control over the network path
- Cloudflare outages have caused downtime
- You want to set up read replicas that need a stable, low-overhead tunnel

---

## Section 3: Option B — WireGuard VPN (Recommended for Low Latency)

WireGuard gives you a direct UDP tunnel between AWS and Hetzner with minimal overhead. Same latency as a direct connection, but with encryption and authentication.

### Architecture

```
AWS (us-east-1)                          Hetzner (hel1)
┌─────────────────┐                      ┌─────────────────┐
│  PostgreSQL      │                      │  Backend App     │
│  10.0.1.10      │                      │                  │
│       │         │                      │       │         │
│  ┌────┴────┐    │    WireGuard UDP     │  ┌────┴────┐    │
│  │  wg0    │◄───┼──────────────────────┼─►│  wg0    │    │
│  │10.200.1.1│   │    (51820/udp)        │  │10.200.1.2│   │
│  └─────────┘    │                      │  └─────────┘    │
└─────────────────┘                      └─────────────────┘
```

### Step 1: Install WireGuard on AWS Primary DB Server

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y wireguard

# Verify
wg --version
```

### Step 2: Generate Key Pairs

Generate keys on **each server**. Never copy private keys between machines.

**On AWS (server):**
```bash
# Generate private key and derive public key
wg genkey | tee /etc/wireguard/aws_private.key | wg pubkey > /etc/wireguard/aws_public.key

# View keys (you'll need these for the peer configs)
cat /etc/wireguard/aws_private.key
cat /etc/wireguard/aws_public.key
```

**On Hetzner hel1 (client):**
```bash
wg genkey | tee /etc/wireguard/hel1_private.key | wg pubkey > /etc/wireguard/hel1_public.key

cat /etc/wireguard/hel1_private.key
cat /etc/wireguard/hel1_public.key
```

**On Hetzner sin1 (client):**
```bash
wg genkey | tee /etc/wireguard/sin1_private.key | wg pubkey > /etc/wireguard/sin1_public.key

cat /etc/wireguard/sin1_private.key
cat /etc/wireguard/sin1_public.key
```

### Step 3: Configure AWS Side (wg0.conf)

Create `/etc/wireguard/wg0.conf` on the AWS DB server:

```ini
[Interface]
# AWS WireGuard IP
Address = 10.200.1.1/24
# Port WireGuard listens on
ListenPort = 51820
# AWS private key (from Step 2)
PrivateKey = <AWS_PRIVATE_KEY>

# PostUp/PostDown rules for NAT forwarding
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# --- Hetzner hel1 peer ---
[Peer]
# hel1 public key
PublicKey = <HEL1_PUBLIC_KEY>
# hel1's WireGuard IP
AllowedIPs = 10.200.1.2/32
# hel1 public IP (for initial connection)
Endpoint = <HEL1_PUBLIC_IP>:51820
# Keep connection alive (important for NAT)
PersistentKeepalive = 25

# --- Hetzner sin1 peer ---
[Peer]
# sin1 public key
PublicKey = <SIN1_PUBLIC_KEY>
# sin1's WireGuard IP
AllowedIPs = 10.200.1.3/32
# sin1 public IP
Endpoint = <SIN1_PUBLIC_IP>:51820
PersistentKeepalive = 25
```

### Step 4: Configure Hetzner Side (wg0.conf)

**On Hetzner hel1**, create `/etc/wireguard/wg0.conf`:

```ini
[Interface]
# hel1 WireGuard IP
Address = 10.200.1.2/24
# hel1 private key
PrivateKey = <HEL1_PRIVATE_KEY>
# Listen port (optional, needed if AWS needs to reach hel1)
ListenPort = 51820

[Peer]
# AWS public key
PublicKey = <AWS_PUBLIC_KEY>
# Route all WireGuard traffic to AWS
AllowedIPs = 10.200.1.0/24
# AWS DB server public IP
Endpoint = <AWS_PUBLIC_IP>:51820
PersistentKeepalive = 25
```

**On Hetzner sin1**, create `/etc/wireguard/wg0.conf`:

```ini
[Interface]
# sin1 WireGuard IP
Address = 10.200.1.3/24
# sin1 private key
PrivateKey = <SIN1_PRIVATE_KEY>
ListenPort = 51820

[Peer]
# AWS public key
PublicKey = <AWS_PUBLIC_KEY>
AllowedIPs = 10.200.1.0/24
# AWS DB server public IP
Endpoint = <AWS_PUBLIC_IP>:51820
PersistentKeepalive = 25
```

### Step 5: Enable IP Forwarding on AWS Server

The AWS server needs to forward packets between WireGuard and the local network.

```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Make it persistent across reboots
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-wireguard.conf
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf
```

### Step 6: Configure Firewall Rules

**AWS Security Group** (add inbound rule):

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| Custom UDP | UDP | 51820 | `<HEL1_PUBLIC_IP>/32` | WireGuard from hel1 |
| Custom UDP | UDP | 51820 | `<SIN1_PUBLIC_IP>/32` | WireGuard from sin1 |

Also allow PostgreSQL access from the WireGuard subnet:

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| PostgreSQL | TCP | 5432 | 10.200.1.0/24 | PostgreSQL via WireGuard |

**Hetzner Firewall** (allow outbound WireGuard):

```bash
# On each Hetzner server, allow UDP 51820 outbound
sudo ufw allow out 51820/udp
sudo ufw allow out on wg0

# If using iptables instead:
sudo iptables -A OUTPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -A OUTPUT -o wg0 -j ACCEPT
```

**AWS server local firewall** (if ufw/iptables is active):

```bash
# Allow WireGuard traffic
sudo ufw allow 51820/udp
sudo ufw allow in on wg0
sudo ufw allow out on wg0

# Allow PostgreSQL from WireGuard subnet only
sudo ufw allow from 10.200.1.0/24 to any port 5432
```

### Step 7: Start WireGuard on Both Sides

**On AWS:**
```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Verify
sudo wg show wg0
```

**On each Hetzner server:**
```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Verify
sudo wg show wg0
```

Expected `wg show` output:
```
interface: wg0
  public key: <LOCAL_PUBLIC_KEY>
  private key: (hidden)
  listening port: 51820

peer: <REMOTE_PUBLIC_KEY>
  endpoint: <REMOTE_IP>:51820
  allowed ips: 10.200.1.0/24
  latest handshake: 5 seconds ago
  transfer: 1.2 KiB received, 3.4 KiB sent
```

If `latest handshake` shows a recent timestamp, the tunnel is up.

### Step 8: Test Connectivity

**Ping test:**
```bash
# From Hetzner hel1 to AWS
ping -c 5 10.200.1.1

# From AWS to Hetzner hel1
ping -c 5 10.200.1.2
```

**PostgreSQL connection test:**
```bash
# From Hetzner, connect via WireGuard IP
psql -h 10.200.1.1 -U postgres -d paymentform -c "SELECT 1;"

# Verify SSL is required
psql "host=10.200.1.1 dbname=paymentform user=postgres sslmode=require" -c "SELECT ssl_is_used();"
```

**Traceroute comparison:**
```bash
# Via public IP (for reference)
traceroute <AWS_PUBLIC_IP>

# Via WireGuard
traceroute 10.200.1.1
# Should show a single hop through the WireGuard tunnel
```

### Step 9: Make It Persistent

WireGuard uses `wg-quick@wg0` as a systemd service. It starts on boot automatically once enabled (Step 7).

Additional hardening for persistence:

```bash
# Ensure the service starts after network is up
sudo systemctl enable wg-quick@wg0

# Verify it's enabled
sudo systemctl is-enabled wg-quick@wg0
# Should output: enabled
```

If you need WireGuard to start before the application tries to connect to the database, add a dependency:

```bash
# For systemd services that depend on the DB connection
sudo systemctl edit your-app.service
```

Add:
```ini
[Unit]
After=wg-quick@wg0.service
Requires=wg-quick@wg0.service
```

### Step 10: Update Application DB_HOST

Change the application configuration to use the WireGuard IP instead of the Cloudflare Tunnel CNAME.

**Before (Cloudflare Tunnel):**
```env
DB_HOST=db-tunnel.paymentform.com
DB_PORT=5432
```

**After (WireGuard):**
```env
DB_HOST=10.200.1.1
DB_PORT=5432
```

Then restart the application:
```bash
sudo systemctl restart your-app
# Or for Docker:
docker compose restart backend
```

Verify the connection is using WireGuard:
```bash
# On the Hetzner server, check active connections
ss -tnp | grep 5432
# Should show connection to 10.200.1.1:5432
```

---

## Section 4: Option C — AWS Site-to-Site VPN

AWS-managed IPSec VPN between your VPC and Hetzner's network. Uses a Virtual Private Gateway on the AWS side and a Customer Gateway + IPSec daemon (strongSwan) on the Hetzner side.

### Architecture

```
AWS VPC (us-east-1)                     Hetzner (hel1)
┌──────────────────┐                    ┌──────────────────┐
│  Virtual Private  │    IPSec VPN       │  Customer Gateway  │
│  Gateway (VGW)   │◄──────────────────►│  (strongSwan)     │
│                  │    2 tunnels        │                    │
│  Route Table     │    (AWS provides   │  Route to VPC      │
│  10.0.0.0/16     │     2 for HA)      │  subnets           │
└──────────────────┘                    └──────────────────┘
```

### Step 1: Create Customer Gateway

```bash
aws ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip <HEL1_PUBLIC_IP> \
  --bgp-asn 65000 \
  --tag-specifications "ResourceType=customer-gateway,Tags=[{Key=Name,Value=hetzner-hel1}]"
```

Note the `CustomerGatewayId` from the output.

### Step 2: Create Virtual Private Gateway

```bash
aws ec2 create-vpn-gateway \
  --type ipsec.1 \
  --tag-specifications "ResourceType=vpn-gateway,Tags=[{Key=Name,Value=paymentform-vgw}]"

# Attach to VPC
aws ec2 attach-vpn-gateway \
  --vpn-gateway-id <VGW_ID> \
  --vpc-id <VPC_ID>
```

### Step 3: Create VPN Connection

```bash
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id <CGW_ID> \
  --vpn-gateway-id <VGW_ID> \
  --options '{"StaticRoutesOnly": true}'

# Get the configuration (strongSwan format)
aws ec2 describe-vpn-connections \
  --vpn-connection-ids <VPN_CONNECTION_ID> \
  --query 'VpnConnections[0].VpnTelemetry' \
  --output text
```

Download the IPSec configuration:
```bash
aws ec2 describe-vpn-connections \
  --vpn-connection-ids <VPN_CONNECTION_ID> \
  --query 'VpnConnections[0].VgwTelemetry' \
  --output json > vpn-config.json
```

### Step 4: Configure strongSwan on Hetzner

```bash
# Install strongSwan
sudo apt install -y strongswan strongswan-pki libcharon-extra-plugins
```

Create `/etc/ipsec.conf`:
```conf
conn aws-vpn
  authby=secret
  left=<HEL1_PRIVATE_IP>
  leftid=<HEL1_PUBLIC_IP>
  leftsubnet=10.200.2.0/24
  right=<AWS_VPN_PUBLIC_IP_1>
  rightid=<AWS_VPN_PUBLIC_IP_1>
  rightsubnet=10.0.0.0/16
  ike=aes256-sha2_256-modp2048
  esp=aes256-sha2_256
  keyexchange=ikev2
  auto=start
  dpdaction=restart
  keylife=3600
  ikelifetime=86400
```

Create `/etc/ipsec.secrets`:
```conf
# PSK from AWS VPN configuration
<HEL1_PUBLIC_IP> <AWS_VPN_PUBLIC_IP_1> : PSK "<PRE_SHARED_KEY>"
```

```bash
# Start strongSwan
sudo systemctl enable strongswan
sudo systemctl start strongswan
```

### Step 5: Update Route Tables

```bash
# Add route for Hetzner subnet through the VGW
aws ec2 create-route \
  --route-table-id <ROUTE_TABLE_ID> \
  --destination-cidr-block 10.200.2.0/24 \
  --gateway-id <VGW_ID>

# Enable route propagation
aws ec2 enable-vgw-route-propagation \
  --route-table-id <ROUTE_TABLE_ID> \
  --gateway-id <VGW_ID>
```

### Step 6: Test Connectivity

```bash
# From Hetzner, ping AWS VPC subnet
ping -c 5 10.0.1.10

# Test PostgreSQL
psql -h 10.0.1.10 -U postgres -d paymentform -c "SELECT 1;"
```

### Cost Note

AWS Site-to-Site VPN pricing (as of 2025):
- $0.05/hour per VPN connection (~$36/month)
- $0.09/GB data transfer
- Two connections for HA = ~$72/month minimum

This is significantly more expensive than WireGuard or Tailscale for the same result.

---

## Section 5: Option D — Tailscale (Simplest Alternative)

Tailscale is a mesh VPN built on WireGuard. It handles NAT traversal, key management, and ACLs automatically. Easiest option if you don't want to manage WireGuard configs.

### Architecture

```
AWS (us-east-1)                    Hetzner (hel1)           Hetzner (sin1)
┌──────────────┐                   ┌──────────────┐         ┌──────────────┐
│  PostgreSQL   │                   │  Backend App  │         │  Backend App  │
│              │                   │              │         │              │
│  Tailscale   │◄── Direct P2P ──►│  Tailscale   │         │  Tailscale   │
│  100.x.y.1   │   WireGuard      │  100.x.y.2   │         │  100.x.y.3   │
└──────────────┘                   └──────────────┘         └──────────────┘
        │                                │                         │
        └──────── Control Plane ─────────┘────────────────────────┘
              (key exchange, ACLs, DERP relay fallback)
```

### Step 1: Install Tailscale on All Nodes

**On AWS DB server:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=<AUTH_KEY> --hostname=aws-db-primary
```

**On Hetzner hel1:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=<AUTH_KEY> --hostname=hetzner-hel1
```

**On Hetzner sin1:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=<AUTH_KEY> --hostname=hetzner-sin1
```

### Step 2: Authenticate and Join Tailnet

If not using auth keys, authenticate each node interactively:
```bash
sudo tailscale up
# Follow the URL to authenticate in your browser
```

Verify all nodes are connected:
```bash
tailscale status
# Should show all three nodes as "active"
```

### Step 3: Enable Subnet Routing on AWS Node

If you want Hetzner servers to access the entire AWS VPC subnet (not just the DB server):

```bash
# On AWS DB server
sudo tailscale up --authkey=<AUTH_KEY> --advertise-routes=10.0.0.0/16 --hostname=aws-db-primary
```

Then approve the subnet routes in the Tailscale admin console (https://login.tailscale.com/admin/routes).

### Step 4: Configure ACLs for PostgreSQL Port Access

In the Tailscale admin console, edit the ACL policy:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["hetzner-hel1", "hetzner-sin1"],
      "dst": ["aws-db-primary:5432"]
    }
  ],
  "ssh": []
}
```

This restricts access so Hetzner servers can only reach PostgreSQL on the DB server, nothing else.

### Step 5: Update DB_HOST to Use Tailscale IP

```bash
# Get the Tailscale IP of the AWS DB server
tailscale ip -4 aws-db-primary
# e.g., 100.64.0.1
```

Update application config:
```env
DB_HOST=100.64.0.1
DB_PORT=5432
```

Restart the application:
```bash
sudo systemctl restart your-app
```

### Step 6: Test Connectivity

```bash
# From Hetzner, ping the DB server via Tailscale
ping -c 5 100.64.0.1

# Test PostgreSQL connection
psql -h 100.64.0.1 -U postgres -d paymentform -c "SELECT 1;"

# Verify it's going through Tailscale
tailscale ping aws-db-primary
# Should show "via DERP" or direct connection with latency
```

### Tailscale Pricing

- Free tier: Up to 3 users, 100 devices
- Starter: $5/user/month
- Enough for this use case on the free tier

---

## Section 6: Latency Comparison

### Expected Round-Trip Latency (EU to us-east-1)

| Method | Typical RTT | Overhead vs Direct | Notes |
|--------|-------------|-------------------|-------|
| Direct public IP | 90-110ms | Baseline | No encryption, not recommended |
| Cloudflare Tunnel | 100-130ms | +10-20ms | Extra hops through Cloudflare edge network |
| WireGuard VPN | 90-110ms | ~0-2ms | Kernel-space crypto, UDP, near-zero overhead |
| AWS Site-to-Site VPN | 95-115ms | +5-10ms | IPSec overhead, AWS routing |
| Tailscale | 95-120ms | +5-15ms | Direct P2P when possible; DERP relay adds latency |
| ZeroTier | 95-120ms | +5-15ms | Similar to Tailscale |

### The Honest Answer About Latency

**Trans-Atlantic latency is physics-limited.** Light in fiber travels at roughly 2/3 the speed of light. The physical distance between Helsinki and Virginia is ~7,000 km. Even in a perfect fiber with zero routing overhead, the minimum RTT is ~70ms. Real world routing adds 20-40ms on top.

Switching from Cloudflare Tunnel to WireGuard saves ~10-20ms per query. That's meaningful for high-frequency small queries, but it won't transform a 100ms experience into a 20ms one.

### What Actually Reduces Latency for Reads

If read latency in EU/AP is the problem, the solution is **read replicas**:

1. **Stream replication from AWS primary to Hetzner** (via WireGuard or Cloudflare Tunnel)
2. **Route read queries to the local replica** in EU/AP
3. **Route write queries to the primary** in us-east-1

This cuts read latency from ~100ms to ~1-5ms (local network). Write latency stays at ~100ms because writes must go to the primary.

The Hetzner servers already run PostgreSQL replicas connected via Cloudflare Tunnel. The tunnel is fine for replication (which is async and tolerant of latency). For application reads, point `DB_READ_HOST` at the local replica instead of the primary.

```env
# Application config for Hetzner hel1
DB_HOST=10.200.1.1          # Primary (for writes) via WireGuard
DB_READ_HOST=localhost      # Local replica (for reads)
DB_READ_HOST=db-tunnel.paymentform.com  # Or via tunnel if no WireGuard
```

---

## Section 7: Security Best Practices

### Never Expose PostgreSQL Port 5432 to the Public Internet

PostgreSQL's authentication protocol is not designed for public internet exposure. Even with TLS and strong passwords, the attack surface is unnecessary when VPN options exist.

**What not to do:**
```bash
# NEVER do this
sudo ufw allow 5432/tcp from 0.0.0.0/0
# Or in AWS: never open security group 5432 to 0.0.0.0/0
```

**What to do instead:**
- Use WireGuard, Tailscale, or Cloudflare Tunnel
- If you must allow direct access, restrict to specific IPs:
  ```bash
  # Only allow specific IPs
  sudo ufw allow from <KNOWN_IP> to any port 5432
  ```

### Always Use TLS/SSL for PostgreSQL Connections

Even inside a VPN, require SSL for PostgreSQL connections:

In `postgresql.conf`:
```
ssl = on
ssl_cert_file = '/etc/ssl/certs/postgresql.crt'
ssl_key_file = '/etc/ssl/private/postgresql.key'
```

In `pg_hba.conf`:
```
# Require SSL for all non-local connections
hostssl  all  all  10.200.1.0/24  md5
hostssl  all  all  100.64.0.0/10   md5
```

### Restrict VPN/Tunnel Access to Specific IPs and CIDRs

**WireGuard:** Use `AllowedIPs` to limit which IPs each peer can reach:
```ini
# Only allow access to the DB server's WireGuard IP
AllowedIPs = 10.200.1.1/32
```

**Tailscale:** Use ACLs to restrict port access:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["hetzner-*"],
      "dst": ["aws-db-primary:5432"]
    }
  ]
}
```

**AWS Security Groups:** Restrict inbound 51820/udp to known Hetzner IPs only.

### Rotate VPN Keys Regularly

**WireGuard key rotation:**
```bash
# Generate new key pair
wg genkey | tee /etc/wireguard/new_private.key | wg pubkey > /etc/wireguard/new_public.key

# Update peer configs with new public key
# Then restart WireGuard
sudo systemctl restart wg-quick@wg0
```

Schedule key rotation every 90 days. Use a cron job or calendar reminder.

**Tailscale** handles key rotation automatically.

### Monitor VPN Tunnel Health

**WireGuard monitoring:**
```bash
# Check tunnel status
sudo wg show wg0

# Check last handshake (should be recent)
sudo wg show wg0 | grep "latest handshake"

# Monitor traffic
sudo wg show wg0 transfer
```

**Tailscale monitoring:**
```bash
# Check status
tailscale status

# Check connectivity
tailscale ping aws-db-primary
```

**Automated health check script** (add to cron):
```bash
#!/bin/bash
# /usr/local/bin/check-wireguard.sh
LAST_HANDSHAKE=$(sudo wg show wg0 | grep "latest handshake" | awk '{print $3}')

if [ -z "$LAST_HANDSHAKE" ]; then
  echo "WireGuard tunnel is DOWN" | logger -t wireguard
  sudo systemctl restart wg-quick@wg0
fi
```

```bash
# Run every minute
echo "* * * * * root /usr/local/bin/check-wireguard.sh" | sudo tee /etc/cron.d/wireguard-check
```

---

## Section 8: Switching from Tunnel to VPN

Migration checklist for moving from Cloudflare Tunnel to WireGuard (or Tailscale).

### Pre-Migration

- [ ] Set up WireGuard/Tailscale alongside the existing Cloudflare Tunnel
- [ ] Verify both paths work simultaneously
- [ ] Document current `DB_HOST` value and backup application config
- [ ] Schedule a maintenance window (connections will briefly drop during switch)

### Migration Steps

1. **Set up VPN alongside existing tunnel**

   Follow the WireGuard (Section 3) or Tailscale (Section 5) setup guide. Do not remove the Cloudflare Tunnel yet. Both can run in parallel.

2. **Test connectivity via VPN**

   ```bash
   # Test WireGuard
   psql -h 10.200.1.1 -U postgres -d paymentform -c "SELECT 1;"

   # Or test Tailscale
   psql -h 100.64.0.1 -U postgres -d paymentform -c "SELECT 1;"
   ```

3. **Update application config (DB_HOST)**

   ```bash
   # On each Hetzner server, update .env or environment variable
   # Before:
   DB_HOST=db-tunnel.paymentform.com

   # After (WireGuard):
   DB_HOST=10.200.1.1

   # After (Tailscale):
   DB_HOST=100.64.0.1
   ```

4. **Restart applications**

   ```bash
   # For Docker-based deployments
   docker compose restart backend

   # For systemd services
   sudo systemctl restart your-app
   ```

5. **Verify replication and connections work**

   ```bash
   # Check PostgreSQL connections
   sudo -u postgres psql -c "SELECT * FROM pg_stat_activity WHERE client_addr = '10.200.1.0/24';"

   # Check replication status
   sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"

   # Verify application is connecting via VPN
   ss -tnp | grep 5432
   ```

6. **Monitor for 24-48 hours**

   Watch for:
   - Connection timeouts or drops
   - Replication lag spikes
   - Application error rates
   - WireGuard tunnel stability (`wg show`)

7. **Remove Cloudflare Tunnel (optional)**

   Only after confirming the VPN is stable:

   ```bash
   # On AWS DB server
   sudo systemctl stop cloudflared
   sudo systemctl disable cloudflared

   # Remove Cloudflare DNS record
   cloudflared tunnel cleanup db-tunnel
   cloudflared tunnel delete db-tunnel

   # Remove Terraform module (if managed by IaC)
   # Remove module.tunnel_db from your Terraform config
   ```

### Rollback Plan

If the VPN causes issues after switching:

```bash
# 1. Revert DB_HOST to Cloudflare Tunnel
DB_HOST=db-tunnel.paymentform.com

# 2. Restart application
docker compose restart backend

# 3. Investigate VPN issues
sudo wg show wg0
sudo journalctl -u wg-quick@wg0 --since "1 hour ago"
```

The Cloudflare Tunnel should remain configured until you're confident the VPN is stable. Keep it as a fallback for at least a week.

---

## Recommendations

| Scenario | Recommended Option |
|----------|-------------------|
| Simple setup, few servers, want minimal ops | **Tailscale** |
| Full control, no third-party dependency | **WireGuard** |
| Already using Cloudflare, latency not critical | **Cloudflare Tunnel** (current) |
| Multiple sites, AWS-native infra, budget allows | **AWS Site-to-Site VPN** |
| Need read latency reduction in EU/AP | **Read replicas** (not a tunnel change) |

**Primary recommendation:** WireGuard for self-managed control with minimal overhead. Tailscale if you want the easiest setup and don't mind a third-party dependency.

**For latency:** The real solution for EU/AP read latency is PostgreSQL read replicas in those regions, not a different tunnel type. The tunnel type affects security and reliability, not trans-Atlantic physics.