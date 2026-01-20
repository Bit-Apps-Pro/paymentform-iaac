#!/bin/bash

set -e

# Script to run Payment Form IaC with LocalStack

usage() {
    echo "Usage: $0 [start|stop|deploy|destroy]"
    echo "  start    - Start LocalStack container"
    echo "  stop     - Stop LocalStack container"
    echo "  deploy   - Deploy infrastructure to LocalStack"
    echo "  destroy  - Destroy infrastructure in LocalStack"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

case $1 in
    start)
        echo "Starting LocalStack..."
        docker compose -f local/localstack.yml up -d
        echo "Waiting for LocalStack to be ready..."
        sleep 10
        # Check if LocalStack is running
        if curl -s http://localhost:4566/_localstack/health > /dev/null; then
            echo "LocalStack is ready!"
        else
            echo "LocalStack failed to start properly"
            exit 1
        fi
        ;;
    stop)
        echo "Stopping LocalStack..."
        docker compose -f local/localstack.yml down
        ;;
    deploy)
        echo "Deploying infrastructure to LocalStack..."
        
        # Set LocalStack environment variables
        export AWS_ACCESS_KEY_ID=test
        export AWS_SECRET_ACCESS_KEY=test
        export AWS_DEFAULT_REGION=us-east-1
        export AWS_ENDPOINT_URL=http://localhost:4566
        
        # Change to the localstack directory
        cd tofu/localstack
        
        # Initialize Terraform with LocalStack config
        echo "Initializing Terraform..."
        tofu init
        
        # Plan the deployment
        echo "Planning deployment..."
        tofu plan -out=tfplan
        
        # Apply the deployment
        echo "Applying deployment..."
        tofu apply tfplan
        
        echo "Infrastructure deployed to LocalStack!"
        ;;
    destroy)
        echo "Destroying infrastructure in LocalStack..."
        
        # Set LocalStack environment variables
        export AWS_ACCESS_KEY_ID=test
        export AWS_SECRET_ACCESS_KEY=test
        export AWS_DEFAULT_REGION=us-east-1
        export AWS_ENDPOINT_URL=http://localhost:4566
        
        # Change to the localstack directory
        cd tofu/localstack
        
        # Initialize Terraform
        tofu init
        
        # Destroy the infrastructure
        tofu destroy -auto-approve
        
        echo "Infrastructure destroyed in LocalStack!"
        ;;
    *)
        usage
        ;;
esac