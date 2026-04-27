# Infrastructure as Code - PaymentForm

OpenTofu/Terraform infrastructure with AWS backend, Cloudflare Containers for client/renderer, and Cloudflare R2 for storage.

## Quick Start

```bash
# 1. Set environment variables
cp .envrc.example .envrc
# Edit .envrc with your secrets
source .envrc

# 2. Initialize
make init

# 3. Review changes
make plan

# 4. Deploy
make apply
```

## Common Commands

| Command | Description | Example |
|---------|-------------|---------|
| `make plan` | Generate execution plan | `make plan` |
| `make apply` | Apply planned changes | `make apply` |
| `make cost-estimate` | Estimate monthly costs | `make cost-estimate` |
| `make state-list` | List all resources | `make state-list` |
| `make output` | Show outputs | `make output` |
| `make validate` | Validate configuration | `make validate` |
| `make fmt` | Format all .tf files | `make fmt` |

## Structure

```
iaac/
├── providers/              # Cloud provider modules
│   ├── aws/
│   │   ├── compute/       # EC2 backend
│   │   ├── networking/    # VPC, subnets
│   │   ├── security/      # Security groups
│   │   └── volume/        # EBS volumes
│   └── cloudflare/
│       ├── containers/    # Cloudflare Containers
│       ├── dns/           # DNS, WAF, rate limiting
│       ├── r2/            # R2 buckets + SSL config
│       ├── kv/            # KV namespaces
│       └── status/        # Status page worker
│
├── environments/
│   └── prod/              # Single production environment (us-east-1)
│       ├── main.tf        # All modules wired together
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
│
├── .envrc.example          # Environment variables template
└── Makefile                # Common commands (make help)
```

## Architecture

```
                                    ┌─────────────────────────────┐
                                    │      Cloudflare             │
                                    │       Containers            │
                                    │                             │
                                    │  ┌───────────────────────┐  │
┌─────────────────┐                 │  │  Client Container     │  │
│   Cloudflare    │                 │  │  (Next.js SSR)        │  │
│      DNS        │─────────────────│  └───────────────────────┘  │
│                 │                 │  ┌───────────────────────┐  │
│  - api.*        │─────────────────│  │  Renderer Container   │  │
│  - app.*        │                 │  │  (Next.js + Caddy)    │  │
│  - *.renderer.* │                 │  └───────────────────────┘  │
└─────────────────┘                 └─────────────────────────────┘
                                              ▲
┌─────────────────┐   ┌───────────────────────┼───────────────────────┐
│      AWS        │   │              Cloudflare R2 (Multi-Region)     │
│   (Backend)     │   │  ┌─────────────────────────────────────────┐  │
│                 │   │  │  - paymentform-uploads-us (wnam)       │  │
│  ┌───────────┐  │   │  │  - paymentform-uploads-eu (weur)       │  │
│  │   EC2     │  │◄──┤  │  - paymentform-uploads-ap (apac)       │  │
│  │  (API)    │  │   │  │  - SSL Config Bucket                   │  │
│  └───────────┘  │   │  └─────────────────────────────────────────┘  │
│  ┌───────────┐  │   └───────────────────────────────────────────────┘
│  │   SSM     │◄─┘
│  │  Secrets  │         ┌──────────────────────────────┐
│  └───────────┘         │       Cloudflare KV          │
└─────────────────┘      │  - Tenants Namespace         │
                         └──────────────────────────────┘
┌─────────────────┐
│    Hetzner      │
│   (Backend)     │
│                 │
│  ┌───────────┐  │
│  │  cx22     │  │
│  │  (hel1)   │  │
│  └───────────┘  │
│  ┌───────────┐  │
│  │  cx22     │  │
│  │  (sin1)   │  │
│  └───────────┘  │
└─────────────────┘
```

## Key Features

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Client** | Cloudflare Containers | Next.js SSR dashboard |
| **Renderer** | Cloudflare Containers | Next.js + Caddy for wildcard TLS |
| **Backend (AWS)** | EC2 Auto Scaling Group | Laravel/FrankenPHP API (us-east-1) |
| **Backend (EU/AP)** | Hetzner Cloud | Laravel/FrankenPHP API (hel1, sin1) |
| **Storage** | Cloudflare R2 | Multi-region file uploads (US/EU/AP) + SSL certs |
| **CDN** | Cloudflare Workers | Regional CDN workers (cdn-us/eu/ap) |
| **Secrets** | AWS SSM | Encrypted parameters |
| **KV Store** | Cloudflare KV | Tenant session/state storage |
| **Deploy** | GitHub Actions | Automated image deploy to running instances |

## Prerequisites

- OpenTofu/Terraform >= 1.8
- AWS CLI configured
- Cloudflare API token (permissions: Workers Scripts/Routes, Container Registry, R2, DNS)

## Required Variables

```bash
# Cloudflare
export TF_VAR_cloudflare_api_token="..."
export TF_VAR_cloudflare_account_id="..."
export TF_VAR_cloudflare_zone_id="..."

# Containers
export TF_VAR_client_container_image="ghcr.io/org/client:latest"
export TF_VAR_renderer_container_image="ghcr.io/org/renderer:latest"
export TF_VAR_ghcr_token="..."

# R2 SSL Config
export TF_VAR_ssl_storage_access_key_id="..."
export TF_VAR_ssl_storage_secret_access_key="..."

# Database
export TF_VAR_neon_database_url="..."
export TF_VAR_turso_api_token="..."
```

See `.envrc.example` for full list.

## Container Images

**Client (Next.js SSR):**
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY .next/standalone ./
COPY .next/static ./.next/static
EXPOSE 3000
CMD ["node", "server.js"]
```

**Renderer (Next.js + Caddy):**
```dockerfile
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=client /app/.next/standalone /srv/app
EXPOSE 443
```

## R2 SSL Config

Renderer stores Caddy certificates in R2 for persistence across restarts:

```bash
R2_SSL_BUCKET_NAME=sandbox-paymentform-ssl-config
R2_SSL_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_SSL_ACCESS_KEY_ID=...
R2_SSL_SECRET_ACCESS_KEY=...
```

## Cost Estimate

Run `make cost-estimate` to get current infrastructure costs.

| Resource | Monthly Cost |
|----------|--------------|
| AWS Backend EC2 (ASG) | ~$15-30/mo |
| Hetzner Backend (hel1) | ~$5-10/mo |
| Hetzner Backend (sin1) | ~$5-10/mo |
| Cloudflare Containers | ~$10-15/mo |
| Cloudflare R2 (3 regions) | ~$2-5/mo |
| **Total** | **~$37-70/mo** |

**Additional:** Neon DB (~$0-19/mo)

## Migration from Amplify/EC2

1. Build and push container images to GHCR
2. Deploy with `enable_cloudflare_containers = true`
3. Test containers (run parallel to existing infra)
4. Update DNS to point to containers
5. Decommission Amplify apps and renderer EC2

## Documentation

- `terraform.tfvars.example` - Variable examples
- `.envrc.example` - Environment variables template

## Support

Check provider directories (`providers/aws/*/`, `providers/cloudflare/*/`) for component-specific documentation.

## Backend Auto-Deploy

Backend deploys use GitHub Actions workflows to push release-tagged images to running EC2 and Hetzner instances.

### Workflows

| Workflow | File | Trigger |
|----------|------|---------|
| Build | `build-and-push-image.yml` | Push to main, PR, release, workflow_dispatch |
| Deploy | `deploy-release.yml` | After build-and-push-image succeeds, manual dispatch |

### How It Works

1. Release published → `build-and-push-image` builds → `deploy-release` deploys to instances (automatic chain)
2. Manual deploy → Run workflow dispatch with image tag
3. AWS: Uses SSM SendCommand to run deploy script on EC2 instances
4. Hetzner: SSH into each server and run deploy script
5. Deploy script:
   - Detects environment (EC2 vs Hetzner)
   - Pulls new image
   - Restarts container (Docker or systemd)
   - Health check with rollback on failure

### Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC auth |
| `GHCR_TOKEN` | GitHub token with `read:packages` scope for GHCR pull |
| `HETZNER_BACKEND_IPS` | Space-separated list of Hetzner backend IPs |
| `HETZNER_SSH_KEY` | Private SSH key for Hetzner root access |

### AWS IAM Setup

#### 1. Create OIDC Identity Provider

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4e98bab03faadb97b34396831e3780aea1 \
  --client-id-list sts.amazonaws.com
```

#### 2. Create IAM Role for GitHub Actions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:bit-apps-pro/paymentform-backend:ref:refs/tags/*"
        }
      }
    }
  ]
}
```

#### 3. Attach Required Policies

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ssm:SendCommand",
        "ssm:GetCommandInvocation"
      ],
      "Resource": "*"
    }
  ]
}
```

### Hetzner Setup

1. Add SSH public key to each Hetzner server:
   ```bash
   ssh-copy-id -i deploy_key.pub root@SERVER_IP
   ```

2. Store private key in GitHub secret `HETZNER_SSH_KEY`

3. Tag backend instances with `Service=backend` for AWS discovery

### Manual Deploy

```bash
# GitHub CLI
gh workflow run deploy-release.yml -f image_tag=v1.2.3
```

Or use GitHub web UI: Actions → Deploy Release → Run workflow

### Rollback

If deploy fails, manually run previous version:

```bash
# On affected server
curl -fsSL https://raw.githubusercontent.com/bit-apps-pro/paymentform-backend/main/.github/scripts/deploy.sh | bash -s 'PREVIOUS_TAG' backend
```
