#!/bin/bash
set -e

# Instance Profile Setup for Kubernetes Nodes
# Attaches IAM role to EC2 instances for AWS API access

echo "=== Setting up IAM Instance Profile for Kubernetes Nodes ==="

# Variables - UPDATE THESE
ROLE_NAME="k8s-node-role"
POLICY_NAME="k8s-node-policy"
INSTANCE_PROFILE_NAME="k8s-node-instance-profile"
AWS_ACCOUNT_ID="123456789012"

echo "Role Name: $ROLE_NAME"
echo "Policy Name: $POLICY_NAME"

# Step 1: Create IAM Policy
echo ""
echo "Step 1: Creating IAM Policy..."

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn $POLICY_ARN 2>/dev/null; then
    echo "Policy already exists: $POLICY_ARN"
else
    echo "Creating policy..."
    aws iam create-policy \
        --policy-name $POLICY_NAME \
        --policy-document file://node-iam-policy.json
    echo "Policy created: $POLICY_ARN"
fi

# Step 2: Create IAM Role with EC2 trust policy
echo ""
echo "Step 2: Creating IAM Role..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

if aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
    echo "Role already exists: $ROLE_NAME"
else
    echo "Creating role..."
    echo "$TRUST_POLICY" > /tmp/trust-policy.json
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file:///tmp/trust-policy.json
    echo "Role created: $ROLE_NAME"
    rm /tmp/trust-policy.json
fi

# Step 3: Attach Policy to Role
echo ""
echo "Step 3: Attaching policy to role..."
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn $POLICY_ARN
echo "Policy attached"

# Step 4: Create Instance Profile
echo ""
echo "Step 4: Creating Instance Profile..."

if aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME 2>/dev/null; then
    echo "Instance profile already exists: $INSTANCE_PROFILE_NAME"
else
    echo "Creating instance profile..."
    aws iam create-instance-profile \
        --instance-profile-name $INSTANCE_PROFILE_NAME
    echo "Instance profile created"
fi

# Step 5: Add Role to Instance Profile
echo ""
echo "Step 5: Adding role to instance profile..."

# Check if role is already in instance profile
ROLE_IN_PROFILE=$(aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --query 'InstanceProfile.Roles[?RoleName==`'$ROLE_NAME'`]' --output text)

if [ -z "$ROLE_IN_PROFILE" ]; then
    echo "Adding role to instance profile..."
    aws iam add-role-to-instance-profile \
        --instance-profile-name $INSTANCE_PROFILE_NAME \
        --role-name $ROLE_NAME
    echo "Role added to instance profile"
else
    echo "Role already in instance profile"
fi

echo ""
echo "=== Instance Profile Setup Complete ==="
echo ""
echo "Instance Profile ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:instance-profile/${INSTANCE_PROFILE_NAME}"
echo ""
echo "Next steps:"
echo "1. Attach this instance profile to your EC2 instances:"
echo "   aws ec2 associate-iam-instance-profile \\"
echo "     --instance-id i-1234567890abcdef0 \\"
echo "     --iam-instance-profile Name=${INSTANCE_PROFILE_NAME}"
echo ""
echo "2. Or specify in launch template/configuration:"
echo "   IamInstanceProfile:"
echo "     Name: ${INSTANCE_PROFILE_NAME}"
echo ""
echo "3. For existing instances, you may need to restart the kubelet"
