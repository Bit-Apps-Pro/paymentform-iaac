#!/bin/bash

# Test script to verify LocalStack integration works

echo "Testing LocalStack integration..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed or not in PATH"
    exit 1
fi

# Check if LocalStack container is running
if docker ps | grep -q "paymentform-localstack"; then
    echo "✓ LocalStack container is running"
else
    echo "✗ LocalStack container is not running"
    echo "Run './scripts/localstack.sh start' to start LocalStack"
    exit 1
fi

# Test LocalStack health endpoint
if curl -s http://localhost:4566/_localstack/health > /dev/null; then
    echo "✓ LocalStack health check passed"
else
    echo "✗ LocalStack health check failed"
    exit 1
fi

# Test AWS CLI with LocalStack
if aws --endpoint-url=http://localhost:4566 s3 ls > /dev/null 2>&1; then
    echo "✓ AWS CLI can connect to LocalStack S3"
else
    echo "✗ AWS CLI cannot connect to LocalStack S3"
    exit 1
fi

# Check if Terraform/OpenTofu is available
if command -v tofu &> /dev/null; then
    TERRAFORM_CMD="tofu"
elif command -v terraform &> /dev/null; then
    TERRAFORM_CMD="terraform"
else
    echo "Neither OpenTofu nor Terraform is installed"
    exit 1
fi

echo "✓ $TERRAFORM_CMD is available"

# Check if required files exist
REQUIRED_FILES=(
    "scripts/localstack.sh"
    "local/localstack.yml"
    "tofu/localstack/main.tf"
    "docs/localstack-integration.md"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ $file exists"
    else
        echo "✗ $file does not exist"
        exit 1
    fi
done

echo ""
echo "✓ All tests passed! LocalStack integration is properly configured."
echo ""
echo "To start using LocalStack with your IaC:"
echo "1. Start LocalStack: ./scripts/localstack.sh start"
echo "2. Deploy infrastructure: ./scripts/localstack.sh deploy"
echo "3. Check outputs: cd tofu/localstack && $TERRAFORM_CMD output"
echo "4. Clean up: ./scripts/localstack.sh destroy && ./scripts/localstack.sh stop"