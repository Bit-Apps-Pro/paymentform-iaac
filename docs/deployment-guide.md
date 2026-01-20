# Payment Form IaC Deployment Guide

## Prerequisites

Before deploying the infrastructure, ensure you have the following tools installed:

- OpenTofu v1.6+ or Terraform v1.5+
- Ansible v2.10+
- AWS CLI v2+
- Docker and Docker Compose
- Git

Also ensure you have:

- AWS account with appropriate permissions
- Domain registered in Route53
- Valid SSL certificates (or ability to create them)

## Environment Setup

### 1. Clone the Repository

```bash
git clone <your-iac-repo-url>
cd paymentform-iac
```

### 2. Configure AWS Credentials

```bash
aws configure
```

Or set environment variables:

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### 3. Create Environment Variables File

Create `environments/prod.tfvars`:

```hcl
environment = "prod"
domain_name = "yourdomain.com"
db_username = "postgres"
db_password = "your_secure_password"
app_key = "your_laravel_app_key"
s3_bucket_name = "your-unique-bucket-name"
allow_origin_hosts = "renderer.yourdomain.com,*.renderer.yourdomain.com"
```

## Deployment Steps

### 1. Initialize OpenTofu

```bash
cd tofu
tofu init
```

### 2. Validate Configuration

```bash
tofu validate
tofu fmt
```

### 3. Plan the Deployment

```bash
tofu plan -var-file=../environments/prod.tfvars
```

Review the plan carefully before proceeding.

### 4. Deploy the Infrastructure

```bash
tofu apply -var-file=../environments/prod.tfvars
```

Confirm the deployment when prompted.

### 5. Deploy Applications with Ansible

First, update the inventory file with your server IPs:

```bash
# Edit ansible/inventory/production
[backend]
your-backend-server-ip ansible_user=ec2-user

[client]
your-client-server-ip ansible_user=ec2-user

[renderer]
your-renderer-server-ip ansible_user=ec2-user
```

Then deploy:

```bash
ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-backend.yml
ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-client.yml
ansible-playbook -i ansible/inventory/production ansible/playbooks/deploy-renderer.yml
```

## Regional Deployment Details

### US East (Virginia) - Backend Services

Deploys:
- Laravel backend application
- Primary Aurora PostgreSQL database
- ECS cluster for backend services

```bash
cd tofu/backend/us-east-1
tofu init
tofu plan -var-file=../../../environments/prod.tfvars
tofu apply -var-file=../../../environments/prod.tfvars
```

### EU West (Ireland) - Client Dashboard

Deploys:
- Next.js client dashboard
- ECS cluster for client services

```bash
cd tofu/client/eu-west-1
tofu init
tofu plan -var-file=../../../environments/prod.tfvars
tofu apply -var-file=../../../environments/prod.tfvars
```

### Asia Pacific (Singapore) - Renderer

Deploys:
- Multi-tenant Next.js renderer
- ECS cluster for renderer services

```bash
cd tofu/renderer/ap-southeast-1
tofu init
tofu plan -var-file=../../../environments/prod.tfvars
tofu apply -var-file=../../../environments/prod.tfvars
```

## Database Setup

### Aurora Primary Cluster (US East)

The primary database cluster is deployed in the US East region:

- Engine: Aurora PostgreSQL
- Mode: Serverless v2 for auto-scaling
- Encryption: Enabled at rest
- Backup: 7-day retention

### Aurora Read Replicas

Read replicas are deployed in other regions for low-latency access:

- EU West (Ireland)
- Asia Pacific (Singapore)

### Turso Multi-Region Setup

For tenant databases, Turso provides:

- Serverless database instances
- Multi-region replication
- Built-in encryption
- Automatic scaling

## Storage Configuration

### S3 Primary Bucket

Located in US East:
- Versioning enabled
- Server-side encryption
- Lifecycle policies for cost optimization
- Cross-region replication configured

### S3 Replicas

Replica buckets in other regions:
- EU West
- Asia Pacific
- Automatic synchronization from primary

## Networking and Load Balancing

### Global Resources

Deployed in US East:
- Route53 hosted zone
- SSL certificates for all regions
- CloudFront distributions
- WAF protection

### Regional Load Balancers

Each region has:
- Application Load Balancer (ALB)
- Target groups for services
- HTTPS listeners with SSL termination
- Health checks for targets

### DNS Routing

Route53 implements:
- Latency-based routing
- Failover routing for high availability
- Geographic routing (optional)
- Weighted routing (for canary deployments)

## Security Configuration

### Network Security

- VPCs with public/private subnet separation
- NAT Gateways for private subnet internet access
- Security groups with minimal required ports
- Network ACLs for additional layer of security

### Application Security

- SSL/TLS encryption in transit
- Secrets management with AWS Secrets Manager
- IAM roles with least-privilege permissions
- WAF protection against common attacks

### Data Security

- Encryption at rest for all databases
- S3 bucket policies enforcing HTTPS
- Regular security scanning
- Audit logging enabled

## Monitoring and Observability

### AWS Services Used

- CloudWatch for metrics and logs
- ECS Container Insights
- AWS X-Ray for distributed tracing
- AWS Config for compliance monitoring

### Key Metrics to Monitor

- Application response times
- Error rates
- Database connection counts
- CPU and memory utilization
- Request throughput
- Failed health checks

## Maintenance Procedures

### Regular Maintenance

- Rotate database passwords monthly
- Update SSL certificates before expiration
- Review and update security groups
- Clean up old log files
- Update AMIs and container images

### Scaling Procedures

- Monitor CloudWatch metrics for scaling triggers
- Adjust ECS service task counts as needed
- Scale Aurora Serverless v2 capacity limits
- Update Auto Scaling Groups if using EC2

### Backup and Recovery

- Test backup restoration regularly
- Maintain copies of Terraform state files
- Document manual recovery procedures
- Keep infrastructure diagrams updated

## Troubleshooting

### Common Issues

1. **State Lock Conflicts**: Check DynamoDB lock table and remove stale locks if needed
2. **Dependency Errors**: Ensure resources are created in the correct order
3. **Permission Issues**: Verify IAM roles and policies
4. **DNS Propagation**: Allow time for Route53 changes to propagate

### Useful Commands

```bash
# Check Terraform state
tofu state list

# View specific resource
tofu show aws_lb.backend

# Refresh state
tofu refresh

# Import existing resources
tofu import aws_instance.example i-1234567890abcdef0
```

## Rollback Procedures

### Infrastructure Rollback

1. Identify the previous working state file
2. Restore from backup if needed
3. Apply the previous configuration
4. Verify application functionality

### Application Rollback

1. Deploy previous application version
2. Verify functionality
3. Update DNS routing if needed
4. Monitor for issues

## Cost Optimization

### Regular Reviews

- Right-size compute resources
- Clean up unused resources
- Optimize storage classes
- Review reserved instance opportunities
- Monitor for unused IP addresses

### Automation Opportunities

- Schedule non-production resources to stop
- Implement intelligent auto-scaling
- Use spot instances where appropriate
- Automate cleanup of temporary resources