#!/bin/bash

set -e

# Script to deploy the payment form application locally

usage() {
    echo "Usage: $0 [backend|client|renderer|full]"
    echo "  backend  - Deploy only the backend service"
    echo "  client   - Deploy only the client service (includes backend)"
    echo "  renderer - Deploy only the renderer service (includes backend)"
    echo "  full     - Deploy all services"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

case $1 in
    backend)
        echo "Deploying backend service locally..."
        docker compose -f local/docker-compose.backend.yml up -d --build
        echo "Backend deployed. Access at: http://api.local.paymentform.com:8000"
        ;;
    client)
        echo "Deploying client service locally..."
        docker compose -f local/docker-compose.client.yml up -d --build
        echo "Client deployed. Access at: http://localhost:3000"
        ;;
    renderer)
        echo "Deploying renderer service locally..."
        docker compose -f local/docker-compose.renderer.yml up -d --build
        echo "Renderer deployed. Access at: http://localhost:3001"
        ;;
    full)
        echo "Deploying full application locally..."
        docker compose -f local/docker-compose.backend.yml up -d --build
        sleep 10
        echo "Full application deployed."
        echo "Backend API: http://api.local.paymentform.com:8000"
        echo "Health check: http://api.local.paymentform.com:8000/health"
        ;;
    *)
        usage
        ;;
esac

echo "Deployment completed!"