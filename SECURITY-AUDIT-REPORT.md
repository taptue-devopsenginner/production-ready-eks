# Kubernetes Infrastructure Security Audit Report

**Date:** 2026-02-27
**Cluster:** Production Kubernetes on AWS (2 Masters, 5 Workers)
**Severity Levels:** CRITICAL | HIGH | MEDIUM | LOW | INFO

---

## Executive Summary

This security audit identified **8 vulnerabilities** across configuration files, including **2 CRITICAL**, **3 HIGH**, **2 MEDIUM**, and **1 LOW** severity issues. Immediate action is required for critical vulnerabilities before production deployment.

---

## Critical Vulnerabilities

### 1. HARDCODED BOOTSTRAP TOKEN IN CONFIGURATION
**File:** `kubeadm-config.yaml`
**Line:** 8
**Severity:** CRITICAL
**CWE:** CWE-798 (Use of Hard-coded Credentials)

**Issue:**
```yaml
token: abcdef.0123456789abcdef
```

The bootstrap token is hardcoded in the configuration file. This token is used for node authentication during cluster join operations.

**Risk:**
- Anyone with access to this file can join malicious nodes to the cluster
- Token could be committed to version control
- No token rotation mechanism

**Recommendation:**
- Generate unique tokens dynamically during cluster initialization
- Use `kubeadm token create` to generate tokens at runtime
- Set short TTL (1-2 hours) for bootstrap tokens
- Never commit tokens to git

**Fix:**
```bash
# Generate token dynamically
TOKEN=$(kubeadm token generate)
sed -i "s/abcdef.0123456789abcdef/${TOKEN}/" kubeadm-config.yaml
```

---

### 2. DEFAULT HAPROXY STATS CREDENTIALS
**File:** `haproxy-loadbalancer.cfg`
**Line:** 43
**Severity:** CRITICAL
**CWE:** CWE-798 (Use of Hard-coded Credentials)

**Issue:**
```
stats auth admin:changeme
```

Default credentials for HAProxy statistics page are exposed.

**Risk:**
- Attackers can access HAProxy statistics and monitoring
- Reveals backend server IPs and health status
- Could be used to gather information for attacks
- Statistics page accessible on port 8404

**Recommendation:**
- Change default credentials immediately
- Use strong, randomly generated passwords
- Restrict access to stats page by IP address
- Consider disabling stats page in production
- Enable HTTPS for stats endpoint

**Fix:**
```cfg
stats auth admin:$(openssl rand -base64 32)
# Or restrict by IP
acl allowed_ips src 10.0.0.0/8
http-request deny unless allowed_ips
```

---

## High Severity Vulnerabilities

### 3. EXAMPLE AWS CREDENTIALS IN SECRET FILE
**File:** `secret-based-setup/aws-credentials-secret.yaml`
**Lines:** 14-15
**Severity:** HIGH
**CWE:** CWE-798 (Use of Hard-coded Credentials)

**Issue:**
```yaml
aws_access_key_id: "AKIAIOSFODNN7EXAMPLE"
aws_secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

While these are AWS example credentials, the file structure encourages hardcoding real credentials.

**Risk:**
- Users may replace with real credentials and commit to git
- Credentials visible in plain text in the file
- No encryption until applied to cluster
- Risk of accidental exposure

**Recommendation:**
- NEVER use this method in production
- Use IRSA (IAM Roles for Service Accounts) instead
- If secrets must be used, create them dynamically from environment variables
- Use External Secrets Operator with AWS Secrets Manager
- Add this file to .gitignore

**Fix:**
```bash
# Use the provided script instead
export AWS_ACCESS_KEY_ID='real-key'
export AWS_SECRET_ACCESS_KEY='real-secret'
./secret-based-setup/create-secret.sh
```

---

### 4. PLACEHOLDER ENCRYPTION KEY IN CONFIG
**File:** `encryption-config.yaml`
**Line:** 12
**Severity:** HIGH
**CWE:** CWE-321 (Use of Hard-coded Cryptographic Key)

**Issue:**
```yaml
secret: <BASE64_ENCODED_SECRET>
```

Placeholder value for encryption key that must be replaced.

**Risk:**
- If not replaced, secrets encryption will fail
- Weak or default keys could be used
- Key visible in configuration file
- No key rotation mechanism

**Recommendation:**
- Generate strong 32-byte random key before deployment
- Never commit the actual key to version control
- Store encryption key securely (AWS Secrets Manager, Vault)
- Implement key rotation strategy
- Verify encryption is working after deployment

**Fix:**
```bash
# Generate strong encryption key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
sed -i "s/<BASE64_ENCODED_SECRET>/${ENCRYPTION_KEY}/" encryption-config.yaml
# Store key securely
aws secretsmanager create-secret --name k8s-encryption-key --secret-string "$ENCRYPTION_KEY"
```

---

### 5. NGINX INGRESS SNIPPET ANNOTATIONS ENABLED
**File:** `ingress-nginx.yaml`
**Line:** 31
**Severity:** HIGH
**CWE:** CWE-94 (Improper Control of Generation of Code)

**Issue:**
```yaml
allow-snippet-annotations: "true"
```

Allows users to inject arbitrary nginx configuration via annotations.

**Risk:**
- Code injection vulnerability (CVE-2021-25742)
- Malicious users can execute arbitrary nginx directives
- Bypass security policies and access controls
- Potential for data exfiltration or privilege escalation
- Known to be exploited in the wild

**Recommendation:**
- Set `allow-snippet-annotations: "false"` immediately
- Only enable if absolutely required and with strict RBAC controls
- Use ConfigMaps for custom nginx configuration instead
- Monitor for suspicious ingress annotations
- Keep NGINX Ingress Controller updated

**Fix:**
```yaml
data:
  allow-snippet-annotations: "false"  # Changed from "true"
```

**Reference:** [CVE-2021-25742](https://github.com/kubernetes/ingress-nginx/issues/7837)

---

## Medium Severity Vulnerabilities

### 6. OVERLY PERMISSIVE BIND ADDRESSES
**File:** `kubeadm-config.yaml`
**Lines:** 14, 29, 33
**Severity:** MEDIUM
**CWE:** CWE-200 (Exposure of Sensitive Information)

**Issue:**
```yaml
advertiseAddress: 0.0.0.0
bind-address: 0.0.0.0
```

Components bound to all interfaces (0.0.0.0) instead of specific IPs.

**Risk:**
- Services accessible from unintended networks
- Increased attack surface
- Potential exposure to internet if firewall misconfigured
- Metrics endpoints exposed

**Recommendation:**
- Bind to specific private IP addresses
- Use security groups to restrict access
- Implement network policies
- Regular firewall rule audits

**Fix:**
```yaml
advertiseAddress: 10.0.10.10  # Master node private IP
bind-address: 10.0.10.10
```

---

### 7. PRIVILEGED POD SECURITY POLICY TOO PERMISSIVE
**File:** `pod-security-policy.yaml`
**Lines:** 38-63
**Severity:** MEDIUM
**CWE:** CWE-269 (Improper Privilege Management)

**Issue:**
The privileged PSP allows:
- Host network, PID, IPC access
- All capabilities
- Privileged containers
- All volume types

**Risk:**
- Containers can escape to host
- Access to host resources
- Privilege escalation
- Only needed for specific system pods

**Recommendation:**
- Limit privileged PSP to system namespaces only (kube-system)
- Remove `system:serviceaccounts:kube-system` from binding
- Use per-service account bindings instead
- Migrate to Pod Security Standards (PSP is deprecated)
- Audit which pods actually need privileged access

**Fix:**
```yaml
subjects:
# Remove this broad binding:
# - kind: Group
#   name: system:serviceaccounts:kube-system
# Add specific service accounts:
- kind: ServiceAccount
  name: calico-node
  namespace: kube-system
- kind: ServiceAccount
  name: aws-cloud-controller-manager
  namespace: kube-system
```

---

## Low Severity Vulnerabilities

### 8. INGRESS CONTROLLER PRIVILEGE ESCALATION ENABLED
**File:** `ingress-nginx.yaml`
**Line:** 227
**Severity:** LOW
**CWE:** CWE-250 (Execution with Unnecessary Privileges)

**Issue:**
```yaml
allowPrivilegeEscalation: true
```

While needed for NET_BIND_SERVICE capability, it should be documented why.

**Risk:**
- Container can gain more privileges than initially granted
- Required for binding to ports 80/443
- Mitigated by dropping all other capabilities

**Recommendation:**
- Keep current setting (required for functionality)
- Add comment explaining why it's needed
- Ensure container runs as non-root user (runAsUser: 101 is set)
- Monitor for privilege escalation attempts
- Consider using Kubernetes 1.22+ NET_BIND_SERVICE without escalation

**Acceptable as-is** due to:
- runAsUser: 101 (non-root)
- All capabilities dropped except NET_BIND_SERVICE
- Required for ingress functionality

---

## Additional Security Recommendations

### 1. Missing Security Configurations

**Network Policies:**
- No NetworkPolicy definitions found
- Implement zero-trust network policies
- Restrict pod-to-pod communication
- Isolate namespaces

**Resource Limits:**
- Ingress controller has limits (good)
- Add limits to all workloads
- Prevent resource exhaustion attacks

**Image Security:**
- No image pull policies for some resources
- Use specific image tags, not :latest
- Implement image scanning (Trivy, Anchore)
- Use private registries with vulnerability scanning

### 2. Logging and Monitoring

**Audit Logging:**
- Audit logging is enabled (good)
- Configure audit policy for sensitive operations
- Ship logs to external SIEM
- Monitor for suspicious activities

**Monitoring:**
- Metrics server is included (good)
- Add Prometheus for detailed metrics
- Implement alerting for security events
- Monitor pod security policy violations

### 3. Secrets Management

**Current State:**
- Encryption at rest configured (good)
- IRSA setup provided (excellent)
- Multiple credential methods offered

**Recommendations:**
- Use IRSA exclusively in production
- Implement External Secrets Operator
- Rotate secrets regularly
- Audit secret access

### 4. RBAC Hardening

**Current State:**
- RBAC enabled
- PSP configured
- Service accounts created

**Recommendations:**
- Audit RBAC permissions regularly
- Implement least privilege principle
- Remove default service account tokens
- Use separate service accounts per application

### 5. API Server Security

**Current State:**
- Anonymous auth disabled (good)
- Webhook authorization enabled (good)
- Admission controllers enabled

**Recommendations:**
- Enable additional admission controllers:
  - AlwaysPullImages
  - PodSecurityPolicy (or PodSecurity in K8s 1.25+)
  - ResourceQuota
- Implement API rate limiting
- Use API priority and fairness

### 6. etcd Security

**Current State:**
- etcd data directory configured
- Metrics exposed

**Recommendations:**
- Enable etcd TLS encryption
- Restrict etcd metrics access (currently 0.0.0.0:2381)
- Implement etcd backup strategy
- Encrypt etcd backups
- Use separate disk for etcd data

### 7. Container Runtime Security

**Current State:**
- Containerd configured with systemd cgroup
- CRI socket configured

**Recommendations:**
- Enable containerd runtime encryption
- Configure seccomp profiles
- Use RuntimeClass for workload isolation
- Enable AppArmor/SELinux

---

## Compliance Considerations

### CIS Kubernetes Benchmark
- **1.2.1**: Anonymous authentication disabled ✓
- **1.2.6**: Kubelet auth enabled ✓
- **1.2.15**: Admission controllers enabled ✓
- **3.2.1**: Audit logging enabled ✓
- **5.1.5**: Default service accounts restricted ⚠ (needs review)
- **5.2.6**: PSP enabled ✓
- **5.7.3**: Network policies missing ✗

### NIST 800-190 Container Security
- **Image security**: Needs improvement
- **Runtime defense**: Partially implemented
- **Network isolation**: Missing network policies
- **Data protection**: Encryption at rest enabled ✓

---

## Remediation Priority

### Immediate (Before Production)
1. Change HAProxy stats password
2. Generate unique bootstrap token
3. Generate encryption key
4. Disable NGINX snippet annotations
5. Replace all placeholder values

### Short-term (Within 1 week)
1. Implement network policies
2. Restrict bind addresses to private IPs
3. Audit and restrict privileged PSP usage
4. Add resource limits to all workloads
5. Configure image scanning

### Long-term (Within 1 month)
1. Implement comprehensive monitoring
2. Set up secret rotation
3. Regular security audits
4. Pen testing
5. Compliance validation

---

## Security Checklist

Before deploying to production:

- [ ] All CRITICAL vulnerabilities fixed
- [ ] All HIGH vulnerabilities fixed
- [ ] Unique credentials generated
- [ ] Encryption key generated and secured
- [ ] HAProxy credentials changed
- [ ] Bootstrap token regenerated
- [ ] Snippet annotations disabled
- [ ] Network policies implemented
- [ ] Resource limits added
- [ ] Image tags specified (no :latest)
- [ ] RBAC audited
- [ ] Secrets management strategy implemented
- [ ] Monitoring and alerting configured
- [ ] Backup strategy implemented
- [ ] Incident response plan created
- [ ] Security training completed

---

## Tools Used for Audit

- Manual code review
- CIS Kubernetes Benchmark
- OWASP Kubernetes Security Cheat Sheet
- Kubernetes official security documentation
- CVE database review

## Recommended Security Scanning Tools

- **kubeaudit** - Audit Kubernetes configurations
- **kube-bench** - CIS Benchmark compliance
- **Trivy** - Container image scanning
- **Falco** - Runtime security monitoring
- **OPA/Gatekeeper** - Policy enforcement
- **Kyverno** - Kubernetes-native policy management

---

## Contact

For questions about this audit or remediation assistance, please consult your security team or Kubernetes administrator.

**Report Version:** 1.0
**Last Updated:** 2026-02-27
