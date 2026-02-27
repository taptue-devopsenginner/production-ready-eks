# AWS Credentials as Kubernetes Secrets

Store AWS credentials in Kubernetes secrets with encryption at rest.

## ⚠️ Security Warning

**This method stores long-lived credentials in your cluster. For production use:**
1. Prefer IRSA (IAM Roles for Service Accounts) - See `../irsa-setup/`
2. Use AWS Secrets Manager with External Secrets Operator - See `../external-secrets-setup/`
3. Only use secrets for legacy apps that can't support IRSA

## When to Use

**Acceptable for:**
- Development and testing environments
- Legacy applications that require static credentials
- Third-party tools without IAM support
- Quick prototypes

**Not recommended for:**
- Production applications (use IRSA)
- Multi-tenant clusters
- Compliance-sensitive workloads
- Long-term deployments

## Security Measures

This setup includes:
- Encryption at rest (configured in `kubeadm-config.yaml`)
- RBAC restrictions on secret access
- No credentials in git (using .gitignore)
- Environment variable injection (not mounting as files)

## Setup Methods

### Method 1: From Environment Variables (Recommended)

```bash
# Set credentials in your shell (NOT in scripts!)
export AWS_ACCESS_KEY_ID='your-access-key'
export AWS_SECRET_ACCESS_KEY='your-secret-key'
export AWS_DEFAULT_REGION='us-east-1'

# Create secret
chmod +x create-secret.sh
./create-secret.sh
```

### Method 2: From AWS CLI Profile

```bash
# Extract from AWS CLI config
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
export AWS_DEFAULT_REGION=$(aws configure get region)

# Create secret
./create-secret.sh
```

### Method 3: Manual kubectl Command

```bash
kubectl create secret generic aws-credentials \
  --namespace=default \
  --from-literal=aws_access_key_id='AKIAIOSFODNN7EXAMPLE' \
  --from-literal=aws_secret_access_key='wJalrXUtnFEMI/K7MDENG/bPxRfiCY' \
  --from-literal=aws_region='us-east-1'
```

### Method 4: From YAML (Not Recommended)

Edit `aws-credentials-secret.yaml` and apply:
```bash
# WARNING: Don't commit credentials to git!
kubectl apply -f aws-credentials-secret.yaml
```

## Using in Pods

### Environment Variables (Recommended)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: your-app:latest
    env:
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: aws-credentials
          key: aws_access_key_id
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: aws-credentials
          key: aws_secret_access_key
    - name: AWS_DEFAULT_REGION
      valueFrom:
        secretKeyRef:
          name: aws-credentials
          key: aws_region
```

### Volume Mount (Alternative)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: your-app:latest
    volumeMounts:
    - name: aws-creds
      mountPath: "/root/.aws"
      readOnly: true
  volumes:
  - name: aws-creds
    secret:
      secretName: aws-credentials
      items:
      - key: aws_access_key_id
        path: credentials
```

## Testing

Test that credentials work:

```bash
kubectl run aws-test --rm -it --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=$(kubectl get secret aws-credentials -o jsonpath='{.data.aws_access_key_id}' | base64 -d)" \
  --env="AWS_SECRET_ACCESS_KEY=$(kubectl get secret aws-credentials -o jsonpath='{.data.aws_secret_access_key}' | base64 -d)" \
  --env="AWS_DEFAULT_REGION=$(kubectl get secret aws-credentials -o jsonpath='{.data.aws_region}' | base64 -d)" \
  -- aws sts get-caller-identity
```

## Namespace Isolation

Create secrets per namespace for isolation:

```bash
# Production namespace
kubectl create namespace production
kubectl create secret generic aws-credentials \
  --namespace=production \
  --from-literal=aws_access_key_id='PROD_KEY' \
  --from-literal=aws_secret_access_key='PROD_SECRET' \
  --from-literal=aws_region='us-east-1'

# Development namespace
kubectl create namespace development
kubectl create secret generic aws-credentials \
  --namespace=development \
  --from-literal=aws_access_key_id='DEV_KEY' \
  --from-literal=aws_secret_access_key='DEV_SECRET' \
  --from-literal=aws_region='us-west-2'
```

## Rotating Credentials

1. Create new IAM access key in AWS Console
2. Update the secret:
```bash
kubectl create secret generic aws-credentials \
  --namespace=default \
  --from-literal=aws_access_key_id='NEW_KEY' \
  --from-literal=aws_secret_access_key='NEW_SECRET' \
  --from-literal=aws_region='us-east-1' \
  --dry-run=client -o yaml | kubectl apply -f -
```
3. Restart pods to pick up new credentials:
```bash
kubectl rollout restart deployment/my-app
```
4. Delete old IAM key in AWS Console

## RBAC Restrictions

Limit who can read secrets:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["aws-credentials"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-aws-creds
  namespace: default
subjects:
- kind: ServiceAccount
  name: my-app-sa
  namespace: default
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

## Viewing Secrets (Admin Only)

```bash
# List secrets
kubectl get secrets -n default

# View secret contents (base64 encoded)
kubectl get secret aws-credentials -o yaml

# Decode a value
kubectl get secret aws-credentials -o jsonpath='{.data.aws_access_key_id}' | base64 -d
```

## Best Practices

1. **Use read-only credentials** - Create IAM user with minimal permissions
2. **Rotate regularly** - Change credentials every 90 days
3. **Enable encryption at rest** - Already configured in kubeadm-config.yaml
4. **Use namespace isolation** - Different secrets per namespace
5. **Audit access** - Enable audit logging to track secret access
6. **Never commit to git** - Use .gitignore (already configured)
7. **Restrict RBAC** - Limit who can read secrets
8. **Monitor usage** - CloudTrail logs show credential usage

## Migration to IRSA

When ready for production, migrate to IRSA:

1. Set up IRSA (see `../irsa-setup/`)
2. Update pods to use service accounts
3. Test thoroughly
4. Delete Kubernetes secrets
5. Delete IAM user credentials

This eliminates long-lived credentials entirely!

## Troubleshooting

**Secret not found:**
```bash
kubectl get secrets -n default | grep aws-credentials
```

**Wrong namespace:**
```bash
# Secrets are namespace-scoped
kubectl get secret aws-credentials -n your-namespace
```

**Permission denied:**
- Check RBAC: Does service account have access?
- Check IAM: Are credentials valid?
- Check CloudTrail: What errors appear?

**Pods not using credentials:**
- Check environment variables: `kubectl exec pod -- env | grep AWS`
- Restart pods after secret changes
- Verify secret name matches in pod spec
