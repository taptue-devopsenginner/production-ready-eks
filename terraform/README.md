# Terraform foundation

This branch adds an infrastructure-as-code foundation for an Amazon EKS **dev** environment in **us-east-1**. It has not been applied; no AWS resources have been created by this work.

## Layout

- `bootstrap/remote-state`: one-time S3 state bucket with versioning, encryption and public-access blocking.
- `modules/vpc`: three-AZ VPC, public/private subnets, internet gateway and configurable NAT topology.
- `modules/eks`: EKS control plane, KMS secret encryption, control-plane logs, managed node group and managed add-ons.
- `environments/dev`: dev root module composing VPC and EKS.

## Prerequisites

- Terraform >= 1.10
- AWS CLI v2 and an authenticated AWS identity with provisioning permissions
- A globally unique S3 bucket name for Terraform state
- An EKS Kubernetes version currently supported in `us-east-1`

Do not commit AWS keys, Terraform state, real `.tfvars`, or private backend configuration.

## Bootstrap remote state

The bootstrap stack deliberately uses local state for its one-time creation. Only run these commands when you decide to create the state bucket:

```bash
cd terraform/bootstrap/remote-state
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set a globally unique bucket name.
terraform init
terraform fmt -recursive
terraform validate
terraform plan
# Review the plan and costs before any apply.
```

After the bucket exists, configure the dev backend:

```bash
cd ../../environments/dev
cp backend.hcl.example backend.hcl
# Replace the bucket value in backend.hcl.
cp terraform.tfvars.example terraform.tfvars
# Set kubernetes_version to an EKS version supported in us-east-1.
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan
```

Do not run `terraform apply` until the account, plan, cost estimate, region and security posture have been reviewed and explicitly approved.

## Dev topology and trade-offs

- EKS API endpoint is private-only by default. Run Terraform and Kubernetes administration from a network with private VPC connectivity (for example VPN or an SSM-managed administration host). Public endpoint access can be enabled deliberately with a trusted CIDR allowlist.
- Worker nodes are placed in private subnets.
- One NAT gateway is enabled by default to reduce dev cost; this is not AZ-resilient. Set `single_nat_gateway = false` to provision one NAT gateway per AZ.
- The managed node group defaults to two `t3.large` instances. Review workload sizing and EC2 pricing before applying.
- Control-plane logs are retained for 30 days; Kubernetes secrets use a customer-managed KMS key.
- The EBS CSI add-on is included. Its Pod Identity role association is a prerequisite for granting the driver scoped EBS permissions.

## Validation

Run `terraform fmt -check -recursive`, initialize and validate each root module, and run Checkov/tflint before any apply. Provider and backend initialization may require network access. This repository change itself did not execute Terraform or contact AWS.
