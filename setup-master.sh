#!/bin/bash
# Script to initialize the first Kubernetes master node
# Run this on the FIRST master node only

set -e

echo "=== Kubernetes Master Node Setup ==="

# Update system
echo "Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Install container runtime (containerd)
echo "Installing containerd..."
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Install kubeadm, kubelet, kubectl
echo "Installing Kubernetes components..."
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Configure kernel modules
echo "Configuring kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Disable swap
echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Generate encryption key
echo "Generating encryption key..."
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
sudo mkdir -p /etc/kubernetes
sudo sed "s/<BASE64_ENCODED_SECRET>/${ENCRYPTION_KEY}/" encryption-config.yaml | sudo tee /etc/kubernetes/encryption-config.yaml

# Initialize the cluster (first master only)
echo "Initializing Kubernetes cluster..."
echo "Make sure kubeadm-config.yaml is configured with the correct control plane endpoint!"
sudo kubeadm init --config kubeadm-config.yaml --upload-certs

# Setup kubectl for root
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo ""
echo "=== Master Node Initialized Successfully ==="
echo ""
echo "IMPORTANT: Save the join commands that were printed above!"
echo ""
echo "Next steps:"
echo "1. Install CNI (Calico): kubectl apply -f calico-network.yaml"
echo "2. Install AWS Cloud Controller Manager: kubectl apply -f aws-cloud-controller-manager.yaml"
echo "3. Install EBS CSI Driver: kubectl apply -f aws-ebs-csi-driver.yaml"
echo "4. Install Metrics Server: kubectl apply -f metrics-server.yaml"
echo "5. Install Ingress Controller: kubectl apply -f ingress-nginx.yaml"
echo "6. Join the second master using the control-plane join command"
echo "7. Join worker nodes using the worker join command"
echo ""
