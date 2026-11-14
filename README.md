# Production-ready Amazon EKS platform

This branch is rebuilding the project around **managed Amazon EKS**, provisioned with Terraform. The first target is a development environment in **us-east-1**.

> **Status:** Terraform foundation committed; not deployed. No AWS resources have been created by this branch's implementation work.

## Architecture

- Amazon EKS managed control plane
- Three-AZ VPC with public and private subnets
- Managed EC2 node group in private subnets
- Configurable NAT topology (single NAT gateway by default for dev cost control)
- KMS encryption for Kubernetes secrets
- EKS control-plane API, audit, authenticator, controller-manager and scheduler logs
- EKS managed add-ons: VPC CNI, CoreDNS, kube-proxy, Pod Identity Agent and EBS CSI
- EBS CSI driver receives its own scoped IAM role through EKS Pod Identity
- Versioned, encrypted, public-access-blocked S3 backend with native S3 state locking

## Repository structure

```text
terraform/
├── bootstrap/remote-state/   # One-time S3 state bucket
├── modules/
│   ├── vpc/                  # Three-AZ VPC and NAT routing
│   └── eks/                  # EKS, IAM, KMS, node group and add-ons
└── environments/dev/         # us-east-1 dev composition
docs/
└── terraform-foundation.md
```

## Quick start

See [Terraform foundation guide](terraform/README.md) for prerequisites, state bootstrap, backend setup and validation steps.

1. Install Terraform >= 1.10 and AWS CLI v2.
2. Review the bootstrap stack and choose a globally unique S3 bucket name.
3. Create the remote-state bucket only after reviewing its Terraform plan.
4. Configure `terraform/environments/dev/backend.hcl` and `terraform.tfvars`.
5. Set an EKS Kubernetes version currently supported in us-east-1.
6. Run `terraform fmt -check -recursive`, `terraform validate` and security scans.
7. Review the plan and cost estimate before any apply.

**Do not run `terraform apply` until you have explicitly reviewed and approved the plan.** The EKS API endpoint is private-only by default, so administration requires private connectivity to the VPC.

## Important legacy note

Files from the original kubeadm/self-managed Kubernetes implementation remain in the repository for historical review. They are **not part of the new Terraform deployment path** and should not be used to build this EKS environment. The old README instructions were replaced by this managed-EKS guide; legacy manifests and scripts still need a separate security and cleanup review.

## Roadmap

- [x] Terraform remote-state bootstrap
- [x] Reusable three-AZ VPC module
- [x] EKS control plane and managed node group
- [x] KMS encryption, control-plane logs and baseline add-ons
- [ ] Add-on version pinning and full Terraform validation in CI
- [ ] AWS Load Balancer Controller
- [ ] GitHub Actions OIDC and Terraform plan/apply workflow
- [ ] Argo CD GitOps deployment
- [ ] Checkov, TFLint, Trivy and policy-as-code
- [ ] Prometheus/Grafana/CloudWatch observability
- [ ] Production environment and disaster-recovery documentation

## Security

Never commit credentials, bootstrap tokens, Terraform state, real `.tfvars` or private backend configuration. See [SECURITY.md](SECURITY.md) for remediation guidance.
