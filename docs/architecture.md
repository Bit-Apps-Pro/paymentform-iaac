# Payment Form Multi-Region IaC Documentation

## Architecture Overview

This Infrastructure as Code (IaC) implements a multi-region deployment for the Payment Form application with the following characteristics:

- **Backend**: Hosted in US East (Virginia) region
- **Client Dashboard**: Hosted in EU West (Ireland) region  
- **Renderer (Multi-tenant)**: Hosted in Asia Pacific (Singapore) region
- **Databases**: Primary Aurora in US East with read replicas in other regions, plus Turso for tenant databases
- **Storage**: S3 with cross-region replication
- **Load Balancing**: Regional ALBs with Route53 latency-based routing

## Directory Structure

```
paymentform-iac/
├── tofu/                     # OpenTofu/Terraform configurations
│   ├── backend/              # Backend service infrastructure
│   │   └── us-east-1/        # US East region configuration
│   ├── client/               # Client service infrastructure
│   │   └── eu-west-1/        # EU West region configuration
│   ├── renderer/             # Renderer service infrastructure
│   │   └── ap-southeast-1/   # Asia Pacific region configuration
│   ├── databases/            # Database infrastructure
│   │   ├── primary/          # Primary Aurora cluster
│   │   ├── replicas/         # Aurora read replicas
│   │   └── turso/            # Turso multi-region setup
│   ├── storage/              # Storage infrastructure
│   │   ├── primary/          # Primary S3 bucket
│   │   └── replicas/         # S3 replica buckets
│   ├── networking/           # Networking infrastructure
│   │   ├── global/           # Global resources (Route53, ACM, WAF)
│   │   └── regional/         # Regional networking
│   └── modules/              # Reusable modules
│       ├── ecs-service/      # ECS service module
│       ├── rds-cluster/      # RDS cluster module
│       ├── s3-bucket/        # S3 bucket module
│       └── vpc/              # VPC module
├── ansible/                  # Ansible automation
│   ├── inventory/            # Inventory files
│   ├── playbooks/            # Deployment playbooks
│   ├── roles/                # Ansible roles
│   └── vars/                 # Variable files
├── local/                    # Local development configurations
├── scripts/                  # Utility scripts
└── docs/                     # Documentation
```

## Deployment Process

### Prerequisites

1. Install OpenTofu (>= v1.6) or Terraform
2. Install Ansible (>= v2.10)
3. Configure AWS CLI with appropriate permissions
4. Ensure Docker and Docker Compose are available for local deployments

### Multi-Region Deployment Steps

1. **Initialize OpenTofu**:
   ```bash
   cd tofu/
   tofu init
   ```

2. **Plan the infrastructure**:
   ```bash
   tofu plan -var-file=../environments/prod.tfvars
   ```

3. **Deploy the infrastructure**:
   ```bash
   tofu apply -var-file=../environments/prod.tfvars
   ```

4. **Deploy applications using Ansible**:
   ```bash
   ansible-playbook -i inventory/production playbooks/deploy-backend.yml
   ansible-playbook -i inventory/production playbooks/deploy-client.yml
   ansible-playbook -i inventory/production playbooks/deploy-renderer.yml
   ```

### Regional Deployment Order

For proper dependencies, deploy in this order:

1. **Networking (Global)**: Route53 zones, certificates
2. **Databases**: Primary Aurora cluster
3. **Storage**: Primary S3 bucket with replication
4. **Services**: Backend, Client, Renderer in their respective regions

## Traffic Routing Strategy

The architecture implements intelligent traffic routing:

1. **Latency-Based Routing**: Route53 directs users to the geographically closest region
2. **Application-Level Routing**: Each region serves its designated function
3. **Failover Protection**: Health checks and failover routing ensure high availability
4. **CDN Integration**: CloudFront caches static content globally

## Security Features

- VPCs with private/public subnet separation
- Security groups restricting access to necessary ports only
- SSL/TLS encryption in transit
- KMS encryption at rest
- WAF protection at the edge
- IAM roles with least-privilege permissions
- Regular security scanning and monitoring

## Multi-Tenancy Support

The renderer service is designed for multi-tenancy:

- Tenant-specific subdomains (e.g., tenant1.renderer.paymentform.com)
- Isolated tenant data in Turso database
- Shared infrastructure with logical separation
- Scalable architecture supporting thousands of tenants

## Local Development

For local development and testing:

```bash
# Deploy backend only
./scripts/deploy-local.sh backend

# Deploy client with backend
./scripts/deploy-local.sh client

# Deploy renderer with backend
./scripts/deploy-local.sh renderer

# Deploy full application
./scripts/deploy-local.sh full
```

## Monitoring and Operations

- CloudWatch for AWS resource monitoring
- ECS Container Insights for container monitoring
- Application logs shipped to CloudWatch
- Health checks and alarms configured
- Automated scaling based on demand

## Disaster Recovery

- Multi-region deployment provides geographic redundancy
- Database replication ensures data durability
- Automated backups with configurable retention
- Rapid recovery procedures documented
- Regular disaster recovery testing recommended