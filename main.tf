# PaymentForm Infrastructure
#
# Structure:
#   providers/        - Reusable AWS and Cloudflare modules
#   environments/prod - Production configuration (us-east-1, primary)
#
# Quick start:
#   cd environments/prod
#   tofu init && tofu plan -out=tfplan && tofu apply tfplan
#
# See README.md for full documentation.
