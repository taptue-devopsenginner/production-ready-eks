# Terraform State Backend Setup

This directory contains configuration for Terraform remote state management with versioning and locking.

## Features

- **S3 Backend**: State stored in S3 with encryption at rest
- **Versioning**: Automatic versioning of state files (rollback capability)
- **State Locking**: DynamoDB-based locking to prevent concurrent modifications
- **Encryption**: Server-side encryption (AES256 or KMS)
- **Access Logging**: All state access logged to separate S3 bucket
- **Lifecycle Management**: Automatic cleanup of old versions
- **Point-in-Time Recovery**: DynamoDB PITR enabled

## Architecture

```
┌─────────────────┐
│  Terraform CLI  │
└────────┬────────┘
         │
         ├──────────────────────┐
         │                      │
         ▼                      ▼
┌──────────────────┐  ┌──────────────────┐
│   S3 Bucket      │  │  DynamoDB Table  │
│  (State Storage) │  │  (State Locking) │
│                  │  │                  │
│  • Versioned     │  │  • LockID (key)  │
│  • Encrypted     │  │  • Pay-per-req   │
│  • Logged        │  │  • PITR enabled  │
└──────────────────┘  └──────────────────┘
         │
         ▼
┌──────────────────┐
│   S3 Bucket      │
│  (Access Logs)   │
└──────────────────┘
```

## Setup Instructions

### Option 1: Automated Setup (Recommended)

Run the setup script to create all backend resources:

```bash
# 1. Update configuration in setup-backend.sh
vim setup-backend.sh
# Update: STATE_BUCKET, DYNAMODB_TABLE, AWS_REGION

# 2. Make executable and run
chmod +x setup-backend.sh
./setup-backend.sh

# 3. Update backend.hcl with actual values
vim backend.hcl

# 4. Initialize Terraform with backend
terraform init -backend-config=backend.hcl
```

### Option 2: Manual Setup with Terraform

If you prefer to use Terraform to create backend resources:

```bash
# 1. Create backend resources using local state
cd terraform/
terraform init
terraform apply -target=aws_s3_bucket.terraform_state
terraform apply -target=aws_s3_bucket_versioning.terraform_state
terraform apply -target=aws_dynamodb_table.terraform_state_lock
terraform apply  # Create all backend resources

# 2. Update backend.tf with actual resource names
vim backend.tf

# 3. Migrate to remote backend
terraform init -migrate-state

# 4. Confirm state was migrated
terraform state list
```

### Option 3: Manual Setup with AWS CLI

```bash
# 1. Create S3 bucket
aws s3api create-bucket \
    --bucket my-terraform-state-bucket \
    --region us-east-1

# 2. Enable versioning
aws s3api put-bucket-versioning \
    --bucket my-terraform-state-bucket \
    --versioning-configuration Status=Enabled

# 3. Enable encryption
aws s3api put-bucket-encryption \
    --bucket my-terraform-state-bucket \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

# 4. Block public access
aws s3api put-public-access-block \
    --bucket my-terraform-state-bucket \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 5. Create DynamoDB table
aws dynamodb create-table \
    --table-name terraform-state-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1

# 6. Initialize Terraform
terraform init -backend-config=backend.hcl
```

## Configuration

### Backend Configuration Files

**backend.tf** - Terraform backend configuration
**backend.hcl** - Separate config file (keeps credentials out of code)
**backend-resources.tf** - Terraform code to create backend resources

### Required AWS Resources

1. **S3 Bucket** - Stores Terraform state files
   - Versioning enabled
   - Encryption enabled (AES256 or KMS)
   - Public access blocked
   - Access logging enabled

2. **DynamoDB Table** - Provides state locking
   - Hash key: `LockID` (String)
   - Billing mode: PAY_PER_REQUEST
   - Encryption enabled
   - Point-in-time recovery enabled

3. **KMS Key** (Optional) - Additional encryption control
   - Auto-rotation enabled
   - Used for S3 and DynamoDB encryption

## Usage

### Initialize Terraform

```bash
# First time setup
terraform init -backend-config=backend.hcl

# Migrate existing state
terraform init -migrate-state

# Reconfigure backend
terraform init -reconfigure
```

### Working with State

```bash
# List resources in state
terraform state list

# Show specific resource
terraform state show aws_instance.example

# Pull current state
terraform state pull > terraform.tfstate.backup

# Push state (use with caution!)
terraform state push terraform.tfstate
```

### State Versioning

List all state versions:
```bash
aws s3api list-object-versions \
    --bucket my-terraform-state-bucket \
    --prefix kubernetes/production/terraform.tfstate
```

Restore previous version:
```bash
# Get version ID
VERSION_ID="abc123..."

# Download specific version
aws s3api get-object \
    --bucket my-terraform-state-bucket \
    --key kubernetes/production/terraform.tfstate \
    --version-id $VERSION_ID \
    terraform.tfstate.backup

# Push restored state
terraform state push terraform.tfstate.backup
```

### State Locking

Terraform automatically handles locking. If a lock is stuck:

```bash
# Force unlock (use with extreme caution!)
terraform force-unlock LOCK_ID

# Check lock status manually
aws dynamodb get-item \
    --table-name terraform-state-lock \
    --key '{"LockID": {"S": "my-terraform-state-bucket/kubernetes/production/terraform.tfstate"}}'
```

## Multi-Environment Setup

For multiple environments, use different state keys:

```hcl
# Development
key = "kubernetes/development/terraform.tfstate"

# Staging
key = "kubernetes/staging/terraform.tfstate"

# Production
key = "kubernetes/production/terraform.tfstate"
```

Or use Terraform workspaces:

```bash
# Create workspace
terraform workspace new production
terraform workspace new staging

# Switch workspace
terraform workspace select production

# List workspaces
terraform workspace list
```

## Security Best Practices

### 1. IAM Permissions

Minimum required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning"
      ],
      "Resource": "arn:aws:s3:::my-terraform-state-bucket"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-terraform-state-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    }
  ]
}
```

### 2. Bucket Policy

Enforce encryption:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-terraform-state-bucket/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    }
  ]
}
```

### 3. Access Logging

Monitor all state access:

```bash
# View recent access logs
aws s3 cp s3://my-terraform-state-logs-bucket/state-access-logs/ . --recursive

# Search for specific operations
grep "REST.GET.OBJECT" *.log
```

### 4. Encryption

Options for encryption:

**AES256** (Default, simpler):
```hcl
server_side_encryption_configuration {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

**KMS** (More control, key rotation):
```hcl
server_side_encryption_configuration {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}
```

## Disaster Recovery

### Backup Strategy

1. **S3 Versioning** - Automatic, keeps all versions
2. **Cross-Region Replication** - Optional for critical environments
3. **Regular Backups** - Pull state to local backup

```bash
# Automated backup script
#!/bin/bash
DATE=$(date +%Y%m%d-%H%M%S)
terraform state pull > backups/terraform-$DATE.tfstate
```

### Restore Procedure

**From S3 Version:**
```bash
# List versions
aws s3api list-object-versions --bucket my-terraform-state-bucket --prefix kubernetes/production/

# Restore specific version
aws s3api get-object \
    --bucket my-terraform-state-bucket \
    --key kubernetes/production/terraform.tfstate \
    --version-id VERSION_ID \
    terraform.tfstate.restored

# Apply restored state
terraform state push terraform.tfstate.restored
```

**From Local Backup:**
```bash
terraform state push backups/terraform-20260227.tfstate
```

## Troubleshooting

### Issue: "Error locking state"

**Cause:** Previous Terraform run didn't clean up lock

**Solution:**
```bash
# Check lock in DynamoDB
aws dynamodb scan --table-name terraform-state-lock

# Force unlock (if you're sure no one else is running terraform)
terraform force-unlock LOCK_ID
```

### Issue: "Failed to get existing workspaces"

**Cause:** Backend not initialized or credentials issue

**Solution:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Verify bucket access
aws s3 ls s3://my-terraform-state-bucket/

# Reinitialize
terraform init -reconfigure
```

### Issue: "Error acquiring the state lock"

**Cause:** Another process has the lock, or lock is stuck

**Solution:**
```bash
# Wait for other process to finish, or
# Check who has the lock
aws dynamodb get-item \
    --table-name terraform-state-lock \
    --key '{"LockID": {"S": "BUCKET/PATH"}}'

# Force unlock if needed
terraform force-unlock LOCK_ID
```

## Cost Optimization

### S3 Costs
- Storage: ~$0.023 per GB/month
- Versioning: Additional storage for old versions
- Lifecycle policies move old versions to cheaper storage

### DynamoDB Costs
- PAY_PER_REQUEST: $1.25 per million write requests
- Typical usage: <$1/month for small teams

### Lifecycle Policy
Automatically manages costs:
- Moves old versions to STANDARD_IA after 30 days (cheaper)
- Deletes versions older than 90 days
- Removes expired delete markers

## Monitoring

### CloudWatch Alarms

Create alarms for:

```bash
# S3 bucket size
aws cloudwatch put-metric-alarm \
    --alarm-name terraform-state-bucket-size \
    --metric-name BucketSizeBytes \
    --namespace AWS/S3 \
    --statistic Average \
    --period 86400 \
    --evaluation-periods 1 \
    --threshold 1000000000

# DynamoDB throttling
aws cloudwatch put-metric-alarm \
    --alarm-name terraform-lock-throttling \
    --metric-name UserErrors \
    --namespace AWS/DynamoDB \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 10
```

### Access Auditing

Review who accessed state:

```bash
# CloudTrail logs
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue=my-terraform-state-bucket \
    --max-results 50
```

## Best Practices

1. **Never commit state files to git** - Use .gitignore
2. **Use separate backends per environment** - Isolate dev/staging/prod
3. **Enable MFA Delete** - Extra protection for production state
4. **Regular backups** - Automate state backups
5. **Access control** - Restrict who can modify state
6. **Audit logging** - Monitor all state access
7. **Version control backend config** - But not the state itself
8. **Test disaster recovery** - Practice restoring from backups

## Migration Guide

### From Local State to Remote

```bash
# 1. Backup local state
cp terraform.tfstate terraform.tfstate.backup

# 2. Configure backend
vim backend.tf

# 3. Initialize and migrate
terraform init -migrate-state

# 4. Verify migration
terraform state list
aws s3 ls s3://my-terraform-state-bucket/kubernetes/production/

# 5. Delete local state
rm terraform.tfstate terraform.tfstate.backup
```

### From One Backend to Another

```bash
# 1. Update backend configuration
vim backend.tf

# 2. Reinitialize with migration
terraform init -migrate-state

# 3. Verify new backend
terraform state list
```

## References

- [Terraform S3 Backend Documentation](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [AWS S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
- [DynamoDB Locking](https://www.terraform.io/docs/language/settings/backends/s3.html#dynamodb-state-locking)
- [Terraform State Management Best Practices](https://www.terraform.io/docs/language/state/index.html)
