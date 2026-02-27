# IAM Instance Profiles for Kubernetes Nodes

Attach IAM roles directly to EC2 instances running Kubernetes.

## How It Works

1. IAM role is created with required AWS permissions
2. Instance profile is created and linked to the role
3. EC2 instances are launched with the instance profile
4. All pods on the instance can use these credentials via instance metadata service

## When to Use

**Good for:**
- Node-level operations (EBS volumes, Load Balancers)
- Legacy applications that can't use IRSA
- Simple setups where all pods need same permissions
- Quick development/testing environments

**Not ideal for:**
- Multi-tenant clusters (all pods share permissions)
- Fine-grained access control per application
- Security-sensitive production workloads (use IRSA instead)

## Prerequisites

- AWS CLI configured with admin access
- EC2 instances for your Kubernetes nodes

## Setup Steps

### 1. Update Configuration

Edit `setup-instance-profile.sh`:
```bash
ROLE_NAME="k8s-node-role"
POLICY_NAME="k8s-node-policy"
INSTANCE_PROFILE_NAME="k8s-node-instance-profile"
AWS_ACCOUNT_ID="123456789012"
```

### 2. Update IAM Policy

Edit `node-iam-policy.json` with required permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::your-bucket/*"
    }
  ]
}
```

The default policy includes:
- EC2 operations (for EBS CSI driver)
- ELB operations (for LoadBalancer services)
- ECR access (for pulling container images)
- S3 access (customize to your buckets)

### 3. Run Setup Script

```bash
chmod +x setup-instance-profile.sh
./setup-instance-profile.sh
```

### 4. Attach to EC2 Instances

**For existing instances:**
```bash
aws ec2 associate-iam-instance-profile \
  --instance-id i-1234567890abcdef0 \
  --iam-instance-profile Name=k8s-node-instance-profile
```

**For new instances (in launch template):**
```json
{
  "IamInstanceProfile": {
    "Name": "k8s-node-instance-profile"
  }
}
```

**For Terraform:**
```hcl
resource "aws_instance" "k8s_node" {
  ami           = "ami-12345678"
  instance_type = "t3.medium"
  iam_instance_profile = "k8s-node-instance-profile"
}
```

### 5. Verify

On the EC2 instance, verify the role is attached:
```bash
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

Test AWS access:
```bash
aws sts get-caller-identity
aws s3 ls
```

## Using in Pods

Pods automatically use the instance profile credentials. No configuration needed!

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: aws-test
spec:
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["aws", "s3", "ls"]
```

The pod will use the EC2 instance's IAM role automatically.

## Security Considerations

**Limitations:**
- All pods on a node share the same permissions
- Any pod can access any AWS resource the node can access
- No per-application isolation

**Mitigation:**
- Use IRSA for production workloads requiring isolation
- Use instance profiles only for node-level operations
- Combine with IRSA: instance profile for infrastructure, IRSA for applications
- Use Pod Security Policies to restrict hostNetwork pods

## Best Practices

1. **Minimal permissions** - Grant only what nodes need for infrastructure
2. **Separate worker and master roles** - Masters need different permissions
3. **Regular audits** - Review CloudTrail logs for unauthorized access
4. **Combine with IRSA** - Use instance profiles for infrastructure, IRSA for apps
5. **Use for infrastructure only** - EBS, ELB, CloudWatch, not application access

## Common Permissions

**Worker Nodes:**
- EBS CSI driver: EC2 volume operations
- ELB controller: LoadBalancer operations
- CloudWatch: Metrics and logs
- ECR: Pull container images

**Master Nodes:**
- All worker permissions
- Additional control plane operations
- AWS Cloud Controller Manager permissions

## Troubleshooting

**Pods can't access AWS:**
- Verify instance profile is attached: Check EC2 console or use AWS CLI
- Check IAM policy: Ensure required permissions are granted
- Test from instance: SSH to node and test `aws` commands
- Check metadata service: `curl http://169.254.169.254/latest/meta-data/`

**Permission denied:**
- Review IAM policy for missing permissions
- Check CloudTrail logs for detailed error messages
- Verify policy is attached to role

**Instance profile not found:**
- Ensure instance profile exists: `aws iam get-instance-profile`
- Check role is added to instance profile
- Wait a few seconds after attaching (eventual consistency)
