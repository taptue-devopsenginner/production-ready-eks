# IAM Roles for Service Accounts (IRSA)

The most secure way to provide AWS credentials to Kubernetes pods.

## How It Works

1. AWS creates an OIDC identity provider for your cluster
2. IAM roles trust this OIDC provider
3. Kubernetes service accounts are annotated with IAM role ARNs
4. Pods using these service accounts automatically get temporary AWS credentials
5. AWS SDKs automatically detect and use these credentials

## Prerequisites

- EKS cluster or self-managed cluster with OIDC provider configured
- AWS CLI installed and configured
- kubectl access to your cluster
- eksctl installed (for easy OIDC setup)

## Setup Steps

### 1. Update Configuration

Edit `setup-irsa.sh` and update these variables:
```bash
CLUSTER_NAME="my-k8s-cluster"
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-1"
NAMESPACE="default"
SERVICE_ACCOUNT_NAME="my-app-sa"
IAM_ROLE_NAME="my-app-role"
IAM_POLICY_NAME="my-app-policy"
```

### 2. Update IAM Policy

Edit `irsa-policy.json` with the AWS permissions your application needs:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::your-bucket/*"
    }
  ]
}
```

### 3. Run Setup Script

```bash
chmod +x setup-irsa.sh
./setup-irsa.sh
```

This script will:
- Create OIDC identity provider
- Create IAM policy
- Create IAM role with trust relationship
- Attach policy to role
- Create Kubernetes service account

### 4. Use in Your Pods

Add the service account to your pod/deployment spec:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app-sa
  containers:
  - name: app
    image: your-app:latest
    env:
    - name: AWS_REGION
      value: us-east-1
```

That's it! Your application can now use AWS SDK without any credentials.

## Testing

Test that IRSA is working:

```bash
kubectl run test-irsa --rm -it \
  --image=amazon/aws-cli:latest \
  --serviceaccount=my-app-sa \
  -- aws sts get-caller-identity
```

You should see output showing the IAM role ARN.

## Application Code

No code changes needed! AWS SDKs automatically detect IRSA credentials:

**Python (boto3):**
```python
import boto3
s3 = boto3.client('s3')  # Automatically uses IRSA
s3.list_buckets()
```

**Node.js (AWS SDK):**
```javascript
const AWS = require('aws-sdk');
const s3 = new AWS.S3();  // Automatically uses IRSA
s3.listBuckets().promise();
```

**Go (AWS SDK):**
```go
import "github.com/aws/aws-sdk-go/aws/session"
sess := session.Must(session.NewSession())  // Automatically uses IRSA
```

## Troubleshooting

**Pod can't assume role:**
- Check service account annotation: `kubectl get sa my-app-sa -o yaml`
- Verify IAM role trust policy includes correct OIDC provider and service account
- Check pod logs for AWS SDK errors

**Permission denied:**
- Verify IAM policy has required permissions
- Check IAM role is attached to correct policy
- Test with `aws sts get-caller-identity` first

**OIDC provider not found:**
- Ensure OIDC provider is created for your cluster
- Run: `aws iam list-open-id-connect-providers`

## Best Practices

1. **One role per service account** - Different apps need different permissions
2. **Least privilege** - Grant only required permissions
3. **Use namespaces** - Isolate service accounts by namespace
4. **Audit regularly** - Review IAM policies and CloudTrail logs
5. **Rotate nothing** - IRSA uses temporary credentials that auto-rotate

## Multiple Service Accounts

For multiple applications, repeat the process with different names:

```bash
# App 1: S3 access
IAM_ROLE_NAME="s3-app-role"
SERVICE_ACCOUNT_NAME="s3-app-sa"

# App 2: DynamoDB access
IAM_ROLE_NAME="dynamodb-app-role"
SERVICE_ACCOUNT_NAME="dynamodb-app-sa"
```

Each app gets its own minimal permissions.
