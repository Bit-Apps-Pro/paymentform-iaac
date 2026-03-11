#!/bin/bash
set -e

NAMESPACE_ID="$1"
WORKER_PATH="$2"
ENV="$3"
ACCOUNT_ID="$4"
KV_STORE_API_TOKEN="$5"

if [ -z "$NAMESPACE_ID" ]; then
    echo "ERROR: NAMESPACE_ID is empty, skipping deployment"
    exit 0
fi

if [ ! -f "$WORKER_PATH/wrangler.toml" ]; then
    echo "ERROR: wrangler.toml not found at $WORKER_PATH"
    exit 1
fi

echo "Updating wrangler.toml with namespace ID: $NAMESPACE_ID"

KV_NAMESPACE_ID=""
KV_PREVIEW_ID=""

if [ "$ENV" = "prod-us" ]; then
    KV_NAMESPACE_ID="$NAMESPACE_ID"
    KV_PREVIEW_ID="$NAMESPACE_ID"
fi

cd "$WORKER_PATH"

if [ -n "$KV_STORE_API_TOKEN" ]; then
    echo "Setting KV_STORE_API_TOKEN secret..."
    echo "$KV_STORE_API_TOKEN" | wrangler secret put KV_STORE_API_TOKEN --env prod --yes 2>/dev/null || true
fi

if [ -n "$KV_NAMESPACE_ID" ]; then
    echo "Updating kv_namespaces in wrangler.toml..."
    if [ "$ENV" = "prod-us" ]; then
        sed -i "s|id = \".*\"|id = \"$KV_NAMESPACE_ID\"|" "$WORKER_PATH/wrangler.toml"
    fi
fi

echo "Deploying kv-store worker..."
cd "$WORKER_PATH"

if ! command -v wrangler &> /dev/null; then
    echo "Installing wrangler..."
    npm install -g wrangler
fi

if [ "$ENV" = "prod-us" ]; then
    wrangler deploy --env prod --yes
else
    wrangler deploy --yes
fi

echo "KV Store deployed successfully"
