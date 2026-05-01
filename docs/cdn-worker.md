# CDN Worker

## Overview

The CDN worker module (`providers/cloudflare/r2/cdn-worker`) serves files from regional R2 buckets via Cloudflare Workers. Each worker is bound to its regional bucket and routes traffic through a dedicated domain.

## Workers

| Worker | Domain | R2 Bucket | Region |
|--------|--------|-----------|--------|
| `prod-cdn-worker-us` | `cdn.paymentform.io` | `paymentform-uploads-us` | US (wnam) |
| `prod-cdn-worker-ap` | `cdn-ap.paymentform.io` | `paymentform-uploads-ap` | AP (apac) |

The EU bucket (`paymentform-uploads-eu`) does not have a dedicated CDN worker domain. It is accessed directly via the R2 public bucket URL or through the application backend.

## Configuration

The CDN worker is configured in `environments/prod/main.tf` under `module "paymentform_storage_cdn"`:

```hcl
module "paymentform_storage_cdn" {
  source = "../../providers/cloudflare/r2/cdn-worker"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  worker_enabled       = true
  regional_buckets     = module.paymentform_storage_application.bucket_names
  domain_prefix        = "cdn"
  base_domain          = "paymentform.io"
  regional_domains     = { us = "cdn.paymentform.io", ap = "cdn-ap.paymentform.io" }
  cors_allowed_origins = ["https://app.paymentform.io"]
}
```

### Key Variables

- **`worker_enabled`**: Set to `true` to deploy the worker. Set to `false` to disable without removing the resource from state.
- **`regional_domains`**: Maps region keys to custom domains. Each entry creates a Worker route and binds the worker to the corresponding R2 bucket.
- **`regional_buckets`**: Comes from the application storage module. Maps region keys (`us`, `eu`, `ap`) to bucket names.
- **`cors_allowed_origins`**: Origins allowed in CORS responses from the worker.

## Route Pattern

Each worker route uses the pattern `domain/*`. For example:

- `cdn.paymentform.io/*` routes to `prod-cdn-worker-us`
- `cdn-ap.paymentform.io/*` routes to `prod-cdn-worker-ap`

## Deploying

```bash
# Deploy only the CDN worker module
cd environments/prod
tofu apply -target=module.paymentform_storage_cdn

# Or via Makefile (full apply)
make plan
make apply
```

## Disabling a Worker

Set `worker_enabled = false` in the module configuration and apply. This stops the worker from handling requests but keeps the resource in state for easy re-enablement.

## Adding a New Regional Worker

1. Add the bucket in the application storage module (if not already present).
2. Add the domain mapping to `regional_domains`:
   ```hcl
   regional_domains = {
     us = "cdn.paymentform.io"
     ap = "cdn-ap.paymentform.io"
     eu = "cdn-eu.paymentform.io"  # new
   }
   ```
3. Add the DNS record for the new domain in the DNS module.
4. Run `make plan` and `make apply`.