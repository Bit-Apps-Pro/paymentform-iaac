# Payment Form Infrastructure as Code

This repository contains the Infrastructure as Code (IaC) for the Payment Form application, supporting multi-region deployment with separate hosting for backend, client, and renderer components.

## Quick Links

- 📋 [Architecture Documentation](./docs/architecture.md)
- 🚀 [Deployment Guide](./docs/deployment-guide.md)
- 🔐 [Secrets Management](./docs/secrets-management.md)
- 📊 [Monitoring & Logging](./docs/monitoring-logging.md)
- 🔄 [Disaster Recovery](./docs/disaster-recovery.md)

## Architecture Overview

The infrastructure is designed with the following regional distribution:

- **US East (Virginia)**: Backend services and primary database
- **EU West (Ireland)**: Client dashboard  
- **Asia Pacific (Singapore)**: Multi-tenant renderer
- **Multi-region databases**: Aurora primary with read replicas, Turso multi-region
- **Multi-region storage**: S3 with cross-region replication

## Components

- **OpenTofu** for infrastructure provisioning (>= v1.6)
- **Ansible** for configuration management (>= v2.10)
- **LocalStack** for local testing and development
- **CloudWatch** for monitoring and logging
- Separate state management per region/account
- Local deployment capabilities with Docker Compose

## Directory Structure

```
iaac/
├── tofu/                        # Infrastructure as Code
│   ├── main.tf                  # Root Terraform configuration
│   ├── variables.tf             # Root variables definition
│   ├── backend/                 # Backend service infrastructure
│   │   ├── us-east-1/          # US East region configuration
│   │   └── variables.tf
│   ├── client/                  # Client service infrastructure
│   │   ├── eu-west-1/          # EU West region configuration
│   │   └── variables.tf
│   ├── renderer/                # Renderer service infrastructure
│   │   ├── ap-southeast-1/      # Asia Pacific region configuration
│   │   └── variables.tf
│   ├── databases/               # Database infrastructure
│   │   ├── primary/             # Primary Aurora cluster
│   │   ├── replicas/            # Aurora read replicas
│   │   └── turso/               # Turso multi-region setup
│   ├── storage/                 # Storage infrastructure
│   │   ├── primary/             # Primary S3 bucket
│   │   └── replicas/            # S3 replica buckets
│   ├── networking/              # Networking infrastructure
│   │   ├── global/              # Global resources (Route53, ACM, WAF)
│   │   └── regional/            # Regional networking
│   ├── modules/                 # Reusable modules
│   │   ├── ecs-service/        # ECS service module
│   │   ├── rds-cluster/        # RDS cluster module
│   │   ├── s3-bucket/          # S3 bucket module
│   │   ├── vpc/                # VPC module
│   │   └── alb/                # Application Load Balancer module
│   └── localstack/              # LocalStack configurations
│
├── environments/                # Environment configuration files
│   ├── dev.tfvars              # Development environment
│   ├── staging.tfvars          # Staging environment
│   └── prod.tfvars             # Production environment
│
├── ansible/                     # Configuration management
│   ├── playbooks/              # Deployment playbooks
│   │   ├── deploy-backend.yml
│   │   ├── deploy-client.yml
│   │   ├── deploy-renderer.yml
│   │   └── rollback.yml
│   ├── roles/                  # Ansible roles
│   │   ├── backend/
│   │   ├── client/
│   │   ├── renderer/
│   │   ├── database/
│   │   └── common/
│   ├── inventory/              # Inventory files
│   │   ├── production/
│   │   └── local/
│   └── vars/                   # Variable files
│       ├── common.yml          # Common variables
│       ├── dev.yml             # Dev environment variables
│       ├── staging.yml         # Staging environment variables
│       └── prod.yml            # Production environment variables
│
├── local/                      # Local development configurations
│   ├── docker-compose.backend.yml
│   ├── docker-compose.client.yml
│   ├── docker-compose.renderer.yml
│   ├── docker-compose.full.yml
│   ├── localstack.yml
│   ├── coredns.conf/
│   ├── localstack-config.hcl
│   └── data/
│
├── scripts/                    # Utility scripts
│   ├── validate.sh             # Validate configurations (NEW)
│   ├── rollback.sh             # Rollback infrastructure changes (NEW)
│   ├── state-management.sh     # Manage Terraform state (NEW)
│   ├── deploy-local.sh         # Deploy locally
│   ├── localstack.sh           # LocalStack management
│   └── test-localstack.sh      # Test LocalStack setup
│
├── docs/                       # Documentation
│   ├── architecture.md         # Architecture overview
│   ├── deployment-guide.md     # Deployment procedures
│   ├── disaster-recovery.md    # DR procedures (NEW)
│   ├── secrets-management.md   # Secrets management guide (NEW)
│   └── monitoring-logging.md   # Monitoring & logging setup (NEW)
│
└── README.md                   # This file
```

## Prerequisites

- **AWS CLI** (v2+) configured with appropriate permissions
- **OpenTofu** (>= v1.6) or Terraform (>= 1.0)
- **Ansible** (>= 2.10) with python-boto3
- **Docker** (>= 24.0) and **Docker Compose** (>= 2.20)
- **Git** for version control
- **jq** for JSON processing (optional but recommended)

### Setup

```bash
# AWS CLI
aws --version

# OpenTofu
tofu version

# Ansible
ansible --version

# Docker
docker --version
docker compose version

# Verify AWS credentials
aws sts get-caller-identity
```

## Deployment

### Quick Start

```bash
# 1. Validate configurations
./scripts/validate.sh

# 2. Deploy to local environment
./scripts/deploy-local.sh full

# 3. Access services
# Backend API:    http://api.local.paymentform.com:8000
# Client:         http://localhost:3000
# Renderer:       http://localhost:3001
# Health check:   http://api.local.paymentform.com:8000/health
```

### Multi-Region Deployment (Production)

#### Step 1: Prepare Environment

```bash
# Copy and customize environment variables
cp environments/prod.tfvars.example environments/prod.tfvars
# Edit prod.tfvars with your values:
# - domain_name
# - db_username / db_password (store in AWS Secrets Manager)
# - AWS account IDs for each region
```

#### Step 2: Initialize and Plan

```bash
cd tofu/

# Initialize Terraform with state management
tofu init

# Show planned infrastructure changes
tofu plan -var-file=../environments/prod.tfvars
```

#### Step 3: Deploy Infrastructure

```bash
# Deploy networking first
tofu apply -target=module.networking -var-file=../environments/prod.tfvars

# Deploy databases
tofu apply -target=module.database_cluster -var-file=../environments/prod.tfvars

# Deploy storage
tofu apply -target=module.storage_bucket -var-file=../environments/prod.tfvars

# Deploy services
tofu apply -var-file=../environments/prod.tfvars
```

#### Step 4: Configure and Deploy Applications

```bash
cd ../ansible/

# Deploy backend
ansible-playbook -i inventory/production playbooks/deploy-backend.yml -e "environment=prod"

# Deploy client
ansible-playbook -i inventory/production playbooks/deploy-client.yml -e "environment=prod"

# Deploy renderer
ansible-playbook -i inventory/production playbooks/deploy-renderer.yml -e "environment=prod"
```

### LocalStack Integration (Testing)

For testing infrastructure code locally without AWS costs:

```bash
# Start LocalStack
./scripts/localstack.sh start

# Deploy infrastructure to LocalStack
./scripts/localstack.sh deploy

# Run tests
./scripts/localstack.sh test

# Clean up
./scripts/localstack.sh destroy
./scripts/localstack.sh stop
```

## Operations & Management

### Validation & Testing

Before deploying, always validate your configurations:

```bash
# Comprehensive validation
./scripts/validate.sh

# This checks:
# ✓ Terraform syntax and formatting
# ✓ Ansible playbook syntax and linting
# ✓ Docker Compose configurations
# ✓ Environment files
# ✓ Hardcoded secrets
# ✓ File permissions
# ✓ Documentation completeness
```

### State Management

Safely manage Terraform state:

```bash
# Backup current state
./scripts/state-management.sh backup prod

# List available backups
./scripts/state-management.sh list

# Restore from backup
./scripts/state-management.sh restore .state-backups/state-backup-prod-YYYYMMDD-HHMMSS

# Validate state integrity
./scripts/state-management.sh validate prod

# View state (read-only)
./scripts/state-management.sh view prod

# Force unlock (use with caution)
./scripts/state-management.sh lock prod
```

### Rollback Procedures

If something goes wrong, safely rollback changes:

```bash
# Rollback infrastructure only
./scripts/rollback.sh -e prod -t terraform -c

# Rollback applications only
./scripts/rollback.sh -e prod -t ansible -c

# Full rollback (infrastructure + applications)
./scripts/rollback.sh -e prod -t all -c

# Options:
# -e, --environment ENV    Environment (dev|staging|prod)
# -t, --target TARGET      Target (terraform|ansible|all)
# -c, --create-backup      Create backup before rollback
```

### Monitoring & Alerts

See [Monitoring & Logging Guide](./docs/monitoring-logging.md) for:
- CloudWatch metrics and dashboards
- Log aggregation and analysis
- Alert configuration
- Health checks
- Performance monitoring

### Disaster Recovery

See [Disaster Recovery Guide](./docs/disaster-recovery.md) for:
- Backup and restore procedures
- RTO/RPO targets
- Failure scenarios
- Emergency response procedures
- DR testing and validation

## Secrets & Security

See [Secrets Management Guide](./docs/secrets-management.md) for comprehensive information on:

- **Secret Storage**: AWS Secrets Manager, Parameter Store, Ansible Vault
- **Best Practices**: Encryption, rotation, audit logging
- **Access Control**: IAM roles, least privilege, break-glass access
- **Environment Management**: Different secrets for each environment
- **CI/CD Integration**: GitHub Actions, GitLab CI

### Quick Reference

```bash
# Store a secret in AWS Secrets Manager
aws secretsmanager create-secret \
  --name paymentform/prod/db-password \
  --secret-string "YOUR_SECURE_PASSWORD"

# Retrieve secret in Terraform
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
}

# Rotate secrets
aws secretsmanager rotate-secret \
  --secret-id paymentform/prod/db-password \
  --rotate-immediately
```

### Security Checklist

- [ ] No hardcoded secrets in code
- [ ] .env files added to .gitignore
- [ ] AWS Secrets Manager configured with encryption
- [ ] IAM roles follow least privilege principle
- [ ] VPCs use security groups and NACLs
- [ ] All data encrypted in transit (TLS 1.3+)
- [ ] All data encrypted at rest (KMS)
- [ ] CloudTrail enabled for audit logging
- [ ] Secrets rotated regularly (90-180 days)

## Troubleshooting

### Common Issues

#### Terraform Lock Issues
```bash
# State locked by another process?
./scripts/state-management.sh lock prod

# Check logs
ls -la tofu/.terraform/.terraform.lock.hcl
```

#### Ansible Connection Issues
```bash
# Test inventory
ansible all -i ansible/inventory/production -m ping

# Check SSH keys
ssh-add ~/.ssh/your-key.pem
```

#### LocalStack Issues
```bash
# Check LocalStack health
curl http://localhost:4566/_localstack/health

# View LocalStack logs
docker logs localstack-main

# Restart LocalStack
./scripts/localstack.sh stop
./scripts/localstack.sh start
```

### Getting Help

- 📖 Check the [Architecture Documentation](./docs/architecture.md)
- 🔍 Review [Deployment Guide](./docs/deployment-guide.md)
- 🚨 See [Disaster Recovery Guide](./docs/disaster-recovery.md)
- 💬 Enable debug logging:
  ```bash
  export TF_LOG=DEBUG
  export ANSIBLE_DEBUG=True
  ```

## Environment-Specific Configurations

### Development (dev.tfvars)
- Single region (US East)
- Minimal resources (t3.micro)
- No multi-AZ or replicas
- Log retention: 7 days
- Backup retention: 7 days

### Staging (staging.tfvars)
- Single region (US East)
- Medium resources (t3.small/medium)
- Multi-AZ enabled
- Log retention: 14 days
- Backup retention: 14 days

### Production (prod.tfvars)
- Multi-region deployment
- Large resources (t3.large+)
- Multi-AZ and read replicas enabled
- Cross-region backup enabled
- Log retention: 30 days
- Backup retention: 30 days

## Cost Optimization

- Use AWS Cost Explorer to track spending
- Enable AWS Budgets for alerts
- Review reserved capacity for production
- Use appropriate instance types per environment
- Leverage S3 lifecycle policies
- Archive old logs to Glacier

## Contributing

1. Create a feature branch
2. Validate changes: `./scripts/validate.sh`
3. Test locally with LocalStack
4. Create backup: `./scripts/state-management.sh backup prod`
5. Deploy to staging first
6. Create pull request with detailed description
7. Peer review before merging
8. Deploy to production after approval

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-20 | Initial release with multi-region support |
| 1.1.0 | 2026-01-20 | Added validation, rollback, state management scripts |
| 1.2.0 | 2026-01-20 | Added comprehensive documentation |

## Support & Contact

- **On-Call Engineer**: Check PagerDuty rotation
- **Slack Channel**: #infrastructure
- **Documentation**: See `/docs` directory
- **Issues**: Create GitHub issue with `[iaac]` prefix

---

**Last Updated**: 2026-01-20
**Maintained By**: Infrastructure Team
**Next Review**: 2026-04-20