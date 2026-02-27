# Production-Ready Kubernetes Cluster on AWS

This repository contains Kubernetes configuration files for deploying a production-ready HA cluster on AWS with 2 master nodes and 5 worker nodes.

## Architecture

- **Control Plane**: 2 master nodes for high availability
- **Worker Nodes**: 5 worker nodes for application workloads
- **Load Balancer**: HAProxy for control plane HA (or AWS NLB)
- **CNI**: Calico for pod networking
- **Storage**: AWS EBS CSI Driver for persistent volumes
- **Ingress**: NGINX Ingress Controller with AWS NLB
- **Monitoring**: Metrics Server for pod autoscaling

## Prerequisites

### AWS Resources Required

1. **EC2 Instances**:
   - 2x Master nodes (t3.medium or larger, 2 vCPU, 4GB RAM minimum)
   - 5x Worker nodes (t3.large or larger, 2 vCPU, 8GB RAM minimum)
   - 1x HAProxy load balancer (t3.small)

2. **Networking**:
   - VPC with public and private subnets
   - Security groups configured for:
     - Master nodes: 6443 (API), 2379-2380 (etcd), 10250-10252 (kubelet/controller)
     - Worker nodes: 10250 (kubelet), 30000-32767 (NodePort)
     - HAProxy: 6443 (API), 80 (HTTP), 443 (HTTPS), 8404 (stats)

3. **IAM Roles**:
   - Master nodes need permissions for AWS Cloud Controller Manager
   - Worker nodes need permissions for EBS CSI Driver
   - See AWS documentation for required policies

4. **DNS** (recommended):
   - Create a DNS record pointing to HAProxy or AWS NLB for the control plane endpoint

## Installation Steps

### 1. Prepare Infrastructure

1. Launch EC2 instances (Ubuntu 22.04 LTS recommended)
2. Configure security groups
3. Attach IAM roles to instances
4. Note down private IP addresses of all instances

### 2. Setup HAProxy Load Balancer

On the HAProxy instance:

```bash
# Install HAProxy
sudo apt-get update
sudo apt-get install -y haproxy

# Copy and configure haproxy-loadbalancer.cfg
# Replace <MASTER1_PRIVATE_IP>, <MASTER2_PRIVATE_IP>, etc.
sudo cp haproxy-loadbalancer.cfg /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# Verify HAProxy is running
sudo systemctl status haproxy
```

### 3. Configure kubeadm-config.yaml

Edit `kubeadm-config.yaml` and update:

- `controlPlaneEndpoint`: Set to HAProxy DNS name or IP (e.g., "k8s-lb.example.com:6443")
- `certSANs`: Add HAProxy DNS name and IP addresses
- `networking.podSubnet`: Keep as 10.244.0.0/16 (for Calico)

### 4. Initialize First Master Node

On the **first master node**:

```bash
# Copy configuration files
scp kubeadm-config.yaml encryption-config.yaml setup-master.sh master1:~/

# SSH to master1
ssh master1

# Make script executable and run
chmod +x setup-master.sh
./setup-master.sh

# After initialization, install CNI and addons
kubectl apply -f calico-network.yaml
kubectl apply -f aws-cloud-controller-manager.yaml
kubectl apply -f aws-ebs-csi-driver.yaml
kubectl apply -f metrics-server.yaml
kubectl apply -f ingress-nginx.yaml
kubectl apply -f pod-security-policy.yaml
```

**IMPORTANT**: Save the `kubeadm join` commands printed at the end. You'll need:
- One command for joining the second master (control-plane)
- One command for joining worker nodes

### 5. Join Second Master Node

On the **second master node**:

```bash
# Copy setup script
scp setup-master.sh master2:~/

# SSH to master2
ssh master2

# Prepare the node (without initializing)
chmod +x setup-master.sh
# Comment out the kubeadm init line in the script or just run the preparation steps

# Install dependencies
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y containerd
# ... (follow the same steps as setup-master.sh until kubeadm init)

# Run the control-plane join command from master1 initialization
# It will look like:
sudo kubeadm join k8s-lb.example.com:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash> \
    --control-plane --certificate-key <cert-key>

# Setup kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 6. Join Worker Nodes

On **each worker node** (worker1 through worker5):

```bash
# Copy setup script
scp setup-worker.sh worker1:~/

# SSH to worker
ssh worker1

# Run setup script
chmod +x setup-worker.sh
./setup-worker.sh

# Run the worker join command from master1 initialization
# It will look like:
sudo kubeadm join k8s-lb.example.com:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

Repeat for all 5 worker nodes.

### 7. Verify Cluster

From a master node:

```bash
# Check all nodes are Ready
kubectl get nodes

# Should show:
# NAME      STATUS   ROLES           AGE   VERSION
# master1   Ready    control-plane   10m   v1.29.0
# master2   Ready    control-plane   5m    v1.29.0
# worker1   Ready    <none>          3m    v1.29.0
# worker2   Ready    <none>          3m    v1.29.0
# worker3   Ready    <none>          3m    v1.29.0
# worker4   Ready    <none>          3m    v1.29.0
# worker5   Ready    <none>          3m    v1.29.0

# Check system pods
kubectl get pods -n kube-system

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

## Configuration Files

- `kubeadm-config.yaml`: Main cluster configuration
- `encryption-config.yaml`: Encryption at rest for secrets
- `aws-cloud-controller-manager.yaml`: AWS integration for LoadBalancer services
- `aws-ebs-csi-driver.yaml`: Persistent storage with AWS EBS
- `calico-network.yaml`: CNI plugin for pod networking
- `metrics-server.yaml`: Resource metrics for HPA
- `ingress-nginx.yaml`: Ingress controller with AWS NLB
- `pod-security-policy.yaml`: Security policies for pods
- `haproxy-loadbalancer.cfg`: HAProxy configuration for HA
- `setup-master.sh`: Master node initialization script
- `setup-worker.sh`: Worker node preparation script

## Post-Installation

### Configure kubectl Access

From your local machine:

```bash
# Copy admin.conf from master
scp master1:/etc/kubernetes/admin.conf ~/.kube/config

# Verify access
kubectl get nodes
kubectl cluster-info
```

### Deploy Sample Application

```bash
kubectl create deployment nginx --image=nginx --replicas=3
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx
```

### Enable Horizontal Pod Autoscaling

```bash
kubectl autoscale deployment nginx --cpu-percent=50 --min=3 --max=10
kubectl get hpa
```

## Security Considerations

1. **Encryption at Rest**: Secrets are encrypted in etcd using the encryption-config.yaml
2. **Pod Security Policies**: Restricted PSP applied by default
3. **RBAC**: Enabled by default, configure roles/rolebindings as needed
4. **Network Policies**: Use Calico network policies to restrict pod-to-pod traffic
5. **API Server Audit**: Enabled with logs at /var/log/kubernetes/audit.log
6. **TLS**: All cluster communication is encrypted

## Maintenance

### Upgrade Cluster

```bash
# On master nodes (one at a time)
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.29.x-00
sudo apt-mark hold kubeadm
sudo kubeadm upgrade apply v1.29.x
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.29.x-00 kubectl=1.29.x-00
sudo apt-mark hold kubelet kubectl
sudo systemctl restart kubelet

# On worker nodes (one at a time)
kubectl drain worker1 --ignore-daemonsets
# SSH to worker1
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update && sudo apt-get install -y kubeadm=1.29.x-00 kubelet=1.29.x-00 kubectl=1.29.x-00
sudo apt-mark hold kubeadm kubelet kubectl
sudo systemctl restart kubelet
# Back on master
kubectl uncordon worker1
```

### Backup etcd

```bash
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

## Troubleshooting

### Nodes Not Ready

```bash
# Check node status
kubectl describe node <node-name>

# Check kubelet logs
sudo journalctl -u kubelet -f

# Check containerd
sudo systemctl status containerd
```

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Check events
kubectl get events --sort-by='.lastTimestamp'
```

### Network Issues

```bash
# Check Calico pods
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check CNI configuration
ls -la /etc/cni/net.d/
cat /etc/cni/net.d/10-calico.conflist
```

## Support

For issues and questions:
- Kubernetes documentation: https://kubernetes.io/docs/
- Calico documentation: https://docs.projectcalico.org/
- AWS documentation: https://docs.aws.amazon.com/eks/

## License

These configuration files are provided as-is for educational and production use.
