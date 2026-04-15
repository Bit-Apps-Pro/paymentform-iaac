.PHONY: help init plan apply destroy validate fmt clean output state-list refresh \
	build-local push-to-ecr local-deploy ecr-login \
	cost-estimate \
	security-checkov security-tfsec security-full \
	install-tools quick-start \
	update-backend update-client update-renderer update-all

ENV_DIR = environments/prod
REGION  ?= us-east-1
AWS_PROFILE ?= default
IMAGE_TAG   ?= latest

export AWS_PROFILE

help:
	@echo "PaymentForm Infrastructure"
	@echo "=========================="
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Core Commands:"
	@echo "  init          Initialize OpenTofu"
	@echo "  plan          Generate execution plan"
	@echo "  apply         Apply changes"
	@echo "  destroy       Destroy infrastructure"
	@echo "  validate      Validate configuration"
	@echo "  fmt           Format .tf files"
	@echo "  clean         Remove .terraform directories"
	@echo "  output        Show outputs"
	@echo "  state-list    List resources in state"
	@echo "  refresh       Refresh state"
	@echo ""
	@echo "Container Image Update:"
	@echo "  update-backend    Update backend container image (IMAGE_TAG=x)"
	@echo "  update-client     Update client container image (IMAGE_TAG=x)"
	@echo "  update-renderer   Update renderer container image (IMAGE_TAG=x)"
	@echo "  update-all        Update all container images (IMAGE_TAG=x)"
	@echo ""
	@echo "Container Build & Deploy:"
	@echo "  build-local   Build container images locally"
	@echo "  push-to-ecr   Push images to ECR"
	@echo "  local-deploy  Build, push, and deploy"
	@echo ""
	@echo "Security Scanning:"
	@echo "  security-checkov  Run Checkov scanner"
	@echo "  security-tfsec    Run Tfsec scanner"
	@echo "  security-full     Run both scanners"
	@echo ""
	@echo "Cost Estimation:"
	@echo "  cost-estimate     Estimate costs"
	@echo ""
	@echo "Examples:"
	@echo "  make init"
	@echo "  make plan"
	@echo "  make apply"
	@echo "  make update-all IMAGE_TAG=v1.2.3"
	@echo "  make update-backend IMAGE_TAG=latest"

init:
	@cd $(ENV_DIR) && tofu init

plan:
	@cd $(ENV_DIR) && tofu plan -out=tfplan

apply:
	@cd $(ENV_DIR) && tofu apply tfplan

destroy:
	@echo "WARNING: Destroying production infrastructure"
	@echo "Press Ctrl+C to cancel, or wait 5 seconds..."
	@sleep 5
	@cd $(ENV_DIR) && tofu destroy -auto-approve

validate:
	@cd $(ENV_DIR) && tofu validate

fmt:
	@tofu fmt -recursive .

clean:
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete
	@find . -name "tfplan*" -delete

output:
	@cd $(ENV_DIR) && tofu output

state-list:
	@cd $(ENV_DIR) && tofu state list

refresh:
	@cd $(ENV_DIR) && tofu refresh

build-local:
	@./scripts/build-local.sh prod

ecr-login:
	@aws ecr get-login-password --region $(REGION) | \
		docker login --username AWS --password-stdin \
		$$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(REGION).amazonaws.com || true

push-to-ecr: ecr-login
	@./scripts/push-to-ecr.sh --env prod --region $(REGION)

local-deploy: build-local push-to-ecr
	@./scripts/deploy-to-env.sh prod

security-checkov:
	@if command -v checkov >/dev/null 2>&1; then \
		checkov -d providers/ --framework terraform --output json > security-checkov-report.json; \
		checkov -d providers/ --framework terraform --output cli; \
		echo "Report: security-checkov-report.json"; \
	else \
		echo "Checkov not installed. Install with: pip install checkov"; \
	fi

security-tfsec:
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec providers/ --format json > security-tfsec-report.json; \
		tfsec providers/; \
		echo "Report: security-tfsec-report.json"; \
	else \
		echo "Tfsec not installed. Install with: brew install tfsec"; \
	fi

security-full: security-checkov security-tfsec

cost-estimate:
	@if command -v infracost >/dev/null 2>&1; then \
		cd $(ENV_DIR) && \
		infracost breakdown --path . --format table; \
		infracost breakdown --path . --format json > ../../cost-estimate-prod.json; \
		echo "Report: cost-estimate-prod.json"; \
	else \
		echo "Infracost not installed. Install with: brew install infracost"; \
	fi

install-tools:
	@./scripts/install-testing-tools.sh

quick-start: validate
	@echo "Validation passed. Next: make init && make plan && make apply"

update-backend:
	@cd $(ENV_DIR) && tofu apply -var="backend_container_image=$(IMAGE_TAG)" -auto-approve

update-client:
	@cd $(ENV_DIR) && tofu apply -var="client_container_image=$(IMAGE_TAG)" -auto-approve

update-renderer:
	@cd $(ENV_DIR) && tofu apply -var="renderer_container_image=$(IMAGE_TAG)" -auto-approve

update-all:
	@cd $(ENV_DIR) && tofu apply \
		-var="backend_container_image=$(IMAGE_TAG)" \
		-var="client_container_image=$(IMAGE_TAG)" \
		-var="renderer_container_image=$(IMAGE_TAG)" \
		-auto-approve

.DEFAULT_GOAL := help
