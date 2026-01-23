#!/bin/bash
# Complete Kubernetes Cleanup Script
# Removes all k8s components and resets the system to clean state

set -euo pipefail

echo "🧹 Starting Complete Kubernetes Cleanup"
echo "========================================"

# 1. Reset kubeadm (if it was partially initialized)
if command -v kubeadm &>/dev/null; then
    echo "🔄 Resetting kubeadm..."
    kubeadm reset -f || true
fi

# 2. Stop and disable services
echo "🛑 Stopping Kubernetes services..."
systemctl stop kubelet || true
systemctl disable kubelet || true
systemctl stop containerd || true

# 3. Remove CNI networks
echo "🌐 Removing CNI networks..."
rm -rf /etc/cni/net.d/* || true
rm -rf /opt/cni/bin/* || true

# 4. Remove Kubernetes config files
echo "📂 Removing Kubernetes config files..."
rm -rf /etc/kubernetes/*
rm -rf ~/.kube/*
rm -rf /root/.kube/*
rm -rf /var/lib/kubelet/*
rm -rf /var/lib/etcd/*

# 5. Clean up iptables rules
echo "🔥 Flushing iptables..."
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X || true

# 6. Remove containerd config and data
echo "🗑️  Removing containerd data..."
rm -rf /etc/containerd/config.toml
rm -rf /var/lib/containerd/*

# 7. Unhold and remove packages
echo "📦 Removing Kubernetes packages..."
apt-mark unhold kubelet kubeadm kubectl || true
apt remove -y kubelet kubeadm kubectl kubernetes-cni cri-tools || true
apt autoremove -y

# 8. Remove Kubernetes repo
echo "🗂️  Removing Kubernetes repository..."
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 9. Clean up any remaining processes
echo "⚡ Killing remaining processes..."
pkill -f kubelet || true
pkill -f kube-proxy || true
pkill -f kube-apiserver || true
pkill -f etcd || true

# 10. Restart containerd (if you want to keep it for Docker)
# Comment this out if you want to remove containerd completely
echo "🔄 Restarting containerd with fresh config..."
systemctl restart containerd || true
systemctl enable containerd || true

echo ""
echo "✅ Cleanup Complete!"
echo ""
echo "📋 What was cleaned:"
echo "   ✓ kubeadm reset"
echo "   ✓ All k8s services stopped"
echo "   ✓ All k8s config files removed"
echo "   ✓ CNI networks removed"
echo "   ✓ iptables rules flushed"
echo "   ✓ containerd reset"
echo "   ✓ k8s packages removed"
echo ""
echo "🔄 System is ready for fresh k8s installation"
echo ""
