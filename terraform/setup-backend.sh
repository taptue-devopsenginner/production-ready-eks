#!/bin/bash
# Script to set up Terraform backend with S3 and DynamoDB
# This creates the resources needed for state management

set -e

echo "=== Terraform Backend Setup ==="
echo ""

# Configuration variables - UPDATE THESE
STATE_BUCKET="my-terraform-state-bucket"
LOGS_BUCKET="my-terraform-state-logs-bucket"
DYNAMODB_TABLE="terraform-state-lock"
AWS_REGION="us-east-1"
KMS_KEY_ALIAS="alias/terraform-state"

echo "Configuration:"
echo "  State Bucket: $STATE_BUCKET"
echo "  Logs Bucket: $LOGS_BUCKET"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo "  Region: $AWS_REGION"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "ERROR: AWS CLI not configured or credentials invalid"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: $ACCOUNT_ID"
echo ""

# Step 1: Create S3 bucket for state
echo "Step 1: Creating S3 bucket for Terraform state..."
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
    echo "  Bucket $STATE_BUCKET already exists"
else
    echo "  Creating bucket $STATE_BUCKET..."
    aws s3api create-bucket \
        --bucket "$STATE_BUCKET" \
        --region "$AWS_REGION" \
        $(if [ "$AWS_REGION" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)

    echo "  Waiting for bucket to be available..."
    aws s3api wait bucket-exists --bucket "$STATE_BUCKET"
fi

# Step 2: Enable versioning
echo ""
echo "Step 2: Enabling versioning on state bucket..."
aws s3api put-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --versioning-configuration Status=Enabled

# Verify versioning is enabled
VERSIONING_STATUS=$(aws s3api get-bucket-versioning --bucket "$STATE_BUCKET" --query Status --output text)
echo "  Versioning status: $VERSIONING_STATUS"

# Step 3: Enable encryption
echo ""
echo "Step 3: Enabling server-side encryption..."
aws s3api put-bucket-encryption \
    --bucket "$STATE_BUCKET" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }'

# Step 4: Block public access
echo ""
echo "Step 4: Blocking public access..."
aws s3api put-public-access-block \
    --bucket "$STATE_BUCKET" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Step 5: Create logs bucket
echo ""
echo "Step 5: Creating logs bucket..."
if aws s3api head-bucket --bucket "$LOGS_BUCKET" 2>/dev/null; then
    echo "  Logs bucket $LOGS_BUCKET already exists"
else
    echo "  Creating logs bucket $LOGS_BUCKET..."
    aws s3api create-bucket \
        --bucket "$LOGS_BUCKET" \
        --region "$AWS_REGION" \
        $(if [ "$AWS_REGION" != "us-east-1" ]; then echo "--create-bucket-configuration LocationConstraint=$AWS_REGION"; fi)

    aws s3api wait bucket-exists --bucket "$LOGS_BUCKET"
fi

# Block public access on logs bucket
aws s3api put-public-access-block \
    --bucket "$LOGS_BUCKET" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Step 6: Enable access logging
echo ""
echo "Step 6: Enabling access logging..."
aws s3api put-bucket-logging \
    --bucket "$STATE_BUCKET" \
    --bucket-logging-status '{
        "LoggingEnabled": {
            "TargetBucket": "'$LOGS_BUCKET'",
            "TargetPrefix": "state-access-logs/"
        }
    }'

# Step 7: Add lifecycle policy
echo ""
echo "Step 7: Adding lifecycle policy for old versions..."
aws s3api put-bucket-lifecycle-configuration \
    --bucket "$STATE_BUCKET" \
    --lifecycle-configuration '{
        "Rules": [
            {
                "Id": "expire-old-versions",
                "Status": "Enabled",
                "NoncurrentVersionExpiration": {
                    "NoncurrentDays": 90
                },
                "NoncurrentVersionTransitions": [
                    {
                        "NoncurrentDays": 30,
                        "StorageClass": "STANDARD_IA"
                    }
                ]
            },
            {
                "Id": "delete-old-delete-markers",
                "Status": "Enabled",
                "Expiration": {
                    "ExpiredObjectDeleteMarker": true
                }
            }
        ]
    }'

# Step 8: Create DynamoDB table for locking
echo ""
echo "Step 8: Creating DynamoDB table for state locking..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" 2>/dev/null; then
    echo "  DynamoDB table $DYNAMODB_TABLE already exists"
else
    echo "  Creating DynamoDB table $DYNAMODB_TABLE..."
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION" \
        --tags Key=Name,Value="Terraform State Lock" Key=Environment,Value=Production \
        --sse-specification Enabled=true

    echo "  Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
fi

# Step 9: Enable point-in-time recovery for DynamoDB
echo ""
echo "Step 9: Enabling point-in-time recovery for DynamoDB..."
aws dynamodb update-continuous-backups \
    --table-name "$DYNAMODB_TABLE" \
    --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
    --region "$AWS_REGION"

# Step 10: Create KMS key (optional)
echo ""
echo "Step 10: Creating KMS key for encryption (optional)..."
if aws kms describe-key --key-id "$KMS_KEY_ALIAS" --region "$AWS_REGION" 2>/dev/null; then
    echo "  KMS key $KMS_KEY_ALIAS already exists"
    KMS_KEY_ID=$(aws kms describe-key --key-id "$KMS_KEY_ALIAS" --region "$AWS_REGION" --query KeyMetadata.KeyId --output text)
else
    echo "  Creating KMS key..."
    KMS_KEY_ID=$(aws kms create-key \
        --description "Terraform state encryption key" \
        --key-usage ENCRYPT_DECRYPT \
        --origin AWS_KMS \
        --region "$AWS_REGION" \
        --query KeyMetadata.KeyId \
        --output text)

    # Create alias
    aws kms create-alias \
        --alias-name "$KMS_KEY_ALIAS" \
        --target-key-id "$KMS_KEY_ID" \
        --region "$AWS_REGION"

    # Enable key rotation
    aws kms enable-key-rotation \
        --key-id "$KMS_KEY_ID" \
        --region "$AWS_REGION"
fi

echo ""
echo "=== Backend Setup Complete ==="
echo ""
echo "Backend Configuration:"
echo "  S3 Bucket: $STATE_BUCKET"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo "  Region: $AWS_REGION"
echo "  KMS Key ID: $KMS_KEY_ID"
echo ""
echo "Add this to your backend.tf:"
echo ""
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"$STATE_BUCKET\""
echo "    key            = \"kubernetes/production/terraform.tfstate\""
echo "    region         = \"$AWS_REGION\""
echo "    dynamodb_table = \"$DYNAMODB_TABLE\""
echo "    encrypt        = true"
echo "    kms_key_id     = \"$KMS_KEY_ID\""
echo "  }"
echo "}"
echo ""
echo "Next steps:"
echo "1. Update backend.tf with the configuration above"
echo "2. Run: terraform init -backend-config=backend.hcl"
echo "3. Run: terraform apply"
echo ""
echo "To migrate existing state:"
echo "  terraform init -migrate-state"
echo ""

# Verification
echo "Verification:"
echo "  S3 Versioning: $(aws s3api get-bucket-versioning --bucket $STATE_BUCKET --query Status --output text)"
echo "  S3 Encryption: $(aws s3api get-bucket-encryption --bucket $STATE_BUCKET --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
echo "  DynamoDB Status: $(aws dynamodb describe-table --table-name $DYNAMODB_TABLE --query Table.TableStatus --output text)"
echo ""
