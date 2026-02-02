# Cost Optimization & Analysis

This document outlines cost estimates and optimization strategies for container registry usage and the local build workflow.

## Current Setup Costs (summary)

- Local builds: $0 — developers run images locally using Docker
- ECR storage & transfer: small cost depending on retained images and transfer
- Target total monthly cost: $3–8 (sandbox + prod)


## Cost Breakdown by Service (example assumptions)

| Service | Storage (GB) | Unit Cost | Monthly Cost |
|---------|-------------:|----------:|-------------:|
| ECR (sandbox) | 2 GB | $0.10/GB | $0.20
| ECR (prod)    | 5 GB | $0.10/GB | $0.50
| Data transfer | 1 GB | $0.09/GB  | $0.09
| Total (approx)| —    | —        | $0.79 (~$1)

Notes: AWS pricing varies by region; these are conservative estimates for low usage.


## ECR Lifecycle Policy Details & Examples

Use lifecycle policies to automatically expire images and limit storage growth.

Recommended policies:

- Sandbox: keep last 14 images, expire untagged images older than 7 days
- Prod: keep last 30 images, archive or move long-term artifacts to S3 if needed

Example policy snippets are shown in `docs/LOCAL-BUILD-DEPLOY.md`.


## Cost Comparison: GHCR vs ECR vs Local

| Registry | Pricing model | Pros | Cons |
|----------|---------------|------|------|
| Local (no registry) | $0 | Instant iteration, no storage cost | Not suitable for shared CI or sandbox/prod
| GHCR (GitHub) | Free tier + $0.008/GB after 500MB | Integrated with GitHub Actions, low cost | Transfer limits, public by default unless private repos
| ECR (AWS) | $0.10/GB (example) | AWS-native, multi-region replication | Slightly higher storage cost

Choose GHCR for very low-cost long-term storage; choose ECR for AWS-native workflows and replication.


## Monitoring Costs

- Use AWS Cost Explorer to set up daily reports and alerts
- Sample AWS CLI to get cost for last 30 days (requires Cost Explorer API access):

```bash
aws ce get-cost-and-usage --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics "UnblendedCost" --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon ECR"]}}'
```

- Create budgets and alerts for ECR storage thresholds in the AWS console


## How to Audit and Optimize Further

1. Identify large images:

```bash
docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}"
# Or inspect ECR image sizes via AWS Console (images view)
```

2. Implement multi-stage builds to reduce image size
3. Use smaller base images (alpine, distroless)
4. Enforce lifecycle policies per repository
5. Run nightly cleanup of untagged images via automation


## ROI Calculation (Time Saved vs Cost)

- Assume developer local iteration saves 10 minutes per feature compared to remote build+push cycles
- 20 devs × 10 min/day × 20 working days = 6666 dev-minutes/month ≈ 111 dev-hours/month
- Value of time saved (at $50/hr): 111 × $50 ≈ $5,550/month saved
- Cost of ECR storage for sandbox+prod: ~$3–8/month

ROI: Massive — prioritize developer productivity (local builds) and keep cloud registry costs minimal.


## Further Reading & Links

- AWS ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html
- AWS Cost Explorer API: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-explorer-what-is.html
- GHCR pricing and storage: https://docs.github.com/en/packages/learn-github-packages/about-billing-for-github-packages
