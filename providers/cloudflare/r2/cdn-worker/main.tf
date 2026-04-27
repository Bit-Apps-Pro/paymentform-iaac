terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  worker_configs = var.worker_enabled && length(var.regional_buckets) > 0 ? {
    for region, bucket in var.regional_buckets : region => {
      name    = "${var.environment}-cdn-worker-${region}"
      pattern = "${var.domain_prefix}-${region}.${var.base_domain}/*"
      bucket  = bucket
    }
  } : {}
}

resource "cloudflare_workers_script" "cdn_worker" {
  for_each = local.worker_configs

  account_id         = var.cloudflare_account_id
  script_name        = each.value.name
  content            = file("${path.module}/../worker/index.js")
  compatibility_date = "2024-01-01"

  bindings = [
    {
      name        = "R2_BUCKET"
      type        = "r2_bucket"
      bucket_name = each.value.bucket
    },
    {
      name = "ENVIRONMENT"
      type = "plain_text"
      text = var.environment
    },
    {
      name = "CORS_ORIGINS"
      type = "plain_text"
      text = join(",", var.cors_allowed_origins)
    }
  ]
}

resource "cloudflare_workers_route" "cdn_route" {
  for_each = var.worker_enabled && var.cloudflare_zone_id != "" ? local.worker_configs : {}

  zone_id = var.cloudflare_zone_id
  pattern = each.value.pattern
  script  = cloudflare_workers_script.cdn_worker[each.key].script_name
}
