#!/bin/bash
set -e

# External Secrets Operator Setup
# Syncs secrets from AWS Secrets Manager to Kubernetes

echo "=== Setting up External Secrets Operator ==="

# Variables - UPDATE THESE
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"
IAM_ROLE_NAME="external-secrets-role"
IAM_POLICY_NAME="external-secrets-policy"
NAMESPACE="external-secrets-system"
SERVICE_ACCOUNT_NAME="external-secrets-sa"

echo "Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"

# Step 1: Install External Secrets Operator with Helm
echo ""
echo "Step 1: Installing External Secrets Operator..."

if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm is not installed. Please install Helm first."
    exit 1
fi

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true

echo "Waiting for External Secrets Operator to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/external-secrets -n external-secrets-system

# Step 2: Create IAM Policy for Secrets Manager Access
echo ""
echo "Step 2: Creating IAM Policy..."

POLICY_DOCUMENT='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "*"
    }
  ]
}'

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"

if aws iam get-policy --policy-arn $POLICY_ARN 2>/dev/null; then
    echo "Policy already exists: $POLICY_ARN"
else
    echo "Creating policy..."
    echo "$POLICY_DOCUMENT" > /tmp/policy.json
    aws iam create-policy \
        --policy-name $IAM_POLICY_NAME \
        --policy-document file:///tmp/policy.json
    echo "Policy created: $POLICY_ARN"
    rm /tmp/policy.json
fi

# Step 3: Get OIDC Provider
echo ""
echo "Step 3: Getting OIDC Provider..."

CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2)
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
OIDC_ID=$(echo $OIDC_PROVIDER | cut -d'/' -f5)

echo "OIDC Provider: $OIDC_PROVIDER"

# Step 4: Create IAM Role with Trust Policy
echo ""
echo "Step 4: Creating IAM Role..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::'$AWS_ACCOUNT_ID':oidc-provider/'$OIDC_PROVIDER'"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "'$OIDC_PROVIDER':sub": "system:serviceaccount:'$NAMESPACE':'$SERVICE_ACCOUNT_NAME'",
          "'$OIDC_PROVIDER':aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}'

if aws iam get-role --role-name $IAM_ROLE_NAME 2>/dev/null; then
    echo "Role already exists: $IAM_ROLE_NAME"
else
    echo "Creating role..."
    echo "$TRUST_POLICY" > /tmp/trust-policy.json
    aws iam create-role \
        --role-name $IAM_ROLE_NAME \
        --assume-role-policy-document file:///tmp/trust-policy.json
    echo "Role created: $IAM_ROLE_NAME"
    rm /tmp/trust-policy.json
fi

# Step 5: Attach Policy to Role
echo ""
echo "Step 5: Attaching policy to role..."
aws iam attach-role-policy \
    --role-name $IAM_ROLE_NAME \
    --policy-arn $POLICY_ARN
echo "Policy attached"

# Step 6: Create Service Account with IRSA
echo ""
echo "Step 6: Creating Service Account..."

IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
  annotations:
    eks.amazonaws.com/role-arn: $IAM_ROLE_ARN
EOF

# Step 7: Create SecretStore
echo ""
echo "Step 7: Creating SecretStore..."

cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      auth:
        jwt:
          serviceAccountRef:
            name: $SERVICE_ACCOUNT_NAME
            namespace: $NAMESPACE
EOF

echo ""
echo "=== External Secrets Operator Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Create a secret in AWS Secrets Manager:"
echo "   aws secretsmanager create-secret \\"
echo "     --name prod/app/aws-credentials \\"
echo "     --secret-string '{\"access_key_id\":\"AKIA...\",\"secret_access_key\":\"...\",\"region\":\"us-east-1\"}'"
echo ""
echo "2. Create an ExternalSecret to sync it:"
echo "   kubectl apply -f external-secret-example.yaml"
echo ""
echo "3. Verify the secret was created:"
echo "   kubectl get externalsecrets"
echo "   kubectl get secrets"
echo ""
echo "The operator will automatically sync secrets every hour (configurable)."
