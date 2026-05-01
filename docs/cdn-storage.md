# CDN & R2 Storage

## R2 Buckets

### Application Storage

Three regional buckets for user file uploads, managed by `module.paymentform_storage_application` (source: `providers/cloudflare/r2/application-storage`):

| Bucket | Region | R2 Location | Jurisdiction |
|--------|--------|-------------|--------------|
| `paymentform-uploads-us` | US | wnam | default |
| `paymentform-uploads-eu` | EU | weur | eu |
| `paymentform-uploads-ap` | AP | apac | default |

Bucket names are formed as `{bucket_name_prefix}-{region}`, where `bucket_name_prefix = "paymentform-uploads"`.

The backend selects the appropriate bucket per region using env vars:

```env
AWS_BUCKET_US=paymentform-uploads-us
AWS_BUCKET_EU=paymentform-uploads-eu
AWS_BUCKET_AP=paymentform-uploads-ap
AWS_BUCKET=paymentform-uploads-us          # default
AWS_USE_PATH_STYLE_ENDPOINT=true
AWS_ENDPOINT=https://{account_id}.r2.cloudflarestorage.com
```

Access credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) are set per-instance via Terraform variables (`var.upload_storage_access_key_id`, `var.upload_storage_secret_access_key`).

### SSL Config Bucket

`paymentform-prod-ssl-config` stores Caddy TLS certificates for the renderer. The renderer reads/writes certs here so they persist across container restarts.

Env vars for the renderer:

```env
SSL_STORAGE_BUCKET_NAME=paymentform-prod-ssl-config
SSL_STORAGE_BUCKET_HOST=<bucket_domain>
SSL_STORAGE_BUCKET_ACCESS_KEY_ID=<key>
SSL_STORAGE_BUCKET_ACCESS_KEY=<secret>
```

## CDN Workers

Two Cloudflare Workers serve files from R2 buckets via custom domains:

| Worker | Domain | R2 Bucket |
|--------|--------|-----------|
| `prod-cdn-worker-us` | `cdn.paymentform.io` | `paymentform-uploads-us` |
| `prod-cdn-worker-ap` | `cdn-ap.paymentform.io` | `paymentform-uploads-ap` |

The EU bucket (`paymentform-uploads-eu`) has no dedicated CDN worker domain.

### Worker Script

The worker code is at `providers/cloudflare/r2/worker/index.js`. It handles:

- GET/HEAD requests for public files (path must contain `/public/` segment)
- CORS preflight (OPTIONS) responses
- Range requests for partial content
- Content-Type detection from file extension
- Cache-Control: `public, max-age=31536000, immutable`

Worker bindings:

- `R2_BUCKET` — bound to the regional bucket
- `ENVIRONMENT` — plain text, set to `prod`
- `CORS_ORIGINS` — comma-separated allowed origins (e.g., `https://app.paymentform.io`)

### Route Pattern

Each worker route uses `domain/*`. For example:

- `cdn.paymentform.io/*` routes to `prod-cdn-worker-us`
- `cdn-ap.paymentform.io/*` routes to `prod-cdn-worker-ap`

### Terraform Configuration

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

### Deploying CDN Workers

```bash
cd environments/prod
tofu apply -target=module.paymentform_storage_cdn
```

### Disabling CDN Workers

Set `worker_enabled = false` and apply. The worker stops handling requests but remains in state.

### Adding a New Region

1. Add the bucket in the application storage module (it uses `regional_config` with default regions `us`, `eu`, `ap` — add a new key if needed).
2. Add the domain mapping to `regional_domains`:
   ```hcl
   regional_domains = {
     us = "cdn.paymentform.io"
     ap = "cdn-ap.paymentform.io"
     eu = "cdn-eu.paymentform.io"   # new
   }
   ```
3. Add the DNS record for the new domain in the DNS module.
4. Run `make plan` and `make apply`.