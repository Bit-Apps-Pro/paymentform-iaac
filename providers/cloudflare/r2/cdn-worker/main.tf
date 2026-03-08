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

resource "cloudflare_workers_script" "cdn_worker" {
  count = var.worker_enabled && var.worker_route_pattern != "" ? 1 : 0

  account_id         = var.cloudflare_account_id
  script_name        = "${var.environment}-cdn-worker"
  content            = file("${path.module}/../worker/index.js")
  compatibility_date = "2024-01-01"

  bindings = [
    {
      name        = "R2_BUCKET"
      type        = "r2_bucket"
      bucket_name = var.application_bucket_name
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
  count = var.worker_enabled && var.worker_route_pattern != "" && var.cloudflare_zone_id != "" ? 1 : 0

  zone_id = var.cloudflare_zone_id
  pattern = var.worker_route_pattern
  script  = cloudflare_workers_script.cdn_worker[0].script_name
}