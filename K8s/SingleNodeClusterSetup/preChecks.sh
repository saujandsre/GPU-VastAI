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
# Add Kubernetes latest stable repo (auto-updates when new versions release)

# Remove old list if present
sudo rm -f /etc/apt/sources.list.d/kubernetes.list

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list



apt update -y
apt install -y kubelet kubeadm kubectl


echo "✅ Kubernetes prerequisites installed successfully."

