#!/bin/bash
# Local Control Plane Setup with Tailscale
# Sets up a Kubernetes control plane on your local machine using Tailscale IP
# for secure connectivity to remote GPU worker nodes

set -euo pipefail

echo "🚀 Starting Local Kubernetes Control Plane Setup"
echo "=================================================="

# 1. Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root or with sudo"
   exit 1
fi

# 2. Install Tailscale if not present
if ! command -v tailscale &>/dev/null; then
    echo "📦 Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "✅ Tailscale installed"
else
    echo "✅ Tailscale already installed"
fi

# 3. Check if Tailscale is running and get IP
if ! tailscale status &>/dev/null; then
    echo "⚠️  Tailscale is not running. Please run: sudo tailscale up"
    echo "   Then re-run this script."
    exit 1
fi

TAILSCALE_IP=$(tailscale ip -4)
if [[ -z "$TAILSCALE_IP" ]]; then
    echo "❌ Could not get Tailscale IPv4 address"
    echo "   Make sure Tailscale is connected: sudo tailscale up"
    exit 1
fi

# Get local IP for dual-stack option
LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)

echo "✅ Tailscale IP: $TAILSCALE_IP"
echo "✅ Local IP: $LOCAL_IP"

# 4. Install prerequisites (containerd, kubeadm, kubectl, kubelet)
echo "📦 Installing Kubernetes prerequisites..."

# Update apt
apt update -y

# Install basic packages
apt install -y apt-transport-https ca-certificates curl gpg

# Disable swap
echo "🔄 Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Install containerd if not present, or fix if broken
echo "📦 Setting up containerd..."
apt install -y containerd

# Stop containerd before reconfiguring
systemctl stop containerd

# Generate CLEAN default config
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup (CRITICAL for k8s)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Enable CRI plugin explicitly (fix for your error)
sed -i 's/disabled_plugins = \["cri"\]/disabled_plugins = []/' /etc/containerd/config.toml

# Start and enable containerd
systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd

# Verify containerd is working
echo "🔍 Verifying containerd..."
sleep 2
if ! crictl info &>/dev/null; then
    echo "⚠️  containerd verification failed, but continuing..."
fi
echo "✅ containerd configured"

# Add Kubernetes repo
echo "📦 Adding Kubernetes repository..."
rm -f /etc/apt/sources.list.d/kubernetes.list
mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm, kubectl
apt update -y
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "✅ Kubernetes binaries installed"

# 5. Check if cluster already exists
if [[ -f /etc/kubernetes/admin.conf ]]; then
    echo "⚠️  Kubernetes cluster already exists on this machine"
    echo "   If you want to reset, run: sudo kubeadm reset"
    echo "   Then re-run this script."
    exit 1
fi

# 6. Load kernel modules required by k8s
echo "🔧 Loading required kernel modules..."
modprobe overlay
modprobe br_netfilter

# Set up required sysctl params
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system >/dev/null

# 7. Initialize control plane with Tailscale IP
echo "🎯 Initializing Kubernetes Control Plane..."
echo "   API Server will listen on: $TAILSCALE_IP:6443"
echo "   (Also accessible via local IP: $LOCAL_IP:6443)"

# Use both IPs for cert SANs so you can access via either
kubeadm init \
  --apiserver-advertise-address="$TAILSCALE_IP" \
  --apiserver-cert-extra-sans="$TAILSCALE_IP,$LOCAL_IP" \
  --pod-network-cidr=192.168.0.0/16 \
  --control-plane-endpoint="$TAILSCALE_IP:6443" \
  --v=5

# 8. Configure kubectl for current user
ACTUAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo ~"$ACTUAL_USER")

echo "⚙️  Configuring kubectl for user: $ACTUAL_USER"
mkdir -p "$USER_HOME/.kube"
cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$USER_HOME/.kube"

# Also copy for root (useful when using sudo kubectl)
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

echo "✅ kubectl configured"

# 9. Install Calico CNI
echo "🌐 Installing Calico CNI..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Wait for Calico to start
echo "⏳ Waiting for Calico pods to start (this may take 2-3 minutes)..."
kubectl wait --for=condition=Ready pod \
  -l k8s-app=calico-node \
  -n kube-system \
  --timeout=300s || echo "⚠️  Calico taking longer than expected, check 'kubectl get pods -n kube-system'"

# 10. Remove taint from control plane (allow pods to run here for testing)
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl taint nodes "$NODE_NAME" node-role.kubernetes.io/control-plane- || true

echo "✅ Control plane taint removed (local testing enabled)"

# 11. Generate worker join command
echo ""
echo "=========================================="
echo "🎉 Control Plane Setup Complete!"
echo "=========================================="
echo ""
echo "📋 Cluster Info:"
echo "   Control Plane Tailscale IP: $TAILSCALE_IP"
echo "   Control Plane Local IP: $LOCAL_IP"
echo "   API Server (Tailscale): https://$TAILSCALE_IP:6443"
echo "   API Server (Local): https://$LOCAL_IP:6443"
echo ""

# Save join command to file
JOIN_CMD_FILE="$USER_HOME/k8s-worker-join.sh"
kubeadm token create --print-join-command > "$JOIN_CMD_FILE"
chown "$ACTUAL_USER":"$ACTUAL_USER" "$JOIN_CMD_FILE"
chmod +x "$JOIN_CMD_FILE"

echo "💾 Worker join command saved to: $JOIN_CMD_FILE"
echo ""
echo "📤 To join a worker node (like Vast.ai GPU instance):"
echo "   1. Copy this file to the worker: scp $JOIN_CMD_FILE root@worker-ip:/root/"
echo "   2. On the worker, run: bash /root/k8s-worker-join.sh"
echo ""
echo "Or manually run this command on the worker:"
echo "----------------------------------------"
cat "$JOIN_CMD_FILE"
echo "----------------------------------------"
echo ""

# 12. Verify cluster status
echo "🔍 Verifying cluster status..."
kubectl get nodes
echo ""
kubectl get pods -A
echo ""

echo "✅ Control plane is ready!"
echo ""
echo "📝 Next steps:"
echo "   1. Install monitoring: bash monitoring.sh"
echo "   2. Join GPU workers from Vast.ai using the join command above"
echo "   3. Test connectivity: kubectl get nodes"
echo ""
echo "🔧 Useful commands:"
echo "   kubectl get nodes                    # Check cluster nodes"
echo "   kubectl get pods -A                  # Check all pods"
echo "   kubectl cluster-info                 # Cluster endpoints"
echo "   sudo journalctl -u kubelet -f        # Kubelet logs"
echo "   sudo crictl ps                       # List containers"
echo ""
echo "💡 Access options:"
echo "   - From Vast.ai workers: Use Tailscale IP ($TAILSCALE_IP)"
echo "   - From local network: Use local IP ($LOCAL_IP)"
echo "   - Both IPs work thanks to --apiserver-cert-extra-sans"
echo ""
