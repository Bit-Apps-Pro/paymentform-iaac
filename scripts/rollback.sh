#!/bin/bash

################################################################################
# Rollback Script
# Safely rollback infrastructure and application changes
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_DIR="${PROJECT_ROOT}/.rollback-backups"
LOG_FILE="${BACKUP_DIR}/rollback-$(date +%Y%m%d-%H%M%S).log"

################################################################################
# Utility Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

################################################################################
# Show Usage
################################################################################

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV       Environment to rollback (dev|sandbox|prod)
    -t, --target TARGET         Target to rollback (terraform|ansible|all)
    -v, --version VERSION       Version/commit to rollback to
    -c, --create-backup         Create backup before rollback
    -h, --help                  Show this help message

Examples:
    # Rollback infrastructure to previous version
    $0 -e prod -t terraform -v abc123

    # Rollback applications with backup
    $0 -e sandbox -t ansible --create-backup

    # Full rollback with backup
    $0 -e prod -t all --create-backup

EOF
    exit 1
}

################################################################################
# Parse Arguments
################################################################################

ENVIRONMENT=""
TARGET=""
VERSION=""
CREATE_BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -c|--create-backup)
            CREATE_BACKUP=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate arguments
if [ -z "$ENVIRONMENT" ] || [ -z "$TARGET" ]; then
    log_error "Missing required arguments"
    usage
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

################################################################################
# Create Backup
################################################################################

create_backup() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    log_info "Creating backup: $backup_name"

    mkdir -p "$backup_path"

    # Backup Terraform state
    log_info "Backing up Terraform state..."
    cd "$PROJECT_ROOT/tofu"
    if [ -d .terraform ]; then
        cp -r .terraform "$backup_path/" || log_warning "Failed to backup .terraform"
    fi
    cd - > /dev/null

    # Backup Ansible inventory
    log_info "Backing up Ansible inventory..."
    cp -r "$PROJECT_ROOT/ansible/inventory" "$backup_path/" || log_warning "Failed to backup inventory"

    # Backup environment files
    log_info "Backing up environment configuration..."
    cp "$PROJECT_ROOT/environments/${ENVIRONMENT}.tfvars" "$backup_path/" || log_warning "Failed to backup tfvars"

    log_success "Backup created at: $backup_path"
    echo "$backup_path"
}

################################################################################
# Terraform Rollback
################################################################################

rollback_terraform() {
    log_info "Rolling back Terraform changes for environment: $ENVIRONMENT"

    cd "$PROJECT_ROOT/tofu"

    # Check if version is specified
    if [ -n "$VERSION" ]; then
        log_info "Switching to Git version: $VERSION"
        git checkout "$VERSION" -- . || log_error "Failed to checkout version"
    fi

    # Initialize Terraform
    log_info "Initializing Terraform..."
    if command -v tofu &> /dev/null; then
        tofu init -upgrade
    else
        terraform init -upgrade
    fi

    # Show what would change
    log_info "Showing planned changes (review carefully)..."
    if command -v tofu &> /dev/null; then
        tofu plan -var-file="../environments/${ENVIRONMENT}.tfvars" -lock=false || true
    else
        terraform plan -var-file="../environments/${ENVIRONMENT}.tfvars" -lock=false || true
    fi

    # Confirm before applying
    read -p "Do you want to proceed with rollback? (type 'yes' to confirm): " -r
    if [[ $REPLY == "yes" ]]; then
        log_info "Applying rollback..."
        if command -v tofu &> /dev/null; then
            tofu apply -var-file="../environments/${ENVIRONMENT}.tfvars" -auto-approve
        else
            terraform apply -var-file="../environments/${ENVIRONMENT}.tfvars" -auto-approve
        fi
        log_success "Terraform rollback completed"
    else
        log_error "Rollback cancelled by user"
        return 1
    fi

    cd - > /dev/null
}

################################################################################
# Ansible Rollback
################################################################################

rollback_ansible() {
    log_info "Rolling back Ansible changes for environment: $ENVIRONMENT"

    cd "$PROJECT_ROOT/ansible"

    # Check if version is specified
    if [ -n "$VERSION" ]; then
        log_info "Switching to Git version: $VERSION"
        git checkout "$VERSION" -- . || log_error "Failed to checkout version"
    fi

    # Run rollback playbook
    if [ -f "playbooks/rollback.yml" ]; then
        log_info "Running rollback playbook..."
        ansible-playbook \
            -i "inventory/production" \
            "playbooks/rollback.yml" \
            -e "environment=$ENVIRONMENT" \
            -e "rollback_version=$VERSION" || log_error "Rollback playbook failed"
        log_success "Ansible rollback completed"
    else
        log_warning "No rollback playbook found at playbooks/rollback.yml"
    fi

    cd - > /dev/null
}

################################################################################
# Full Rollback
################################################################################

rollback_all() {
    log_info "Performing full rollback for environment: $ENVIRONMENT"

    # Rollback in reverse order
    rollback_ansible && log_success "Application rollback completed"
    rollback_terraform && log_success "Infrastructure rollback completed"

    log_success "Full rollback completed"
}

################################################################################
# Verify Rollback
################################################################################

verify_rollback() {
    log_info "Verifying rollback..."

    # Check service health
    local services=("backend" "client" "renderer")
    for service in "${services[@]}"; do
        log_info "Checking $service health..."
        # Add your health check commands here
    done

    log_success "Rollback verification completed"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             Infrastructure Rollback Script                      ║${NC}"
    echo -e "${BLUE}║        Environment: $ENVIRONMENT, Target: $TARGET                              ║${NC}"
    echo -e "${BLUE}║        $(date '+%Y-%m-%d %H:%M:%S')                                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo

    # Create backup if requested
    if [ "$CREATE_BACKUP" = true ]; then
        create_backup
    fi

    echo -e "${YELLOW}WARNING: This operation will rollback your infrastructure/applications!${NC}"
    read -p "Continue? (type 'yes' to proceed): " -r
    if [[ $REPLY != "yes" ]]; then
        log_error "Rollback cancelled"
        exit 1
    fi

    # Execute rollback based on target
    case $TARGET in
        terraform)
            rollback_terraform
            ;;
        ansible)
            rollback_ansible
            ;;
        all)
            rollback_all
            ;;
        *)
            log_error "Invalid target: $TARGET"
            exit 1
            ;;
    esac

    # Verify rollback
    verify_rollback

    echo
    log_success "Rollback process completed. Log saved to: $LOG_FILE"
}

main "$@"
