# LocalStack Integration for Payment Form IaC

This document explains how to run the Payment Form Infrastructure as Code (IaC) using LocalStack for local development and testing.

## Overview

LocalStack provides a fully functional local cloud environment that emulates AWS services. This allows you to test your infrastructure code without connecting to actual AWS resources, saving costs and enabling faster iteration during development.

## Prerequisites

Before using LocalStack with the Payment Form IaC, ensure you have:

- Docker and Docker Compose installed
- OpenTofu or Terraform installed
- The Payment Form IaC repository cloned

## Setting Up LocalStack

### 1. Start LocalStack

```bash
# From the IaC root directory
./scripts/localstack.sh start
```

This will start the LocalStack container with all necessary AWS services enabled.

### 2. Verify LocalStack is Running

```bash
curl http://localhost:4566/_localstack/health
```

You should see a JSON response indicating the health status of LocalStack services.

## Deploying Infrastructure to LocalStack

### 1. Deploy the Infrastructure

```bash
./scripts/localstack.sh deploy
```

This command will:
- Set up the necessary environment variables to connect to LocalStack
- Initialize Terraform/OpenTofu
- Plan and apply the infrastructure configuration
- Create local equivalents of AWS resources

### 2. Check Deployed Resources

After deployment, you can verify the resources were created by checking the Terraform outputs:

```bash
cd iaac/tofu/localstack
tofu output
```

## Available LocalStack Services

The LocalStack configuration includes support for the following AWS services that are used in the Payment Form IaC:

- S3: Object storage for application assets
- RDS: Database services (PostgreSQL)
- EC2: Virtual machines (simplified for local testing)
- ELB/ALB: Load balancing
- Route53: DNS management
- IAM: Identity and access management
- Secrets Manager: Secure storage for sensitive information
- CloudWatch: Monitoring and logging
- Lambda: Serverless functions (if needed)

## Testing Applications Locally

Once the infrastructure is deployed to LocalStack, you can run your applications against the local AWS services:

### Backend Application
The backend can connect to the local RDS instance and S3 bucket created by the LocalStack deployment.

### Client and Renderer Applications
These can be configured to connect to the local backend services.

## Cleaning Up

To clean up the local infrastructure:

```bash
./scripts/localstack.sh destroy
```

To stop the LocalStack container:

```bash
./scripts/localstack.sh stop
```

## Configuration Details

### Provider Configuration

The LocalStack provider configuration overrides the standard AWS endpoints to point to the local LocalStack instance:

```hcl
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_force_path_style         = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    s3             = "http://localhost:4566"
    rds            = "http://localhost:4566"
    elbv2          = "http://localhost:4566"
    # ... other services
  }
}
```

### Local Infrastructure

The local configuration creates simplified versions of the production infrastructure:

- Single VPC instead of multi-region setup
- Basic RDS instance instead of Aurora cluster
- Simple ALB instead of multi-region load balancing
- Single S3 bucket instead of cross-region replication

## Limitations

While LocalStack provides excellent AWS service emulation, there are some limitations to be aware of:

- Some advanced AWS features may not be fully supported
- Performance characteristics differ from real AWS services
- Certain service integrations may behave differently
- Multi-region setups are simulated rather than truly distributed

## Best Practices

1. **Use for Development**: LocalStack is ideal for development and testing but should not replace production testing.

2. **Keep Local Config Separate**: The local configuration is kept separate from production configs to avoid accidental deployment.

3. **Validate Before Deploying**: Always test your infrastructure code with LocalStack before deploying to production.

4. **Clean Up Resources**: Remember to destroy local infrastructure when finished to free up resources.

## Troubleshooting

### Common Issues

1. **Connection Refused**: Ensure LocalStack is running and accessible at http://localhost:4566

2. **Service Not Available**: Check the LocalStack health endpoint to verify all required services are running

3. **Terraform Errors**: Verify that environment variables are properly set for LocalStack

### Debugging Tips

- Check LocalStack logs: `docker logs paymentform-localstack`
- Verify environment variables: `env | grep AWS`
- Test connectivity: `curl http://localhost:4566/health`

## Next Steps

After successfully testing your infrastructure with LocalStack:

1. Make any necessary adjustments to your Terraform configurations
2. Test your application code against the local infrastructure
3. Run integration tests to ensure everything works together
4. Deploy to your sandbox or production AWS environment with confidence