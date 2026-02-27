# External Secrets Operator with AWS Secrets Manager

Automatically sync secrets from AWS Secrets Manager to Kubernetes.

## How It Works

1. External Secrets Operator runs in your cluster
2. You create an `ExternalSecret` resource pointing to AWS Secrets Manager
3. Operator fetches the secret from AWS and creates a Kubernetes Secret
4. Secrets auto-sync at configured intervals (default: 1 hour)
5. Changes in AWS Secrets Manager propagate to Kubernetes automatically

## Benefits

- **Centralized management** - One source of truth in AWS
- **Automatic rotation** - Update in AWS, syncs to Kubernetes
- **Audit logging** - CloudTrail tracks all access
- **No credentials in cluster** - Uses IRSA for authentication
- **Multi-cluster** - Same secret syncs to multiple clusters
- **Version control** - AWS Secrets Manager maintains version history

## Architecture

```
AWS Secrets Manager (Source)
      ↓ (IRSA authentication)
External Secrets Operator (running in Kubernetes)
      ↓ (creates/updates)
Kubernetes Secrets (target)
      ↓ (consumed by)
Your Pods
```

## Prerequisites

- Kubernetes cluster (EKS or self-managed with OIDC)
- Helm 3.x installed
- AWS CLI configured
- kubectl access to cluster
- OIDC provider configured (for IRSA)

## Quick Start

### 1. Install External Secrets Operator

```bash
chmod +x setup-external-secrets.sh
./setup-external-secrets.sh
```

This script will:
- Install External Secrets Operator via Helm
- Create IAM policy for Secrets Manager access
- Create IAM role with IRSA
- Create ClusterSecretStore

### 2. Create Secret in AWS Secrets Manager

```bash
# Create a JSON secret
aws secretsmanager create-secret \
  --name prod/app/aws-credentials \
  --secret-string '{"access_key_id":"AKIA...","secret_access_key":"...","region":"us-east-1"}'

# Or create from file
aws secretsmanager create-secret \
  --name prod/database/config \
  --secret-string file://db-config.json
```

### 3. Create ExternalSecret Resource

```bash
kubectl apply -f external-secret-example.yaml
```

### 4. Verify Secret Was Synced

```bash
# Check ExternalSecret status
kubectl get externalsecrets
kubectl describe externalsecret aws-app-credentials

# Check if Kubernetes secret was created
kubectl get secret aws-credentials

# View secret data
kubectl get secret aws-credentials -o jsonpath='{.data}' | jq
```

## Configuration

### SecretStore vs ClusterSecretStore

**ClusterSecretStore** - Available to all namespaces:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

**SecretStore** - Namespace-scoped:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: team-secrets
  namespace: team-a
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: team-a-sa
```

### ExternalSecret Patterns

**Pattern 1: Sync specific fields**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: k8s-secret-name
  data:
  - secretKey: key-in-k8s
    remoteRef:
      key: path/in/aws/secrets-manager
      property: field-name
```

**Pattern 2: Sync entire secret**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: k8s-secret-name
  dataFrom:
  - extract:
      key: path/in/aws/secrets-manager
```

**Pattern 3: Template transformation**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: k8s-secret-name
    template:
      engineVersion: v2
      data:
        config.yaml: |
          database:
            host: {{ .db_host }}
            password: {{ .db_password }}
  dataFrom:
  - extract:
      key: prod/database/config
```

## AWS Secrets Manager Setup

### Secret Naming Convention

Use hierarchical paths:
```
prod/app/aws-credentials
prod/database/postgres
prod/api/external-keys
staging/app/config
dev/app/config
```

### Create Secrets

**Simple key-value:**
```bash
aws secretsmanager create-secret \
  --name prod/app/api-key \
  --secret-string "sk_live_1234567890"
```

**JSON object:**
```bash
aws secretsmanager create-secret \
  --name prod/database/postgres \
  --secret-string '{
    "username": "admin",
    "password": "supersecret",
    "host": "db.example.com",
    "port": "5432",
    "database": "myapp"
  }'
```

**From file:**
```bash
aws secretsmanager create-secret \
  --name prod/app/config \
  --secret-string file://config.json
```

### Update Secrets

```bash
# Update secret value
aws secretsmanager update-secret \
  --secret-id prod/app/api-key \
  --secret-string "sk_live_new_key"

# Updates automatically sync to Kubernetes
# Wait for refresh interval or force sync by deleting pod
```

### Automatic Rotation

Enable automatic rotation for database credentials:

```bash
aws secretsmanager rotate-secret \
  --secret-id prod/database/postgres \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:123456789012:function:SecretsManagerRotation \
  --rotation-rules AutomaticallyAfterDays=30
```

External Secrets Operator will sync rotated values automatically.

## Using Synced Secrets in Pods

Once synced, use like any Kubernetes secret:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-config  # Created by ExternalSecret
          key: password
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: aws-credentials
          key: access_key_id
```

Or mount as volume:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: secrets
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secrets
    secret:
      secretName: aws-credentials
```

## Refresh Intervals

Control sync frequency:

```yaml
spec:
  refreshInterval: 1h   # Every hour (default)
  # Other options:
  # 5m    - Every 5 minutes
  # 30m   - Every 30 minutes
  # 24h   - Once per day
```

**Trade-offs:**
- Shorter intervals = faster updates, more API calls, higher cost
- Longer intervals = delayed updates, fewer API calls, lower cost

**Best practice:** Use 1h for most secrets, 15m for frequently rotated credentials.

## Advanced Features

### Multiple Regions

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-us-west
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2  # Different region
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

### Secret Versioning

Fetch specific version:
```yaml
data:
- secretKey: password
  remoteRef:
    key: prod/database/postgres
    property: password
    version: AWSCURRENT  # or specific version ID
```

### Conditional Sync

Sync only if secret exists:
```yaml
spec:
  target:
    creationPolicy: Orphan  # Don't create if doesn't exist
    deletionPolicy: Retain  # Keep secret if ExternalSecret deleted
```

## Monitoring

### Check ExternalSecret Status

```bash
# List all ExternalSecrets
kubectl get externalsecrets --all-namespaces

# Detailed status
kubectl describe externalsecret aws-app-credentials

# Watch for changes
kubectl get externalsecrets -w
```

### Check Operator Logs

```bash
kubectl logs -n external-secrets-system \
  -l app.kubernetes.io/name=external-secrets \
  --tail=100 -f
```

### Metrics

External Secrets Operator exports Prometheus metrics:
- `externalsecret_sync_calls_total`
- `externalsecret_sync_calls_error`
- `externalsecret_status_condition`

## Troubleshooting

### ExternalSecret not syncing

**Check status:**
```bash
kubectl describe externalsecret my-secret
```

**Common issues:**
- IAM role lacks Secrets Manager permissions
- Secret doesn't exist in AWS
- Wrong secret path or property name
- IRSA not configured correctly

**Verify IAM permissions:**
```bash
# Test from operator pod
kubectl exec -n external-secrets-system \
  deployment/external-secrets -- \
  aws secretsmanager get-secret-value \
    --secret-id prod/app/aws-credentials
```

### Permission denied errors

Check IAM policy has required permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:GetSecretValue",
    "secretsmanager:DescribeSecret"
  ],
  "Resource": "*"
}
```

Or restrict to specific secrets:
```json
{
  "Resource": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/*"
}
```

### Secret not updating after AWS change

- Check refresh interval
- Force update: Delete ExternalSecret and recreate
- Or delete the pod to fetch updated secret

### Operator not starting

```bash
# Check operator status
kubectl get pods -n external-secrets-system

# View logs
kubectl logs -n external-secrets-system \
  -l app.kubernetes.io/name=external-secrets
```

## Security Best Practices

1. **Use IRSA** - Never use static credentials for operator
2. **Least privilege IAM** - Grant access only to required secrets
3. **Namespace isolation** - Use SecretStore per namespace/team
4. **Regular rotation** - Enable automatic rotation in AWS
5. **Audit logging** - Monitor CloudTrail for secret access
6. **Encryption at rest** - Already enabled in kubeadm-config.yaml
7. **RBAC restrictions** - Limit who can create ExternalSecrets

## Cost Considerations

AWS Secrets Manager pricing:
- $0.40 per secret per month
- $0.05 per 10,000 API calls

With 10 secrets and 1h refresh:
- Storage: 10 × $0.40 = $4/month
- API calls: 10 × 24 × 30 = 7,200 calls = $0.04/month
- **Total: ~$4.04/month**

Much cheaper than managing manual rotation!

## Comparison: External Secrets vs IRSA

| Feature | External Secrets | IRSA |
|---------|-----------------|------|
| Best for | Static secrets (keys, passwords) | AWS API access |
| Rotation | Centralized in AWS | Automatic (temporary creds) |
| Multi-cloud | Yes (supports GCP, Azure) | AWS only |
| Setup complexity | Medium | Low |
| Operational overhead | Requires operator | None |
| Cost | API calls + storage | Free |

**Recommendation:** Use both!
- IRSA for AWS service access (S3, DynamoDB, etc.)
- External Secrets for static credentials (API keys, passwords)

## Migration from Kubernetes Secrets

1. Create secrets in AWS Secrets Manager
2. Create ExternalSecret resources
3. Verify secrets sync correctly
4. Update pods to use new secret names (if changed)
5. Delete old Kubernetes secrets
6. Remove manual secret creation from CI/CD

No downtime needed!
