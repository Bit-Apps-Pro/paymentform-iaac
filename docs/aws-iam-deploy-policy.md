# AWS IAM Policy for Deploy-Release Workflow

This document defines the IAM policy required by the GitHub Actions `deploy-release` workflow to deploy backend containers to AWS EC2 instances via SSM.

## AWS API Actions Used

The workflow calls these AWS operations:

| Action | Workflow Step | Purpose |
|--------|--------------|---------|
| `ec2:DescribeInstances` | "Deploy to AWS EC2 instances" | Find running instances tagged `Service=backend` |
| `ssm:SendCommand` | "Deploy to AWS EC2 instances" | Run the deploy script on target instances |
| `ssm:GetCommandInvocation` | Post-deploy verification | Check command status and output |

No other AWS actions are used. The workflow does not fetch parameters from SSM Parameter Store, does not interact with S3, and does not manage EC2 lifecycle.

## Least-Privilege IAM Policy

### Standalone JSON Policy

Copy this into the AWS IAM console as a new policy, or save it as `deploy-release-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DescribeBackendInstances",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "SSMSendCommand",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand"
      ],
      "Resource": [
        "arn:aws:ssm:us-east-1:*:document/AWS-RunShellScript",
        "arn:aws:ec2:us-east-1:*:instance/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "SSMGetCommandResult",
      "Effect": "Allow",
      "Action": [
        "ssm:GetCommandInvocation"
      ],
      "Resource": "*"
    }
  ]
}
```

### Notes on Each Statement

**DescribeBackendInstances** - `ec2:DescribeInstances` does not support resource-level permissions, so `Resource: "*"` is required. The region condition prevents use outside `us-east-1`.

**SSMSendCommand** - Scoped to the `AWS-RunShellScript` SSM document only. The `ssm:ResourceTag/Service` condition restricts the command to instances tagged `Service=backend`. If your instances use a different tag key or value, adjust accordingly.

**SSMGetCommandResult** - `ssm:GetCommandInvocation` does not support resource-level permissions or conditions, so `Resource: "*"` is required here.

### Broader Alternative (Simpler, Less Restrictive)

If the tag-based condition on `ssm:SendCommand` causes issues (some AWS accounts don't propagate tags to SSM resources), use this fallback:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeployBackend",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ssm:SendCommand",
        "ssm:GetCommandInvocation"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    }
  ]
}
```

This matches the existing snippet in `backend-deploy.md` but adds the region condition. Prefer the least-privilege version above when possible.

## OIDC Setup for GitHub Actions

The workflow uses `aws-actions/configure-aws-credentials@v4` with OIDC (no long-lived access keys). Here is how to create the IAM role and attach the policy.

### Step 1: Create the OIDC Identity Provider

If you haven't already added GitHub as an OIDC provider in your AWS account:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4e98bab03faadb97b34396831e3780aea1 \
  --client-id-list sts.amazonaws.com
```

### Step 2: Create the IAM Role with Trust Policy

Save this as `github-deploy-role-trust.json`:

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
          "token.actions.githubusercontent.com:sub": "repo:bit-apps-pro/paymentform-backend:*"
        }
      }
    }
  ]
}
```

Replace `ACCOUNT_ID` with your 12-digit AWS account ID. The `StringLike` condition restricts this role to the `paymentform-backend` repo only.

Create the role:

```bash
aws iam create-role \
  --role-name github-deploy-backend \
  --assume-role-policy-document file://github-deploy-role-trust.json
```

### Step 3: Attach the Policy

```bash
aws iam put-role-policy \
  --role-name github-deploy-backend \
  --policy-name deploy-release-policy \
  --policy-document file://deploy-release-policy.json
```

### Step 4: Store the Role ARN

Set the role ARN as a GitHub secret:

```bash
gh secret set AWS_DEPLOY_ROLE_ARN --body "arn:aws:iam::ACCOUNT_ID:role/github-deploy-backend"
```

The workflow reads this secret at runtime:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
    aws-region: us-east-1
```

## Terraform Implementation

### Using `aws_iam_policy_document` (Recommended)

```hcl
# OIDC provider (create once per account)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Trust policy for the deploy role
data "aws_iam_policy_document" "github_deploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

  principals {
    type        = "Federated"
    identifiers = [data.aws_iam_openid_connect_provider.github.arn]
  }

  condition {
    test     = "StringEquals"
    variable = "token.actions.githubusercontent.com:aud"
    values   = ["sts.amazonaws.com"]
  }

  condition {
    test     = "StringLike"
    variable = "token.actions.githubusercontent.com:sub"
    values   = ["repo:bit-apps-pro/paymentform-backend:ref:refs/tags/*"]
  }
}

# Permissions policy
data "aws_iam_policy_document" "deploy_release" {
  statement {
    sid       = "DescribeBackendInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }

  statement {
    sid    = "SSMSendCommand"
    effect = "Allow"
    actions = ["ssm:SendCommand"]

    resources = [
      "arn:aws:ssm:us-east-1:*:document/AWS-RunShellScript"
    ]

    condition {
      test     = "StringEquals"
      variable = "ssm:ResourceTag/Service"
      values   = ["backend"]
    }
  }

  statement {
    sid       = "SSMGetCommandResult"
    effect    = "Allow"
    actions   = ["ssm:GetCommandInvocation"]
    resources = ["*"]
  }
}

# IAM role
resource "aws_iam_role" "github_deploy_backend" {
  name               = "github-deploy-backend"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_assume.json
}

# Inline policy attached to the role
resource "aws_iam_role_policy" "deploy_release" {
  name   = "deploy-release-policy"
  role   = aws_iam_role.github_deploy_backend.id
  policy = data.aws_iam_policy_document.deploy_release.json
}

# Output the role ARN for the GitHub secret
output "deploy_role_arn" {
  value = aws_iam_role.github_deploy_backend.arn
}
```

### Using `aws_iam_role_policy_attachment` with a Managed Policy

If you prefer a standalone managed policy (easier to update without replacing the role):

```hcl
resource "aws_iam_policy" "deploy_release" {
  name   = "deploy-release-policy"
  policy = data.aws_iam_policy_document.deploy_release.json
}

resource "aws_iam_role_policy_attachment" "deploy_release" {
  role       = aws_iam_role.github_deploy_backend.name
  policy_arn = aws_iam_policy.deploy_release.arn
}
```

## EC2 Instance Tagging Requirement

The workflow discovers instances with:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Service,Values=backend" "Name=instance-state-name,Values=running"
```

Every EC2 instance that should receive deployments must have the tag `Service=backend`. Verify with:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Service,Values=backend" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

If instances are missing the tag, apply it:

```bash
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=Service,Value=backend
```

## Verification

After creating the role and policy, verify the setup works:

1. Push a release tag to trigger the workflow, or run it manually:

   ```bash
   gh workflow run deploy-release.yml -f image_tag=v0.0.1
   ```

2. Check the GitHub Actions log for the "Configure AWS credentials" and "Deploy to AWS EC2 instances" steps. Successful OIDC auth and SSM command dispatch confirms the policy is correct.

3. If you see `AccessDenied` errors, check:
   - The OIDC provider thumbprint is current (GitHub rotates these rarely, but verify).
   - The `AWS_DEPLOY_ROLE_ARN` secret matches the actual role ARN.
   - The `token.actions.githubusercontent.com:sub` condition matches your repo path and ref pattern.