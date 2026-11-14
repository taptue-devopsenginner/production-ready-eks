# Security policy and legacy repository remediation

## Reporting

Do not publish credentials, tokens, private keys, account identifiers or sensitive infrastructure details in issues. Use GitHub's private vulnerability reporting where enabled.

## Legacy repository warning

The original public repository included a kubeadm bootstrap token and HAProxy statistics credentials in tracked configuration. Treat any credential that was ever valid as compromised:

1. Revoke or rotate the kubeadm bootstrap token and any associated certificate key.
2. Rotate the HAProxy statistics password and any other secrets that may have been reused.
3. Review access logs and infrastructure for unauthorized use.
4. Remove secrets from current tracked files and, where appropriate, rewrite Git history after coordinating with collaborators.
5. Store future secrets in AWS Secrets Manager or another approved secret manager; never commit them.

Deleting a secret from the latest commit does not invalidate it and does not remove it from Git history, forks or clones. Rotation is the first priority.

The historical kubeadm manifests and scripts are not used by the new Terraform EKS deployment. They remain pending a separate review and cleanup; do not deploy them.
