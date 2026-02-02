# Local Build & Deploy — Cost-Optimized (Dev → Sandbox → Prod)

## Overview

This guide documents the new three-tier local build and deploy workflow that minimizes hosting costs while enabling fast developer iteration:

- Dev (local) — run everything locally with Docker and docker-compose ($0/month) 🛠️
- Sandbox (ECR) — push images to AWS ECR for a lightweight public sandbox (~$1–3/month) 🌱
- Prod (ECR) — production images in ECR with lifecycle policies (~$2–5/month) 🚀

Target total monthly cost: $3–8/month across sandbox + prod.

Related files and scripts (repository paths):

- make targets: `Makefile` (dev-build, dev-up, dev-local, build-local, ecr-login, push-to-ecr, local-deploy)
- local compose: `local/docker-compose.dev.yml`
- local build scripts: `./scripts/build-local-dev.sh`, `./scripts/build-local.sh`
- ECR helpers: `./scripts/push-to-ecr.sh`, `./scripts/deploy-to-env.sh`


## Prerequisites

- Docker (Engine & CLI) — https://docs.docker.com/get-docker/
- docker-compose (v2 recommended) — used for local dev
- AWS CLI configured with credentials and default region — `aws configure`
- OpenTofu (tofu) — infrastructure tooling used for deploys
- IAM permissions for ECR and pushing images (ecr:* push/pull, iam:PassRole if needed)


## Image Tagging Strategy

- Tag format for builds:
  - `{service}:{env}-{timestamp}` e.g. `renderer:dev-20260102123000`
  - `{service}:{git-sha}` e.g. `renderer:abc1234` (useful for reproducible deploys)

Reference a specific version in deployment manifests by using the full tag (e.g. `renderer:prod-20260102...` or `renderer:abcdef1`).


## Dev Workflow (Local — $0)

Purpose: fastest feedback loop for development and debugging. All images run locally with docker-compose, no cloud costs.

Steps:

1. Build images locally

```bash
# From iaac/ root
make dev-build
# Or run script directly
./scripts/build-local-dev.sh
```

Expected output:

```
✔ Building renderer image: renderer:dev-<timestamp>
✔ Built 3 images: api, renderer, dashboard
```

2. Start with docker-compose

```bash
# Start containers in background (rebuilds if necessary)
make dev-up
# Single command build + run
make dev-local
```

Internals: `make dev-up` runs `docker-compose -f local/docker-compose.dev.yml up -d --build` which references locally built images.

Troubleshooting (common dev issues):

- Containers restart loops: `docker-compose logs <service>`, inspect entrypoint errors or missing env vars from .env
- Port conflicts: ensure `localhost` ports configured in `local/docker-compose.dev.yml` are free
- Build cache issues: `docker-compose build --no-cache` or `docker image prune -f`

Warnings:
- Local runs are destructive to local volumes if `docker-compose down -v` is used — back up data if necessary.


## Sandbox / Prod Workflow (ECR — $1–5/month)

Purpose: host images in AWS ECR for lightweight sandbox and production deployments.

1. Build images locally for sandbox/prod

```bash
# Build for specific ENV (sandbox or prod)
make build-local ENV=sandbox
# or call directly
./scripts/build-local.sh sandbox
```

2. Authenticate with ECR

```bash
# Uses Makefile helper which runs AWS CLI + docker login
make ecr-login REGION=us-east-1

# Equivalent manual command:
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

Common authentication errors:
- `no basic auth credentials`: ensure `aws sts get-caller-identity` returns an account ID and your AWS credentials are valid.
- Expired credentials: re-run `aws configure` or refresh STS session.

3. Push images to ECR

```bash
# Push using the helper (tags with timestamp)
make push-to-ecr ENV=sandbox REGION=us-east-1
# Or call script directly
./scripts/push-to-ecr.sh --tag sandbox-$(date +%Y%m%d%H%M%S) --region us-east-1
```

Expected output:

```
Pushing image renderer:sandbox-20260102...
Digest: sha256:...
✔ Pushed renderer to <account>.dkr.ecr.us-east-1.amazonaws.com/renderer:sandbox-20260102...
```

4. Deploy from ECR

```bash
# Full local deploy workflow: build → push → apply deploy steps (uses scripts/deploy-to-env.sh)
make local-deploy ENV=sandbox
# Or run scripts directly
./scripts/deploy-to-env.sh sandbox
```

The deploy script will update OpenTofu variables / ECS task definitions to reference the new image tag and apply the change.


## Rollback Procedures

List available image versions in ECR:

```bash
aws ecr list-images --repository-name renderer --region us-east-1 --output json
# Or list images with details
aws ecr describe-images --repository-name renderer --region us-east-1 --query 'imageDetails[].[imageTags, imagePushedAt]'
```

Deploy a previous version (example):

```bash
# Edit your deployment manifest or use the helper script to point to a specific tag
# Example: force deploy renderer:abcdef1
./scripts/deploy-to-env.sh sandbox renderer:abcdef1
# Or manually update Terraform/OpenTofu variable and apply
tofu plan -var='image_tag=abcdef1' -var-file=infrastructure/environments/sandbox/terraform.tfvars -out=tfplan-sandbox
tofu apply tfplan-sandbox
```

Emergency rollback (fastest):

```bash
# If you keep previous task definition revision, you can use AWS CLI to update service to use previous revision
aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment --region us-east-1
# If using Terraform, revert variable and run make plan/apply with the previous tag
```


## Cost Optimization Details

ECR lifecycle policies and storage retention are the primary levers to control cost.

- Default ECR storage cost is low but can grow if you keep many large images. With lifecycle policies you can automatically expire old tags.

Sample lifecycle policy (keep latest 30 images, expire untagged older than 7 days):

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images older than 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Keep only latest 30 tagged images per tag prefix",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["sandbox-", "prod-"],
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": { "type": "expire" }
    }
  ]
}
```

Expected monthly costs (approx):

| Environment | Registry | Estimated Storage | Monthly Cost |
|-------------|----------|-------------------:|-------------:|
| Dev         | Local    | 0 GB               | $0.00        |
| Sandbox     | ECR      | 1–5 GB             | $1–3         |
| Prod        | ECR      | 2–10 GB            | $2–5         |
| Total (target) | —     | —                  | $3–8         |

Tips to minimize costs further:

- Use multi-stage builds and slim base images to reduce image sizes
- Apply ECR lifecycle policies aggressively (shorter retention for sandbox)
- Remove unused tags and images regularly: `aws ecr batch-delete-image` or `docker image prune`
- Prefer local dev images; push to ECR only when necessary for sandbox/prod testing


## Troubleshooting

ECR authentication errors:

- Symptom: `no basic auth credentials` or `denied: requested access to the resource is denied`
  - Ensure `make ecr-login` runs successfully and `aws sts get-caller-identity` returns your account
  - Check IAM permissions: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`

Docker build failures:

- Symptom: build logs show failure in RUN step
  - Re-run build with no cache: `docker build --no-cache -t <tag> .`
  - Verify network issues (proxy, DNS) and builder context size

Image push timeouts:

- Symptom: pushes fail or stall at large layers
  - Increase Docker client timeout, ensure stable network, or use smaller images
  - Use `aws ecr` region nearest to CI runner

Deployment verification steps:

```bash
# Verify image exists in ECR
aws ecr describe-images --repository-name renderer --region us-east-1 --image-ids imageTag=renderer:prod-20260102...

# Verify ECS service is using the expected image
aws ecs describe-task-definition --task-definition <task-def> | jq .containerDefinitions[0].image

# Check service stability
aws ecs list-tasks --cluster <cluster> --service-name <service>
aws ecs describe-tasks --cluster <cluster> --tasks <task-arn>
```


## Cross-References

- Full cost deep-dive: `docs/COST-OPTIMIZATION.md`
- CI/CD automation: `docs/deployment-guide.md`
- Local compose files: `local/docker-compose.dev.yml`
- Build & push scripts: `./scripts/*.sh`


---

If anything here is unclear, open an issue or contact the infrastructure team in #infrastructure.
