# AWS Credentials Management for Kubernetes

This guide covers secure methods for managing AWS credentials in your Kubernetes cluster.

## Recommended Approaches (Best to Least Preferred)

### 1. IAM Roles for Service Accounts (IRSA) - **RECOMMENDED**

The most secure method using AWS IAM roles without storing credentials.

**Benefits:**
- No credentials stored in cluster
- Fine-grained permissions per service account
- Automatic credential rotation
- Audit trail via CloudTrail

**Setup:**
1. Enable OIDC provider for your cluster
2. Create IAM roles with trust policies
3. Annotate Kubernetes service accounts
4. Pods automatically get temporary credentials

See `irsa-setup/` directory for complete configuration.

### 2. IAM Instance Profiles - **GOOD FOR NODE-LEVEL**

Attach IAM roles directly to EC2 instances.

**Benefits:**
- No credential management needed
- Works for all pods on the node
- Simple to set up

**Limitations:**
- All pods on a node share the same permissions
- Less granular than IRSA

See `instance-profile-setup/` directory.

### 3. Kubernetes Secrets - **USE WITH CAUTION**

Store AWS credentials as Kubernetes secrets with encryption at rest.

**When to use:**
- Legacy applications that can't use IRSA
- Temporary development environments
- Third-party tools without IAM support

**Important:** Always enable encryption at rest (included in our setup).

See `secret-based-setup/` directory.

### 4. External Secrets Operator with AWS Secrets Manager - **ENTERPRISE**

Sync secrets from AWS Secrets Manager to Kubernetes.

**Benefits:**
- Centralized secret management
- Automatic rotation
- Audit logging

See `external-secrets-setup/` directory.

## Quick Start

For production, start with IRSA:
```bash
cd irsa-setup
./setup-irsa.sh
```

For testing or legacy apps:
```bash
cd secret-based-setup
kubectl apply -f aws-credentials-secret.yaml
```

## Security Best Practices

1. **Never commit credentials to git** - Use .gitignore
2. **Enable encryption at rest** - Already configured in kubeadm-config.yaml
3. **Use least privilege** - Grant only required permissions
4. **Rotate credentials regularly** - Use IRSA or Secrets Manager
5. **Enable audit logging** - Monitor credential access
6. **Use namespaces** - Isolate workloads and credentials
