#!/bin/bash
set -e

# Create AWS Credentials Secret
# This script safely creates a Kubernetes secret from environment variables

echo "=== Creating AWS Credentials Secret ==="

# Check if credentials are set in environment
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERROR: AWS credentials not found in environment"
    echo ""
    echo "Please set these environment variables first:"
    echo "  export AWS_ACCESS_KEY_ID='your-access-key'"
    echo "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
    echo "  export AWS_DEFAULT_REGION='us-east-1'"
    echo ""
    exit 1
fi

# Get region (default to us-east-1 if not set)
AWS_REGION=${AWS_DEFAULT_REGION:-us-east-1}

echo "Creating secret in namespace: default"
echo "Region: $AWS_REGION"

# Create the secret from environment variables
kubectl create secret generic aws-credentials \
    --namespace=default \
    --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID" \
    --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY" \
    --from-literal=aws_region="$AWS_REGION" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Secret created successfully!"
echo ""
echo "To use in your pods, add environment variables:"
echo ""
echo "  env:"
echo "  - name: AWS_ACCESS_KEY_ID"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: aws-credentials"
echo "        key: aws_access_key_id"
echo "  - name: AWS_SECRET_ACCESS_KEY"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: aws-credentials"
echo "        key: aws_secret_access_key"
echo "  - name: AWS_DEFAULT_REGION"
echo "    valueFrom:"
echo "      secretKeyRef:"
echo "        name: aws-credentials"
echo "        key: aws_region"
echo ""

# Verify secret was created
echo "Verifying secret..."
kubectl get secret aws-credentials -n default -o jsonpath='{.data}' | grep -q aws_access_key_id && echo "Secret verified!"

echo ""
echo "IMPORTANT: Never commit credentials to git!"
echo "IMPORTANT: For production, use IRSA instead of secrets!"
