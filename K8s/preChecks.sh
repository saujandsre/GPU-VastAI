#!/bin/bash
# Basic Kubernetes node prep script (for all nodes)
# Performs: apt update, install essentials, disable swap, install containerd, enable systemd cgroup,
# add Kubernetes repo, install kubelet/kubeadm/kubectl, hold them.

# 1. Update apt (no upgrade)
apt update -y

# 2. Install basic packages
apt install -y apt-transport-https ca-certificates curl gpg

# 3. Disable swap immediately and permanently
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# 4. Install containerd
apt install -y containerd

# 5. Generate default config and enable systemd cgroup
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 6. Restart and enable containerd
systemctl restart containerd
systemctl enable containerd

# 7. Add Kubernetes repo and key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# 8. Update and install kubelet, kubeadm, kubectl
apt update -y
apt install -y kubelet kubeadm kubectl

# 9. Hold versions
apt-mark hold kubelet kubeadm kubectl

echo "✅ Kubernetes prerequisites installed successfully."

