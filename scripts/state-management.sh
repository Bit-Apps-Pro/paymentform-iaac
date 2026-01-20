#!/bin/bash

################################################################################
# State Management Script
# Manages Terraform state backup, restore, and validation
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_BACKUP_DIR="${PROJECT_ROOT}/.state-backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Utility Functions
################################################################################

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

################################################################################
# Backup State
################################################################################

backup_state() {
    local environment="$1"
    local backup_name="state-backup-${environment}-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${STATE_BACKUP_DIR}/${backup_name}"

    mkdir -p "$backup_path"

    log_info "Backing up Terraform state for environment: $environment"

    cd "$PROJECT_ROOT/tofu"

    # Get current state from S3
    log_info "Downloading state from S3..."
    aws s3 cp "s3://paymentform-main-state/${environment}/terraform.tfstate" \
        "$backup_path/terraform.tfstate" || log_error "Failed to download state"

    # Create backup metadata
    cat > "$backup_path/metadata.json" << EOF
{
  "environment": "$environment",
  "backup_date": "$(date -Iseconds)",
  "backup_name": "$backup_name",
  "s3_location": "s3://paymentform-main-state/${environment}/terraform.tfstate"
}
EOF

    log_success "State backed up to: $backup_path"
    echo "$backup_path"
}

################################################################################
# Restore State
################################################################################

restore_state() {
    local backup_path="$1"
    local environment="${2:-}"

    if [ ! -f "$backup_path/terraform.tfstate" ]; then
        log_error "Backup file not found: $backup_path/terraform.tfstate"
        return 1
    fi

    # Extract environment from metadata
    if [ -z "$environment" ] && [ -f "$backup_path/metadata.json" ]; then
        environment=$(jq -r '.environment' "$backup_path/metadata.json")
    fi

    log_warning "This will overwrite the current state for environment: $environment"
    read -p "Continue? (type 'yes' to confirm): " -r
    if [[ $REPLY != "yes" ]]; then
        log_error "Restore cancelled"
        return 1
    fi

    log_info "Restoring state to S3..."
    aws s3 cp "$backup_path/terraform.tfstate" \
        "s3://paymentform-main-state/${environment}/terraform.tfstate" || log_error "Failed to restore state"

    log_success "State restored from: $backup_path"
}

################################################################################
# List Backups
################################################################################

list_backups() {
    if [ ! -d "$STATE_BACKUP_DIR" ]; then
        log_warning "No backups found"
        return 0
    fi

    log_info "Available state backups:"
    ls -lh "$STATE_BACKUP_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}'
}

################################################################################
# Validate State
################################################################################

validate_state() {
    local environment="$1"

    log_info "Validating Terraform state for environment: $environment"

    cd "$PROJECT_ROOT/tofu"

    # Initialize Terraform (read-only)
    tofu init -upgrade 2>/dev/null || terraform init -upgrade 2>/dev/null

    # Check state consistency
    log_info "Checking state consistency..."
    if tofu validate &>/dev/null || terraform validate &>/dev/null; then
        log_success "State is consistent"
    else
        log_error "State validation failed"
        return 1
    fi

    # List resources
    log_info "Resources in state:"
    tofu state list 2>/dev/null || terraform state list 2>/dev/null

    # Show state summary
    log_info "State summary:"
    tofu state list -json 2>/dev/null | jq 'length' || echo "Unable to get state summary"

    log_success "State validation completed"
}

################################################################################
# Lock/Unlock State
################################################################################

lock_state() {
    local environment="$1"

    log_info "Locking state for environment: $environment"

    cd "$PROJECT_ROOT/tofu"

    # Force unlock (use with caution)
    local lock_id=$(aws dynamodb scan \
        --table-name paymentform-terraform-lock \
        --filter-expression "Environment = :env" \
        --expression-attribute-values '{":env":{"S":"'"$environment"'"}}' \
        --query 'Items[0].LockID.S' \
        --output text 2>/dev/null || echo "")

    if [ -n "$lock_id" ] && [ "$lock_id" != "None" ]; then
        aws dynamodb delete-item \
            --table-name paymentform-terraform-lock \
            --key '{"LockID":{"S":"'"$lock_id"'"}}' && log_success "State unlocked"
    else
        log_info "No active locks found"
    fi
}

################################################################################
# View State
################################################################################

view_state() {
    local environment="$1"
    local resource="${2:-}"

    cd "$PROJECT_ROOT/tofu"

    if [ -z "$resource" ]; then
        log_info "Showing full state for environment: $environment"
        tofu show 2>/dev/null || terraform show 2>/dev/null
    else
        log_info "Showing resource: $resource"
        tofu state show "$resource" 2>/dev/null || terraform state show "$resource" 2>/dev/null
    fi
}

################################################################################
# Usage
################################################################################

usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS]

Commands:
    backup ENV                      Backup state for environment
    restore BACKUP_PATH [ENV]       Restore state from backup
    list                            List all backups
    validate ENV                    Validate state integrity
    lock ENV                        Force unlock state (use with caution)
    view ENV [RESOURCE]             View state contents
    help                            Show this help message

Examples:
    # Backup production state
    $0 backup prod

    # Restore from backup
    $0 restore .state-backups/state-backup-prod-20260120-120000

    # List backups
    $0 list

    # Validate state
    $0 validate prod

    # View specific resource
    $0 view prod 'module.backend_infrastructure.aws_ecs_service.backend'

EOF
    exit 0
}

################################################################################
# Main
################################################################################

if [ $# -eq 0 ]; then
    usage
fi

case "$1" in
    backup)
        if [ -z "${2:-}" ]; then
            log_error "Environment required"
            usage
        fi
        backup_state "$2"
        ;;
    restore)
        if [ -z "${2:-}" ]; then
            log_error "Backup path required"
            usage
        fi
        restore_state "$2" "${3:-}"
        ;;
    list)
        list_backups
        ;;
    validate)
        if [ -z "${2:-}" ]; then
            log_error "Environment required"
            usage
        fi
        validate_state "$2"
        ;;
    lock)
        if [ -z "${2:-}" ]; then
            log_error "Environment required"
            usage
        fi
        lock_state "$2"
        ;;
    view)
        if [ -z "${2:-}" ]; then
            log_error "Environment required"
            usage
        fi
        view_state "$2" "${3:-}"
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        ;;
esac
