# EKS Terraform foundation — dev / us-east-1

The foundation is organized as reusable VPC and EKS modules plus a dev root module. The VPC spans three Availability Zones. Public subnets are intended for internet-facing load balancers; private subnets host managed worker nodes. The EKS API endpoint is private-only by default.

## Security baseline

- No AWS credentials are stored in this repository.
- Terraform state uses an S3 bucket with versioning, server-side encryption and public-access blocking.
- Native S3 state locking (`use_lockfile = true`) is enabled for the dev backend.
- EKS Kubernetes secrets use a customer-managed KMS key.
- EKS control-plane API, audit, authenticator, controller-manager and scheduler logs are enabled.
- Worker nodes run in private subnets and use a dedicated IAM role.
- EKS Pod Identity Agent and EBS CSI managed add-ons are declared.

## Follow-up hardening

1. Add AWS Load Balancer Controller with a dedicated Pod Identity role.
2. Add Argo CD and GitHub Actions OIDC federation.
3. Add Checkov, TFLint, Trivy, image signing and policy-as-code.
4. Add Pod Security Admission labels, network policies, quotas and workload examples.
5. Add production environment with per-AZ NAT gateways, explicit API endpoint allowlists, workload-specific node pools and tested backup/restore.
6. Validate the selected Kubernetes and managed add-on versions against the live EKS support matrix before provisioning.

This is an initial dev foundation, not yet a complete production platform. No AWS resources were deployed as part of this work.
