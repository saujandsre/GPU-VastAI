#!/bin/bash
# Vast.ai Worker Preparation Script
# Prepares a Vast.ai GPU instance to join your local control plane via Tailscale
# This does EVERYTHING: swap, containerd, kernel modules, k8s binaries, etc.

set -euo pipefail

echo "🔧 Preparing Vast.ai GPU Worker Node"
echo "====================================="

# 1. Update apt (no full upgrade to save time)
echo "📦 Updating package lists..."
apt update -y

# 2. Install basic packages
echo "📦 Installing prerequisites..."
apt install -y apt-transport-https ca-certificates curl gpg

# 3. Disable swap (CRITICAL for k8s)
echo "🔄 Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
echo "✅ Swap disabled"

# 4. Install Tailscale
if ! command -v tailscale &>/dev/null; then
    echo "📦 Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "✅ Tailscale installed"
    echo ""
    echo "⚠️  IMPORTANT: Run 'sudo tailscale up' NOW to connect to your network"
    echo "   Then press ENTER to continue..."
    read -r
else
    echo "✅ Tailscale already installed"
fi

# Verify Tailscale is connected
if ! tailscale status &>/dev/null; then
    echo "❌ Tailscale is not connected!"
    echo "   Run: sudo tailscale up"
    echo "   Then re-run this script."
    exit 1
fi

WORKER_TAILSCALE_IP=$(tailscale ip -4)
echo "✅ Worker Tailscale IP: $WORKER_TAILSCALE_IP"

# 5. Install and configure containerd properly
echo "📦 Setting up containerd..."
apt install -y containerd

# Stop containerd before reconfiguring
systemctl stop containerd

# Generate CLEAN default config
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup (CRITICAL for k8s)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Enable CRI plugin explicitly (prevents "unknown service" error)
sed -i 's/disabled_plugins = \["cri"\]/disabled_plugins = []/' /etc/containerd/config.toml

# Start and enable containerd
systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd

echo "✅ containerd configured"

# 6. Load kernel modules required by k8s
echo "🔧 Loading required kernel modules..."
modprobe overlay
modprobe br_netfilter

# Make them load on boot
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Set up required sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system >/dev/null
echo "✅ Kernel modules and sysctl configured"

# 7. Add Kubernetes repo
echo "📦 Adding Kubernetes repository..."
rm -f /etc/apt/sources.list.d/kubernetes.list
mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

# 8. Install kubelet, kubeadm, kubectl
apt update -y
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "✅ Kubernetes binaries installed"

# 9. Check if already part of a cluster
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
    echo "⚠️  This node is already part of a cluster"
    echo "   To reset: sudo kubeadm reset"
    exit 1
fi

# 10. Pre-pull kubeadm images (speeds up join)
echo "📥 Pre-pulling Kubernetes images (saves time during join)..."
kubeadm config images pull

echo ""
echo "=========================================="
echo "✅ Worker Node Preparation Complete!"
echo "=========================================="
echo ""
echo "📋 Worker Info:"
echo "   Tailscale IP: $WORKER_TAILSCALE_IP"
echo ""
echo "✅ What was configured:"
echo "   ✓ Swap disabled"
echo "   ✓ Tailscale connected"
echo "   ✓ containerd with CRI plugin enabled"
echo "   ✓ Kernel modules loaded (overlay, br_netfilter)"
echo "   ✓ sysctl networking params set"
echo "   ✓ kubelet, kubeadm, kubectl installed"
echo "   ✓ Kubernetes images pre-pulled"
echo ""
echo "📝 Next steps:"
echo "   1. Get the join command from your local machine:"
echo "      cat ~/k8s-worker-join.sh"
echo ""
echo "   2. Run the kubeadm join command here:"
echo "      sudo kubeadm join <CONTROL_PLANE_TAILSCALE_IP>:6443 --token <token> \\"
echo "        --discovery-token-ca-cert-hash sha256:<hash>"
echo ""
echo "   3. Verify on control plane:"
echo "      kubectl get nodes"
echo ""
echo "   4. After joining, install GPU Operator:"
echo "      bash GPUNodes.sh"
echo ""
