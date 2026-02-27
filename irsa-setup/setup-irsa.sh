#!/bin/bash
set -e

# IRSA Setup Script for Kubernetes on AWS
# This script configures IAM Roles for Service Accounts

echo "=== IRSA Setup for Kubernetes on AWS ==="

# Variables - UPDATE THESE
CLUSTER_NAME="my-k8s-cluster"
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"
NAMESPACE="default"
SERVICE_ACCOUNT_NAME="my-app-sa"
IAM_ROLE_NAME="my-app-role"
IAM_POLICY_NAME="my-app-policy"

echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"

# Step 1: Create OIDC Identity Provider (if not exists)
echo ""
echo "Step 1: Creating OIDC Identity Provider..."

OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
echo "OIDC Provider: $OIDC_PROVIDER"

# Check if OIDC provider already exists
OIDC_EXISTS=$(aws iam list-open-id-connect-providers | grep $OIDC_PROVIDER | wc -l)

if [ $OIDC_EXISTS -eq 0 ]; then
    echo "Creating OIDC provider..."
    eksctl utils associate-iam-oidc-provider \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION \
        --approve
else
    echo "OIDC provider already exists"
fi

# Step 2: Create IAM Policy
echo ""
echo "Step 2: Creating IAM Policy..."

IAM_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"

# Check if policy exists
if aws iam get-policy --policy-arn $IAM_POLICY_ARN 2>/dev/null; then
    echo "IAM Policy already exists: $IAM_POLICY_ARN"
else
    echo "Creating IAM Policy..."
    aws iam create-policy \
        --policy-name $IAM_POLICY_NAME \
        --policy-document file://irsa-policy.json
    echo "IAM Policy created: $IAM_POLICY_ARN"
fi

# Step 3: Create IAM Role with Trust Policy
echo ""
echo "Step 3: Creating IAM Role..."

# Update trust policy with actual values
OIDC_ID=$(echo $OIDC_PROVIDER | cut -d'/' -f5)
sed -e "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" \
    -e "s|REGION|${AWS_REGION}|g" \
    -e "s|OIDC_ID|${OIDC_ID}|g" \
    -e "s|NAMESPACE|${NAMESPACE}|g" \
    -e "s|SERVICE_ACCOUNT_NAME|${SERVICE_ACCOUNT_NAME}|g" \
    irsa-trust-policy.json > /tmp/trust-policy.json

# Check if role exists
if aws iam get-role --role-name $IAM_ROLE_NAME 2>/dev/null; then
    echo "IAM Role already exists: $IAM_ROLE_NAME"
    echo "Updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name $IAM_ROLE_NAME \
        --policy-document file:///tmp/trust-policy.json
else
    echo "Creating IAM Role..."
    aws iam create-role \
        --role-name $IAM_ROLE_NAME \
        --assume-role-policy-document file:///tmp/trust-policy.json
fi

# Step 4: Attach Policy to Role
echo ""
echo "Step 4: Attaching policy to role..."
aws iam attach-role-policy \
    --role-name $IAM_ROLE_NAME \
    --policy-arn $IAM_POLICY_ARN

echo "Policy attached successfully"

# Step 5: Create Kubernetes Service Account
echo ""
echo "Step 5: Creating Kubernetes Service Account..."

IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"

# Update service account YAML with actual values
sed -e "s|ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" \
    -e "s|my-app-sa|${SERVICE_ACCOUNT_NAME}|g" \
    -e "s|my-app-role|${IAM_ROLE_NAME}|g" \
    service-account.yaml > /tmp/service-account.yaml

kubectl apply -f /tmp/service-account.yaml

echo ""
echo "=== IRSA Setup Complete ==="
echo ""
echo "Service Account: $SERVICE_ACCOUNT_NAME"
echo "IAM Role: $IAM_ROLE_ARN"
echo ""
echo "To use in your pods, add:"
echo "  spec:"
echo "    serviceAccountName: $SERVICE_ACCOUNT_NAME"
echo ""
echo "Test with:"
echo "kubectl run test-irsa --rm -it --image=amazon/aws-cli:latest --serviceaccount=$SERVICE_ACCOUNT_NAME -- aws sts get-caller-identity"

# Cleanup
rm -f /tmp/trust-policy.json /tmp/service-account.yaml
