#!/bin/bash

################################################################################
# Validation and Linting Script
# Validates Terraform, Ansible, and Docker configurations
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED_CHECKS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        log_success "Found: $1 ($(command -v "$1"))"
        return 0
    else
        log_error "Missing: $1"
        return 1
    fi
}

################################################################################
# Terraform Validation
################################################################################

validate_terraform() {
    log_info "Validating Terraform configurations..."
    ((TOTAL_CHECKS++))

    if ! command -v tofu &> /dev/null && ! command -v terraform &> /dev/null; then
        log_warning "Skipping Terraform validation: tofu/terraform not installed"
        return 0
    fi

    local tf_cmd="tofu"
    if ! command -v tofu &> /dev/null; then
        tf_cmd="terraform"
    fi

    cd "$PROJECT_ROOT/tofu"

    # Initialize Terraform
    log_info "Initializing Terraform in $PWD..."
    $tf_cmd init -upgrade > /dev/null 2>&1 || log_warning "Terraform init had issues"

    # Validate all modules
    for module_dir in */; do
        if [ -f "$module_dir/main.tf" ]; then
            log_info "Validating module: $module_dir"
            if $tf_cmd validate "$module_dir" > /dev/null 2>&1; then
                log_success "Terraform validation passed: $module_dir"
            else
                log_error "Terraform validation failed: $module_dir"
                $tf_cmd validate "$module_dir"
            fi
        fi
    done

    # Format check
    log_info "Checking Terraform formatting..."
    if $tf_cmd fmt -check -recursive . > /dev/null 2>&1; then
        log_success "Terraform formatting is correct"
    else
        log_warning "Terraform formatting issues found (run: tofu fmt -recursive .)"
    fi

    cd - > /dev/null
}

################################################################################
# Ansible Validation
################################################################################

validate_ansible() {
    log_info "Validating Ansible configurations..."
    ((TOTAL_CHECKS++))

    if ! check_command ansible-lint; then
        log_warning "Skipping ansible-lint: not installed"
        return 0
    fi

    cd "$PROJECT_ROOT/ansible"

    # Lint playbooks
    for playbook in playbooks/*.yml; do
        log_info "Linting playbook: $(basename "$playbook")"
        if ansible-lint "$playbook" > /dev/null 2>&1; then
            log_success "Ansible linting passed: $(basename "$playbook")"
        else
            log_error "Ansible linting failed: $(basename "$playbook")"
            ansible-lint "$playbook" || true
        fi
    done

    # Check syntax
    for playbook in playbooks/*.yml; do
        if ansible-playbook --syntax-check "$playbook" > /dev/null 2>&1; then
            log_success "Ansible syntax check passed: $(basename "$playbook")"
        else
            log_error "Ansible syntax check failed: $(basename "$playbook")"
        fi
    done

    cd - > /dev/null
}

################################################################################
# Docker Validation
################################################################################

validate_docker() {
    log_info "Validating Docker configurations..."
    ((TOTAL_CHECKS++))

    if ! check_command docker; then
        log_warning "Skipping Docker validation: docker not installed"
        return 0
    fi

    cd "$PROJECT_ROOT/local"

    # Validate docker-compose files
    for compose_file in docker-compose*.yml; do
        log_info "Validating docker-compose file: $compose_file"
        if docker compose -f "$compose_file" config > /dev/null 2>&1; then
            log_success "Docker Compose validation passed: $compose_file"
        else
            log_error "Docker Compose validation failed: $compose_file"
            docker compose -f "$compose_file" config
        fi
    done

    cd - > /dev/null
}

################################################################################
# Environment Files Check
################################################################################

validate_environments() {
    log_info "Checking environment configuration files..."
    ((TOTAL_CHECKS++))

    local required_envs=("dev" "sandbox" "prod")
    
    for env in "${required_envs[@]}"; do
        local env_file="$PROJECT_ROOT/environments/${env}.tfvars"
        if [ -f "$env_file" ]; then
            log_success "Environment file found: ${env}.tfvars"
            
            # Check for required variables
            local required_vars=("environment" "domain_name" "db_username")
            for var in "${required_vars[@]}"; do
                if grep -q "^$var" "$env_file"; then
                    log_success "  Variable '$var' found in $env.tfvars"
                else
                    log_warning "  Variable '$var' missing in $env.tfvars"
                fi
            done
        else
            log_error "Environment file missing: ${env}.tfvars"
        fi
    done
}

################################################################################
# Secrets Check
################################################################################

validate_secrets() {
    log_info "Checking for hardcoded secrets..."
    ((TOTAL_CHECKS++))

    local secret_patterns=(
        "password.*="
        "secret.*="
        "key.*="
        "api_key"
        "AWS_SECRET_ACCESS_KEY"
        "PRIVATE_KEY"
    )

    local found_secrets=0

    for pattern in "${secret_patterns[@]}"; do
        if grep -r "$pattern" \
            "$PROJECT_ROOT/tofu" \
            "$PROJECT_ROOT/ansible" \
            --include="*.tf" \
            --include="*.yml" \
            --include="*.yaml" \
            --exclude-dir=.git \
            --exclude="*.tfvars" \
            2>/dev/null | grep -v ".tfvars\|#\|description\|variable\|locals" | head -5; then
            log_warning "Potential hardcoded secret found (pattern: $pattern)"
            ((found_secrets++))
        fi
    done

    if [ $found_secrets -eq 0 ]; then
        log_success "No obvious hardcoded secrets found"
    else
        log_error "Potential secrets found - review above"
    fi
}

################################################################################
# Git Checks
################################################################################

validate_git() {
    log_info "Checking Git configuration..."
    ((TOTAL_CHECKS++))

    cd "$PROJECT_ROOT"

    # Check for .gitignore
    if [ -f .gitignore ]; then
        log_success "Found .gitignore file"
        
        local ignored_items=(".env" ".tfvars" ".vault-pass" "*.key" "*.pem")
        for item in "${ignored_items[@]}"; do
            if grep -q "$item" .gitignore; then
                log_success "  Pattern '$item' is gitignored"
            else
                log_warning "  Pattern '$item' is not in .gitignore"
            fi
        done
    else
        log_error ".gitignore file not found"
    fi

    # Check for uncommitted changes
    if git status --porcelain | grep -q .; then
        log_warning "Uncommitted changes detected:"
        git status --short | head -5
    else
        log_success "Repository is clean"
    fi

    cd - > /dev/null
}

################################################################################
# Documentation Check
################################################################################

validate_documentation() {
    log_info "Checking documentation files..."
    ((TOTAL_CHECKS++))

    local required_docs=(
        "$PROJECT_ROOT/README.md"
        "$PROJECT_ROOT/docs/architecture.md"
        "$PROJECT_ROOT/docs/deployment-guide.md"
        "$PROJECT_ROOT/docs/disaster-recovery.md"
        "$PROJECT_ROOT/docs/secrets-management.md"
        "$PROJECT_ROOT/docs/monitoring-logging.md"
    )

    for doc in "${required_docs[@]}"; do
        if [ -f "$doc" ]; then
            log_success "Documentation found: $(basename "$doc")"
        else
            log_error "Documentation missing: $(basename "$doc")"
        fi
    done
}

################################################################################
# Permission Checks
################################################################################

validate_permissions() {
    log_info "Checking file permissions..."
    ((TOTAL_CHECKS++))

    # Check for world-readable secrets
    if find "$PROJECT_ROOT" -name "*.key" -o -name "*.pem" -o -name ".env*" 2>/dev/null | grep -q .; then
        log_warning "Sensitive files found, checking permissions..."
        find "$PROJECT_ROOT" \( -name "*.key" -o -name "*.pem" -o -name ".env*" \) 2>/dev/null | while read -r file; do
            perms=$(stat -c %a "$file")
            if [ "${perms: -2}" = "44" ] || [ "${perms: -2}" = "66" ]; then
                log_error "World-readable sensitive file: $file (perms: $perms)"
            else
                log_success "Secure permissions on: $(basename "$file") ($perms)"
            fi
        done
    else
        log_success "No sensitive files found in default locations"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Infrastructure as Code Validation Script                ║${NC}"
    echo -e "${BLUE}║        $(date '+%Y-%m-%d %H:%M:%S')                                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo

    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command git
    echo

    # Run validations
    validate_environments
    validate_secrets
    validate_git
    validate_documentation
    validate_permissions
    validate_terraform
    validate_ansible
    validate_docker

    # Summary
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Validation Summary                          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "Total Checks: $TOTAL_CHECKS"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
    echo

    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "${GREEN}✓ All validations passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some validations failed. Please review the above output.${NC}"
        return 1
    fi
}

main "$@"
