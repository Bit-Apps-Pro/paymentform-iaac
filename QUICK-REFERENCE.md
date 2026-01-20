# Quick Reference Guide

## Essential Commands

### Validation & Testing
```bash
# Validate all configurations
./scripts/validate.sh

# Test with LocalStack
./scripts/localstack.sh start
./scripts/localstack.sh deploy
./scripts/localstack.sh destroy
```

### Terraform Operations
```bash
cd tofu/

# Initialize (first time only)
tofu init

# Plan changes
tofu plan -var-file=../environments/prod.tfvars

# Apply changes
tofu apply -var-file=../environments/prod.tfvars

# Destroy resources (use with caution!)
tofu destroy -var-file=../environments/prod.tfvars
```

### Ansible Deployment
```bash
cd ansible/

# Deploy backend
ansible-playbook -i inventory/production playbooks/deploy-backend.yml -e "environment=prod"

# Deploy client
ansible-playbook -i inventory/production playbooks/deploy-client.yml -e "environment=prod"

# Deploy renderer
ansible-playbook -i inventory/production playbooks/deploy-renderer.yml -e "environment=prod"
```

### State Management
```bash
# Backup state
./scripts/state-management.sh backup prod

# List backups
./scripts/state-management.sh list

# Restore from backup
./scripts/state-management.sh restore .state-backups/state-backup-prod-YYYYMMDD-HHMMSS

# Validate state
./scripts/state-management.sh validate prod
```

### Rollback
```bash
# Rollback infrastructure
./scripts/rollback.sh -e prod -t terraform --create-backup

# Rollback applications
./scripts/rollback.sh -e prod -t ansible --create-backup

# Full rollback
./scripts/rollback.sh -e prod -t all --create-backup
```

## Environment Variables

### Development
```bash
export ENVIRONMENT=dev
export AWS_REGION=us-east-1
export DOMAIN_NAME=dev.paymentform.local
```

### Staging
```bash
export ENVIRONMENT=staging
export AWS_REGION=us-east-1
export DOMAIN_NAME=staging.paymentform.io
```

### Production
```bash
export ENVIRONMENT=prod
export AWS_REGION=us-east-1
export DOMAIN_NAME=paymentform.io
```

## Troubleshooting Quick Fixes

### Terraform Lock
```bash
# If state is locked
./scripts/state-management.sh lock prod
```

### Ansible Connection
```bash
# Test connection
ansible all -i ansible/inventory/production -m ping

# Add SSH key
ssh-add ~/.ssh/your-key.pem
```

### LocalStack Connection
```bash
# Check health
curl http://localhost:4566/_localstack/health

# Restart
docker compose -f local/localstack.yml restart
```

## Key Files by Purpose

| Need | File | Location |
|------|------|----------|
| Deployment config | dev/staging/prod.tfvars | `environments/` |
| AWS infrastructure | main.tf | `tofu/` |
| Application deployment | deploy-*.yml | `ansible/playbooks/` |
| Documentation | *.md | `docs/` |
| Scripts | *.sh | `scripts/` |
| Local development | docker-compose*.yml | `local/` |

## Workflow

### New Feature Deployment
1. Create feature branch in Git
2. Update terraform and ansible files
3. Run `./scripts/validate.sh`
4. Test with LocalStack: `./scripts/localstack.sh deploy`
5. Create backup: `./scripts/state-management.sh backup dev`
6. Deploy to dev: `tofu apply -var-file=../environments/dev.tfvars`
7. Test application
8. If OK: Commit and create PR
9. After approval: Deploy to staging then prod

### Emergency Rollback
1. Identify issue
2. Create backup: `./scripts/state-management.sh backup prod`
3. Rollback: `./scripts/rollback.sh -e prod -t all --create-backup`
4. Verify: Check application health
5. Investigate root cause
6. Fix issue
7. Re-deploy

### Disaster Recovery Test
1. Run monthly: `./scripts/disaster-recovery-test.sh`
2. Review output
3. Document findings
4. Fix any issues
5. Update procedures if needed

## Documentation Map

```
iaac/
├── README.md                        ← Start here
├── IMPROVEMENTS.md                  ← What's new
├── QUICK-REFERENCE.md              ← This file
└── docs/
    ├── architecture.md              ← System design
    ├── deployment-guide.md          ← How to deploy
    ├── disaster-recovery.md         ← DR procedures
    ├── secrets-management.md        ← Secret management
    └── monitoring-logging.md        ← Monitoring setup
```

## Contact & Support

- **Infrastructure Team**: #infrastructure on Slack
- **On-Call**: Check PagerDuty
- **Documentation**: See `/docs` folder
- **Issues**: GitHub issues with `[iaac]` prefix

## Important Reminders

⚠️ **CRITICAL**
- Always validate before deploying: `./scripts/validate.sh`
- Always create backups before changes: `./scripts/state-management.sh backup ENV`
- Never commit secrets or .env files
- Test in staging before production
- Document all manual changes

✅ **BEST PRACTICES**
- Use environment-specific tfvars files
- Run validation script before each deployment
- Keep infrastructure code in version control
- Regularly test disaster recovery procedures
- Monitor costs with AWS Cost Explorer
- Rotate secrets every 90 days

## Useful Links

- [AWS Documentation](https://docs.aws.amazon.com/)
- [Terraform Docs](https://www.terraform.io/docs)
- [Ansible Docs](https://docs.ansible.com/)
- [OpenTofu Docs](https://opentofu.org/docs/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/)

---

**Updated**: 2026-01-20
**Version**: 1.0
