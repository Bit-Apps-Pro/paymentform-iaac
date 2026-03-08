# Bootstrap Terraform Configuration

This directory contains the bootstrap Terraform configuration needed to create AWS backend resources for storing and locking PaymentForm infrastructure state.

## What It Creates

✅ **S3 Bucket** - For storing Terraform state files
- Name: `paymentform-terraform-state`
- Features: Versioning, encryption, public access blocked
- Includes logging to dedicated logs bucket

✅ **DynamoDB Table** - For Terraform state locking
- Name: `paymentform-terraform-locks`
- Partition Key: `LockID` (String)
- Billing: Pay-per-request

✅ **Optional CloudTrail** - For audit logging of state changes
- Can be disabled by setting `enable_audit_logging = false`

## Prerequisites

1. **AWS Credentials** configured with appropriate permissions:
   - `s3:CreateBucket`, `s3:PutBucketVersioning`, `s3:PutBucketEncryption`, `s3:PutBucketPublicAccessBlock`
   - `dynamodb:CreateTable`
   - `cloudtrail:CreateTrail` (if enabling audit logging)

2. **Terraform/OpenTofu** >= 1.8 installed

3. **AWS Provider** compatible with ~> 5.0

## Usage

### Step 1: Initialize Bootstrap

```bash
cd bootstrap
terraform init
# or
tofu init
```

### Step 2: Review Plan

```bash
terraform plan
# or
tofu plan
```

### Step 3: Apply Configuration

```bash
terraform apply
# or
tofu apply
```

You'll be asked to confirm - type `yes` to proceed.

### Step 4: Note the Outputs

After successful application, Terraform will output:
- `state_bucket_name` - The S3 bucket name
- `locks_table_name` - The DynamoDB table name
- `backend_config` - Backend configuration snippet (informational)

## Customization

Edit `variables.tf` to customize:
- `aws_region` - Which AWS region to use (default: us-east-1)
- `state_bucket_name` - S3 bucket name (default: paymentform-terraform-state)
- `locks_table_name` - DynamoDB table name (default: paymentform-terraform-locks)
- `enable_audit_logging` - Enable CloudTrail audit logging (default: true)

## After Bootstrap is Complete

Once the bootstrap resources are created, you can run the main PaymentForm infrastructure:

```bash
cd ../environments/prod/prod-us

# Now these commands will work:
tofu init
tofu plan
tofu apply
```

## Security Best Practices

✅ S3 bucket has:
- Versioning enabled (can recover deleted state)
- Encryption enabled (AES-256)
- All public access blocked
- Access logging enabled

✅ DynamoDB table:
- Pay-per-request billing (cost-optimized)
- Locked down to Terraform service only

✅ CloudTrail (optional):
- Logs all API calls to state bucket and DynamoDB
- Provides audit trail for compliance

## Cleanup (If Needed)

To destroy bootstrap resources:

```bash
cd bootstrap
terraform destroy
# or
tofu destroy
```

**WARNING**: This will only succeed if no Terraform state files are stored in the S3 bucket. Ensure you've destroyed all other infrastructure first.

## Troubleshooting

### Error: "S3 bucket name already exists"
- S3 bucket names are globally unique across AWS
- Change `state_bucket_name` in variables.tf to a unique name

### Error: "Access Denied"
- Ensure your AWS credentials have required permissions
- Check AWS profile: `export AWS_PROFILE=anra`

### Error: "DynamoDB table already exists"
- Change `locks_table_name` to a different name
- Or remove the existing table from AWS

## Cost Estimate

Monthly cost is minimal:
- **S3 Storage**: ~$0.10-1.00/mo (for state files, typically <1MB)
- **S3 Data Transfer**: $0 (within AWS region)
- **DynamoDB**: $0-1.25/mo (pay-per-request, minimal usage)
- **CloudTrail** (optional): $2/100k API calls (~$0-2/mo)

**Total**: ~$2-5/month with audit logging
