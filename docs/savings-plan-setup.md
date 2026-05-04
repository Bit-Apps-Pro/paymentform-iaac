# AWS Savings Plans Setup for PaymentForm Production

This guide walks through purchasing AWS Savings Plans for the PaymentForm production infrastructure in `us-east-1`. All instances run on Graviton (t4g family).

## What Are Savings Plans?

Savings Plans are a commitment-based pricing model from AWS. You commit to a consistent amount of compute usage (measured in $/hour) for a 1- or 3-year term, and AWS gives you lower prices in return. Think of it as a volume discount contract: you promise to spend a certain amount per hour on compute, and AWS cuts the rate.

Savings Plans are **account-level billing constructs**. They are **not** Terraform resources. You purchase them through the AWS Console or CLI, and they apply automatically to matching usage on your account. There is no infrastructure code to manage here.

> **Key point:** Savings Plans don't reserve capacity. They're a billing discount, not a capacity guarantee. If you need guaranteed capacity in a specific Availability Zone, you'd use On-Demand Capacity Reservations alongside your Savings Plan.

## Plan Types: Compute vs EC2 Instance

AWS offers two Savings Plan types relevant to EC2 workloads:

### Compute Savings Plans

- Up to **66% off** On-Demand pricing
- Applies to **any** EC2 instance family, size, Region, OS, or tenancy
- Also covers AWS Fargate and Lambda usage
- You can switch from `t4g.small` to `m6g.large`, move workloads between Regions, or migrate from EC2 to Fargate, and the discount still applies
- Best for workloads that might change instance types or Regions

### EC2 Instance Savings Plans

- Up to **72% off** On-Demand pricing (deeper discount)
- Locked to a **specific instance family in a specific Region** (e.g., `t4g` in `us-east-1`)
- Flexible within that family: `t4g.small`, `t4g.medium`, `t4g.large` all qualify
- Does **not** cover Fargate or Lambda
- Best for stable workloads that won't change instance families

### Which Should You Choose?

For this infrastructure, **Compute Savings Plans** are recommended because:

1. The backend and renderer run in Auto Scaling Groups (1-4 instances). Scale-out means your hourly compute spend fluctuates. Compute Savings Plans flex to cover whatever instances are running.
2. If you ever migrate workloads to Fargate or Lambda, Compute Savings Plans still apply.
3. The 6% discount gap (66% vs 72%) is a small price for the flexibility you gain. You're trading a marginal savings increase for the ability to change instance families without penalty.

If you're confident you'll stay on `t4g` instances in `us-east-1` for the full term and want the deepest discount, EC2 Instance Savings Plans are an option. But the Auto Scaling Groups make that a riskier bet.

## Term Length: 1-Year vs 3-Year

| Term | Deeper Discount | Risk | Best For |
|------|-----------------|------|----------|
| 1-year | Lower | Lower commitment, easier to adjust | Uncertain workloads, first-time buyers |
| 3-year | Higher | Locked in longer | Stable, predictable workloads |

**Recommendation:** Start with a **1-year term**. This is the first Savings Plan purchase for this infrastructure. A 1-year term lets you validate that the commitment level is right before locking in for three years. After the first year, if usage is stable, renew with a 3-year term for the deeper discount.

## Payment Options: All Upfront vs Partial Upfront vs No Upfront

| Option | Upfront Cost | Effective Discount | Cash Flow Impact |
|--------|-------------|-------------------|-----------------|
| All Upfront | Full term paid at purchase | Highest | Big one-time charge, then zero monthly compute charges for covered usage |
| Partial Upfront | ~50% upfront, rest monthly | Middle | Moderate upfront, small monthly charges |
| No Upfront | $0 upfront, all monthly | Lowest | No upfront, but you pay monthly and get the smallest discount |

**Recommendation:** **Partial Upfront** for the first purchase. It balances discount depth with cash flow flexibility. If budget allows, All Upfront gives the best effective rate. No Upfront is fine for testing the waters but leaves money on the table.

## Calculating Your Hourly Commitment

### Current Infrastructure

| Component | Instance Type | Count | Region |
|-----------|--------------|-------|--------|
| AWS Backend | t4g.small | 1-4 (ASG) | us-east-1 |
| AWS Renderer | t4g.small | 1-4 (ASG, spot/reserve mix) | us-east-1 |
| AWS Cache (Valkey) | t4g.medium | 1 | us-east-1 |
| AWS Postgres Primary | t4g.medium | 1 | us-east-1 |

### Step-by-Step Calculation

You need to determine the On-Demand hourly rate for each instance type, then sum them up. The commitment should cover your **steady-state baseline** (minimum running instances), not your peak.

1. **Look up current On-Demand pricing** for your instance types in `us-east-1`:
   - Go to [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) and find the Linux/ARM64 rates for:
     - `t4g.small`
     - `t4g.medium`

2. **Calculate baseline hourly spend.** Use the minimum instance count for ASGs:

   ```
   Baseline hourly = (2 x t4g.small On-Demand rate)    # Backend + Renderer at min 1 each
                   + (1 x t4g.medium On-Demand rate)    # Cache
                   + (1 x t4g.medium On-Demand rate)    # Postgres
   ```

   The Renderer ASG uses a spot/reserve mix. Only the On-Demand portion of the Renderer is eligible for Savings Plans coverage. Spot usage is **not** covered by Savings Plans. Check what fraction of the Renderer runs On-Demand vs Spot, and only count the On-Demand portion.

3. **Apply the Savings Plan discount rate** to get your commitment amount:

   ```
   Hourly commitment = Baseline hourly spend x (1 - discount percentage)
   ```

   For a Compute Savings Plan with ~66% off, the Savings Plan rate is roughly 34% of On-Demand. So:

   ```
   Hourly commitment = Baseline hourly spend x 0.34
   ```

4. **Round down slightly.** It's better to slightly under-commit than over-commit. Unused commitment is still billed. You can always purchase an additional plan later to cover growth.

### Concrete Example

> **Important:** The prices below are illustrative placeholders. Always check the [current AWS EC2 pricing page](https://aws.amazon.com/ec2/pricing/on-demand/) for real-time rates before purchasing.

Assuming these approximate On-Demand rates in `us-east-1` for Linux/ARM64:

| Instance | Approx. On-Demand Hourly |
|----------|--------------------------|
| t4g.small | ~$0.017 |
| t4g.medium | ~$0.034 |

Baseline calculation (minimum instances, Renderer assumed 50% On-Demand):

```
Backend:     1 x $0.017 = $0.017/hr
Renderer:    0.5 x $0.017 = $0.0085/hr  (only On-Demand portion)
Cache:       1 x $0.034 = $0.034/hr
Postgres:    1 x $0.034 = $0.034/hr
─────────────────────────────────────────
Total baseline On-Demand:  ~$0.0935/hr
```

With a Compute Savings Plan at ~66% discount, the Savings Plan rate is ~34% of On-Demand:

```
Hourly commitment ≈ $0.0935 x 0.34 ≈ $0.032/hr
```

This means you'd commit to roughly **$0.032/hour**. At that rate:

- Monthly cost: ~$0.032 x 730 hrs ≈ **$23.36/month**
- Compared to On-Demand baseline: ~$0.0935 x 730 ≈ **$68.26/month**
- Estimated savings: ~**$45/month** (roughly 66%)

Again, **verify current pricing** before purchasing. The AWS Pricing Calculator and Cost Explorer Recommendations will give you exact numbers.

## Purchasing the Savings Plan

### Prerequisites

1. **Enable Cost Explorer** in your AWS account. Savings Plans recommendations and purchases go through the Cost Management console. If Cost Explorer isn't enabled, enable it and wait up to 24 hours for usage data to populate.
   - [Enabling Cost Explorer](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-enable.html)

2. **Verify IAM permissions.** The IAM user or role purchasing the plan needs:
   - `savingsplans:CreateSavingsPlan`
   - `savingsplans:DescribeSavingsPlans`
   - `ce:GetSavingsPlansPurchaseRecommendation`

   The managed policy `AWSCostManagementSavingsPlansAdmin` provides full access. For read-only, use `AWSCostManagementSavingsPlansReadOnly`.

### Purchase via AWS Console

1. Open the [Billing and Cost Management console](https://console.aws.amazon.com/costmanagement/)
2. In the left navigation, under **Savings Plans**, click **Recommendations**
3. AWS shows a recommended commitment based on your last 30 days of usage. Review it.
4. If the recommendation looks right, add it to your cart. If you want a custom amount:
   - Click **Purchase Savings Plans** in the left nav
   - Select **Compute Savings Plans** as the type
   - Select **1 year** or **3 year** term
   - Select **Partial Upfront** (or your preferred payment option)
   - Enter your hourly commitment amount (e.g., `0.032`)
5. Review the order details, then confirm the purchase.

### Purchase via AWS CLI

```bash
# First, get a recommendation
aws ce get-savings-plans-purchase-recommendation \
  --account-scope "PAYER" \
  --lookback-period "THIRTY_DAYS" \
  --payment-option "PARTIAL_UPFRONT" \
  --savings-plans-type "COMPUTE_SP" \
  --term-in-one-years "ONE_YEAR"

# Purchase (replace HOURLY_COMMITMENT with your calculated value)
aws savingsplans create-savings-plan \
  --savings-plan-offering-id "OFFERING_ID_FROM_RECOMMENDATION" \
  --commitment "HOURLY_COMMITMENT" \
  --upfront-payment "UPFRONT_AMOUNT"

# To find available offering IDs:
aws savingsplans describe-savings-plans-offerings \
  --savings-plans-type "COMPUTE_SP" \
  --term "ONE_YEAR" \
  --payment-option "PARTIAL_UPFRONT"
```

> **Note:** Savings Plans can also be purchased via the [Savings Plans API](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-api.html). The CLI example above is a starting point. Use the AWS Console for your first purchase, as it provides better visibility into what you're committing to.

### Important Notes on Purchasing

- **You can return a Savings Plan within 7 days** of purchase, but only within the same calendar month. This is a safety net, not a strategy. See [Returning a purchased Savings Plan](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-purchase.html#sp-return).
- **Savings Plans cannot be cancelled** after the 7-day return window. You're committed for the full term.
- **You can purchase multiple Savings Plans** over time. If your usage grows, buy an additional plan to cover the increase. Plans stack additively.
- **Spot usage is not eligible** for Savings Plans discounts. The Renderer's Spot instances won't be covered.

## Validating Coverage After Purchase

After purchasing, verify that your Savings Plan is covering the intended instances.

### Check in Cost Explorer

1. Open [Cost Explorer](https://console.aws.amazon.com/costmanagement/home#/cost-explorer)
2. Set the date range to the current month
3. Group by **Savings Plans coverage**
4. Verify that your EC2 usage shows high coverage (aim for 80%+ of your steady-state On-Demand spend)

### Check Savings Plans Utilization

1. In the Cost Management console, go to **Savings Plans** > **Inventory**
2. Check the **Utilization** column. This shows what percentage of your commitment is being used each hour.
   - **Near 100%**: Good. Your commitment matches your usage.
   - **Below 70%**: You're over-committed. Consider letting the plan expire without renewal, or scale up usage.
   - **Above 100%**: You're under-committed. Some usage is still at On-Demand rates. Consider purchasing an additional plan.

### Check Coverage Report

1. In Cost Explorer, select **Savings Plans coverage** from the report type dropdown
2. Filter by service: **Amazon EC2**
3. Filter by Region: **US East (N. Virginia)**
4. Verify that your `t4g` instances show coverage from the Savings Plan

### Set Up Alerts

Configure a **Savings Plans utilization alert** to notify you if utilization drops below a threshold:

1. In the Cost Management console, go to **Budgets** > **Create budget**
2. Select **Savings Plans budget**
3. Set a utilization threshold (e.g., alert if utilization drops below 80%)
4. Configure SNS or email notifications

## Ongoing Management

- **Monitor monthly.** Check Cost Explorer for coverage and utilization trends.
- **Plan renewals early.** Start evaluating renewal 60-90 days before a plan expires to avoid a gap in coverage.
- **Adjust for scale changes.** If you add instances or change instance types, verify your commitment still covers the baseline. Purchase additional plans as needed.
- **Don't over-commit.** It's better to cover 80-90% of steady-state usage and pay On-Demand for peaks than to over-commit and pay for unused capacity.

## Reference Links

- [What are Savings Plans?](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html)
- [Savings Plans Types](https://docs.aws.amazon.com/savingsplans/latest/userguide/plan-types.html)
- [Purchasing Savings Plans](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-purchase.html)
- [Getting Started with Savings Plans](https://docs.aws.amazon.com/savingsplans/latest/userguide/get-started.html)
- [Understanding Savings Plans Recommendations](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-recommendations.html)
- [How Savings Plans Apply to Usage](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-applying.html)
- [Compute and EC2 Instance Savings Plans Pricing](https://aws.amazon.com/savingsplans/compute-pricing/)
- [Savings Plans FAQ](https://aws.amazon.com/savingsplans/faqs/)
- [Savings Plans vs Reserved Instances](https://repost.aws/knowledge-center/ec2-savings-plan-reserved-instances)
- [AWS EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)
- [AWS Pricing Calculator](https://calculator.aws/)