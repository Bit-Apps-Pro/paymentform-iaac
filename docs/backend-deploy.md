# Backend & Renderer Deployment

## Architecture

| Region | Service | Platform | Module |
|--------|---------|----------|--------|
| us-east-1 | Backend API | EC2 ASG (t4g.small) | `module.paymentform_backend` |
| us-east-1 | Renderer | EC2 ASG (t4g.small) | `module.paymentform_renderer` |
| eu-hel1 | Backend API | Hetzner cx22 | `module.hetzner_backend_hel1` |
| ap-sin1 | Backend API | Hetzner cx22 | `module.hetzner_backend_sin1` |

Container images are pulled from GHCR (`ghcr.io`). The backend runs Laravel/FrankenPHP, the renderer runs Next.js + Caddy for wildcard TLS.

## Deploy Flow

### Automated (GitHub Actions)

1. Release tag published triggers `build-and-push-image.yml`.
2. Image built and pushed to GHCR.
3. `deploy-release.yml` runs automatically on success.
4. AWS instances: SSM `SendCommand` runs deploy script on EC2 instances tagged `Service=backend`.
5. Hetzner instances: SSH into each server in `HETZNER_BACKEND_IPS`, run deploy script.
6. Deploy script detects environment, pulls new image, restarts container, runs health check. On failure, rolls back to previous image.

### Manual

```bash
# Via GitHub CLI
gh workflow run deploy-release.yml -f image_tag=v1.2.3

# Or via GitHub web UI: Actions → Deploy Release → Run workflow
```

### Manual on a Single Server

```bash
# SSH into the instance and run
curl -fsSL https://raw.githubusercontent.com/bit-apps-pro/paymentform-backend/main/.github/scripts/deploy.sh | bash -s 'v1.2.3' backend
```

## Required GitHub Secrets

| Secret | Value |
|--------|-------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC auth to AWS |
| `GHCR_TOKEN` | GitHub token with `read:packages` scope |
| `HETZNER_BACKEND_IPS` | Space-separated list of Hetzner backend IPs |
| `HETZNER_SSH_KEY` | Private SSH key for Hetzner root access |

## Container Image Variables

Images are controlled via Terraform variables in `environments/prod/main.tf`:

| Variable | Module | Description |
|----------|--------|-------------|
| `var.backend_container_image` | `paymentform_backend`, `hetzner_backend_hel1`, `hetzner_backend_sin1` | Backend API image |
| `var.renderer_container_image` | `paymentform_renderer`, `hetzner_backend_hel1`, `hetzner_backend_sin1` | Renderer image |
| `var.client_container_image` | `paymentform_client` | Client dashboard image |

### Quick Image Update

```bash
# Backend only
make update-backend IMAGE_TAG=v1.2.3

# Renderer only
make update-renderer IMAGE_TAG=v1.2.3

# Client only
make update-client IMAGE_TAG=v1.2.3

# All at once
make update-all IMAGE_TAG=v1.2.3
```

These run `tofu apply -var="..._container_image=TAG" -auto-approve`.

## Container Environment Variables

Env vars are injected via `container_env_vars` in each Terraform module. Key variables:

### Backend

- `DB_HOST` / `DB_HOST_WRITE` / `DB_HOST_READ` — PostgreSQL endpoints (primary/replica)
- `AWS_BUCKET`, `AWS_BUCKET_US`, `AWS_BUCKET_EU`, `AWS_BUCKET_AP` — R2 bucket names
- `AWS_ENDPOINT` — `https://{account_id}.r2.cloudflarestorage.com`
- `AWS_USE_PATH_STYLE_ENDPOINT` — `true` (R2 requires path-style)
- `REDIS_HOST`, `REDIS_PASSWORD` — Valkey/Redis connection
- `SQS_PREFIX` — SQS queue prefix for Laravel queues

### Renderer

- `SSL_STORAGE_BUCKET_NAME` — R2 bucket for Caddy TLS certs
- `SSL_STORAGE_BUCKET_HOST` — R2 bucket domain
- `SSL_STORAGE_BUCKET_ACCESS_KEY_ID` / `SSL_STORAGE_BUCKET_ACCESS_KEY` — R2 credentials for cert storage
- `CLOUDFLARE_API_TOKEN` — Used by Caddy for wildcard DNS challenge (ACME)
- `DOMAIN` — `paymentform.io`
- `KV_STORE_NAMESPACE_ID` / `KV_STORE_API_TOKEN` — Tenant validation

## Rollback

If a deploy fails or causes issues:

1. Re-run the workflow with the previous working tag:
   ```bash
   gh workflow run deploy-release.yml -f image_tag=v1.2.2
   ```

2. Or on a specific server:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/bit-apps-pro/paymentform-backend/main/.github/scripts/deploy.sh | bash -s 'v1.2.2' backend
   ```

3. For Terraform-managed image updates, revert the variable and re-apply:
   ```bash
   cd environments/prod
   tofu apply -var="backend_container_image=ghcr.io/org/backend:v1.2.2" -auto-approve
   ```

## AWS IAM for Deploy

The GitHub Actions deploy workflow authenticates to AWS via OIDC. The IAM role (`AWS_DEPLOY_ROLE_ARN`) must have:

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:DescribeInstances",
    "ssm:SendCommand",
    "ssm:GetCommandInvocation"
  ],
  "Resource": "*"
}
```

EC2 instances must be tagged with `Service=backend` for SSM discovery.

## Hetzner Setup

1. Add SSH public key to each Hetzner server:
   ```bash
   ssh-copy-id -i deploy_key.pub root@SERVER_IP
   ```

2. Store private key in GitHub secret `HETZNER_SSH_KEY`.

3. The deploy workflow SSHs into each IP listed in `HETZNER_BACKEND_IPS` and runs the deploy script.