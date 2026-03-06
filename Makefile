# PaymentForm Infrastructure Makefile
# 
# Usage: make [target] ENV=<env> REGION=<region>
# 
# Environments: dev, sandbox, prod (default: sandbox)
# Region: AWS region (default: us-east-1)

.PHONY: help init plan apply destroy validate fmt clean \
	dev sandbox prod \
	build-local push-to-ecr local-deploy \
	cost-estimate cost-estimate-all \
	security-checkov security-tfsec security-full \
	install-tools \
	update-backend update-client update-renderer update-all

# ============================================================================
# Configuration
# ============================================================================

ENV ?= sandbox
REGION ?= us-east-1
AWS_PROFILE ?= default
IMAGE_TAG ?= latest

# Map region to environment folder
ENV_DIR = $(shell if [ "$(ENV)" = "prod" ]; then \
	if [ "$(REGION)" = "us-east-1" ] || [ "$(REGION)" = "" ]; then echo "prod-us"; \
	elif [ "$(REGION)" = "eu-west-1" ]; then echo "prod-eu"; \
	elif [ "$(REGION)" = "ap-southeast-1" ]; then echo "prod-au"; \
	else echo "prod-us"; fi; \
else echo "$(ENV)"; fi)

export AWS_PROFILE

# ============================================================================
# Help
# ============================================================================

help:
	@echo "PaymentForm Infrastructure"
	@echo "=========================="
	@echo ""
	@echo "Usage: make [target] ENV=<env> REGION=<region>"
	@echo ""
	@echo "Environments: dev, sandbox, prod (default: sandbox)"
	@echo ""
	@echo "Core Commands:"
	@echo "  init          Initialize OpenTofu for environment"
	@echo "  plan          Generate execution plan"
	@echo "  apply         Apply changes"
	@echo "  destroy       Destroy infrastructure"
	@echo "  validate      Validate configuration"
	@echo "  fmt           Format .tf files"
	@echo "  clean         Remove .terraform directories"
	@echo ""
	@echo "Environment Shortcuts:"
	@echo "  dev           Plan for dev environment"
	@echo "  sandbox       Plan for sandbox environment"
	@echo "  prod          Plan for prod environment"
	@echo ""
	@echo "Container Image Update:"
	@echo "  update-backend    Update backend container image"
	@echo "  update-client     Update client container image"
	@echo "  update-renderer  Update renderer container image"
	@echo "  update-all       Update all container images"
	@echo ""
	@echo "Container Build & Deploy:"
	@echo "  build-local       Build container images locally"
	@echo "  push-to-ecr       Push images to ECR"
	@echo "  local-deploy      Build, push, and deploy"
	@echo ""
	@echo "Security Scanning:"
	@echo "  security-checkov  Run Checkov scanner"
	@echo "  security-tfsec    Run Tfsec scanner"
	@echo "  security-full     Run both scanners"
	@echo ""
	@echo "Cost Estimation:"
	@echo "  cost-estimate     Estimate costs for ENV"
	@echo "  cost-estimate-all Estimate all environments"
	@echo ""
	@echo "Examples:"
	@echo "  make init ENV=sandbox"
	@echo "  make plan ENV=prod"
	@echo "  make apply ENV=dev"
	@echo "  make update-all ENV=prod IMAGE_TAG=v1.2.3"
	@echo "  make update-backend ENV=prod IMAGE_TAG=latest"
	@echo "  make cost-estimate ENV=sandbox"
	@echo "  make security-full"

# ============================================================================
# Core Commands
# ============================================================================

init:
	@echo "🚀 Initializing OpenTofu for $(ENV) ($(REGION))..."
	@cd environments/$(ENV)/$(ENV_DIR) && tofu init

plan:
	@echo "📋 Planning $(ENV) ($(REGION)) environment..."
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu plan -out=tfplan

apply:
	@echo "✅ Applying $(ENV) ($(REGION)) environment..."
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu apply tfplan

destroy:
	@echo "⚠️  WARNING: Destroying $(ENV) ($(REGION)) environment"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds..."
	@sleep 5
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu destroy -auto-approve

validate:
	@echo "✓ Validating configuration..."
	@cd environments/$(ENV)/$(ENV_DIR) && tofu validate

fmt:
	@echo "📝 Formatting .tf files..."
	@tofu fmt -recursive .

clean:
	@echo "🧹 Cleaning up..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete
	@find . -name "tfplan*" -delete
	@echo "✓ Cleanup complete"

output:
	@echo "📊 Outputs for $(ENV) ($(REGION)):"
	@cd environments/$(ENV)/$(ENV_DIR) && tofu output

state-list:
	@echo "📋 Resources in state:"
	@cd environments/$(ENV)/$(ENV_DIR) && tofu state list

refresh:
	@echo "🔄 Refreshing state for $(ENV) ($(REGION))..."
	@cd environments/$(ENV)/$(ENV_DIR) && tofu refresh

# ============================================================================
# Environment Shortcuts
# ============================================================================

dev: ENV=dev
dev: plan

sandbox: ENV=sandbox
sandbox: plan

prod: ENV=prod
prod: plan

# ============================================================================
# Container Build & Deploy
# ============================================================================

build-local:
	@echo "🔨 Building container images for $(ENV)..."
	@./scripts/build-local.sh $(ENV)

ecr-login:
	@echo "🔐 Authenticating with ECR..."
	@aws ecr get-login-password --region $(REGION) | \
		docker login --username AWS --password-stdin \
		$$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(REGION).amazonaws.com || true

push-to-ecr: ecr-login
	@echo "📤 Pushing images to ECR..."
	@./scripts/push-to-ecr.sh --env $(ENV) --region $(REGION)

local-deploy: build-local push-to-ecr
	@echo "🚀 Deploying $(ENV)..."
	@./scripts/deploy-to-env.sh $(ENV)

# ============================================================================
# Security Scanning
# ============================================================================

security-checkov:
	@echo "🔒 Running Checkov..."
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d providers/ --framework terraform --output json > security-checkov-report.json; \
		checkov -d providers/ --framework terraform --output cli; \
		echo "📄 Report: security-checkov-report.json"; \
	else \
		echo "❌ Checkov not installed. Install with: pip install checkov"; \
	fi

security-tfsec:
	@echo "🔍 Running Tfsec..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec providers/ --format json > security-tfsec-report.json; \
		tfsec providers/; \
		echo "📄 Report: security-tfsec-report.json"; \
	else \
		echo "❌ Tfsec not installed. Install with: brew install tfsec"; \
	fi

security-full: security-checkov security-tfsec
	@echo "✓ Security scan complete"

# ============================================================================
# Cost Estimation
# ============================================================================

cost-estimate:
	@echo "💰 Estimating costs for $(ENV)..."
	@if command -v infracost >/dev/null 2>&1; then \
		cd environments/$(ENV) && \
		infracost breakdown --path . --format table; \
		infracost breakdown --path . --format json > ../../cost-estimate-$(ENV).json; \
		echo "📄 Report: cost-estimate-$(ENV).json"; \
	else \
		echo "❌ Infracost not installed. Install with: brew install infracost"; \
	fi

cost-estimate-all:
	@echo "💰 Estimating costs for all environments..."
	@if command -v infracost >/dev/null 2>&1; then \
		for env in dev sandbox prod; do \
			echo ""; \
			echo "📊 $$env:"; \
			cd environments/$$env && \
			infracost breakdown --path . --format table && \
			infracost breakdown --path . --format json > ../../cost-estimate-$$env.json && \
			cd ../..; \
		done; \
		echo "✓ Cost estimation complete"; \
	else \
		echo "❌ Infracost not installed"; \
	fi

# ============================================================================
# Setup
# ============================================================================

install-tools:
	@echo "🔧 Installing tools..."
	@./scripts/install-testing-tools.sh
	@echo "✓ Installation complete"

# ============================================================================
# Quick Start
# ============================================================================

quick-start: validate
	@echo "✓ Validation passed!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make init ENV=$(ENV)"
	@echo "  2. make plan ENV=$(ENV)"
	@echo "  3. make apply ENV=$(ENV)"

.DEFAULT_GOAL := help

# ============================================================================
# Container Image Update
# ============================================================================

update-backend:
	@echo "🔄 Updating backend container image to $(IMAGE_TAG) for $(ENV) ($(REGION))..."
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu apply -var="backend_container_image=$(IMAGE_TAG)" -auto-approve

update-client:
	@echo "🔄 Updating client container image to $(IMAGE_TAG) for $(ENV) ($(REGION))..."
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu apply -var="client_container_image=$(IMAGE_TAG)" -auto-approve

update-renderer:
	@echo "🔄 Updating renderer container image to $(IMAGE_TAG) for $(ENV) ($(REGION))..."
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu apply -var="renderer_container_image=$(IMAGE_TAG)" -auto-approve

update-all:
	@echo "🔄 Updating all container images to $(IMAGE_TAG) for $(ENV) ($(REGION))..."
	@cd environments/$(ENV)/$(ENV_DIR) && \
		tofu apply \
			-var="backend_container_image=$(IMAGE_TAG)" \
			-var="client_container_image=$(IMAGE_TAG)" \
			-var="renderer_container_image=$(IMAGE_TAG)" \
			-auto-approve
