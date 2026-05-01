# Deployment Guide

## Prerequisites

- OpenTofu >= 1.8 (`tofu` binary on PATH)
- AWS CLI configured with credentials (`aws configure` or env vars)
- Cloudflare API token with permissions: Workers Scripts/Routes, Container Registry, R2, DNS
- Hetzner API token (for EU/AP backend servers)
- GitHub CLI (`gh`) for manual workflow dispatch

### Environment Variables

Copy and fill the template:

```bash
cp .envrc.example .envrc
# Edit .envrc with your secrets
source .envrc
```

Required variables:

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

State is stored in S3 backend: `paymentform-terraform-state` bucket, key `prod/terraform.tfstate`, with DynamoDB locking via `paymentform-terraform-locks`.

## First-Time Bootstrap

On a fresh environment with no state:

```bash
make init
make plan
# Review the plan carefully
make apply
```

`make init` runs `tofu init` inside `environments/prod/`, downloading providers and initializing the S3 backend.

If this is the very first apply, all resources will be created. This includes VPC, subnets, security groups, EC2 instances, NLBs, R2 buckets, Cloudflare Workers, DNS records, and Hetzner servers.

## Incremental Apply

For subsequent changes after initial bootstrap:

```bash
make plan    # generates tfplan in environments/prod/
make apply   # applies the saved tfplan
```

Always review the plan output before applying. The plan file (`tfplan`) is stored in `environments/prod/` and applied on the next `make apply`.

## Deploying Specific Modules

Use the `-target` flag to apply changes to a single module without touching others:

```bash
cd environments/prod

# Deploy only the database module
tofu apply -target=module.postgres_database

# Deploy only CDN workers
tofu apply -target=module.paymentform_storage_cdn

# Deploy only backend compute
tofu apply -target=module.paymentform_backend

# Deploy only Hetzner EU backend
tofu apply -target=module.hetzner_backend_hel1

# Deploy only DNS
tofu apply -target=module.paymenform_dns
```

Multiple targets:

```bash
tofu apply -target=module.postgres_database -target=module.paymentform_cache
```

## Updating Container Images

The Makefile provides shortcuts for rolling container images:

```bash
# Update backend to a specific tag
make update-backend IMAGE_TAG=v1.2.3

# Update client
make update-client IMAGE_TAG=v1.2.3

# Update renderer
make update-renderer IMAGE_TAG=v1.2.3

# Update all at once
make update-all IMAGE_TAG=v1.2.3
```

These run `tofu apply -var="..._container_image=TAG" -auto-approve`.

## Rollback Procedure

### Infrastructure Rollback

If an apply breaks something:

1. Identify the last known good state:
   ```bash
   cd environments/prod
   tofu state list   # check current resources
   ```

2. Revert the Terraform source to the previous commit:
   ```bash
   git revert HEAD
   ```

3. Re-apply:
   ```bash
   make plan
   make apply
   ```

### Backend Container Rollback

If a backend deploy fails, SSH into the affected server and run the previous version:

```bash
# On the EC2 or Hetzner instance
curl -fsSL https://raw.githubusercontent.com/bit-apps-pro/paymentform-backend/main/.github/scripts/deploy.sh | bash -s 'PREVIOUS_TAG' backend
```

Or trigger via GitHub CLI:

```bash
gh workflow run deploy-release.yml -f image_tag=v1.2.2
```

### Database Rollback

See [database-operations.md](database-operations.md) for backup restore procedures.

## GitHub Actions Deploy Workflow

### Workflows

| Workflow | File | Trigger |
|----------|------|---------|
| Build | `build-and-push-image.yml` | Push to main, PR, release, workflow_dispatch |
| Deploy | `deploy-release.yml` | After build succeeds, or manual dispatch |

### How It Works

1. Release published triggers `build-and-push-image`, which builds the container image and pushes to GHCR.
2. On success, `deploy-release` runs automatically.
3. AWS instances: SSM `SendCommand` runs the deploy script on EC2 instances tagged `Service=backend`.
4. Hetzner instances: SSH into each server listed in `HETZNER_BACKEND_IPS` and run the deploy script.
5. The deploy script detects environment, pulls the new image, restarts the container, and runs a health check with rollback on failure.

### Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC auth |
| `GHCR_TOKEN` | GitHub token with `read:packages` scope |
| `HETZNER_BACKEND_IPS` | Space-separated list of Hetzner backend IPs |
| `HETZNER_SSH_KEY` | Private SSH key for Hetzner root access |

### Manual Deploy

```bash
gh workflow run deploy-release.yml -f image_tag=v1.2.3
```

Or via GitHub web UI: Actions, Deploy Release, Run workflow.

## Other Makefile Commands

| Command | Description |
|---------|-------------|
| `make validate` | Validate configuration |
| `make fmt` | Format all .tf files |
| `make output` | Show outputs |
| `make state-list` | List all resources in state |
| `make refresh` | Refresh state from real infrastructure |
| `make destroy` | Destroy all infrastructure (5s warning) |
| `make clean` | Remove .terraform directories and lock files |
| `make cost-estimate` | Run infracost estimation (requires infracost CLI) |
| `make security-full` | Run checkov + tfsec scans |