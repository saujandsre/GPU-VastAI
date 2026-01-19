#!/bin/bash
# Control Plane setup script for multi-node cluster
# Uses Tailscale IP for API server, prompts for hostname, untaints control plane to allow GPU pods

set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (use sudo)" 
   exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎛️  Kubernetes Control Plane Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# -------------------------
# 1. Prompt for hostname
# -------------------------
CURRENT_HOSTNAME=$(hostname)
echo "Current hostname: ${CURRENT_HOSTNAME}"
echo ""
read -p "Enter hostname for control plane all small words.[controlnode]: " NEW_HOSTNAME
NEW_HOSTNAME=${NEW_HOSTNAME:-controlNode}

# Validate hostname format (basic check)
if [[ ! "${NEW_HOSTNAME}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
    echo "❌ Invalid hostname format. Use lowercase letters, numbers, and hyphens only."
    exit 1
fi

if [[ "${NEW_HOSTNAME}" != "${CURRENT_HOSTNAME}" ]]; then
    log "Setting hostname to: ${NEW_HOSTNAME}"
    hostnamectl set-hostname "${NEW_HOSTNAME}"
    
    # Update /etc/hosts
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t${NEW_HOSTNAME}/" /etc/hosts
    else
        echo "127.0.1.1	${NEW_HOSTNAME}" >> /etc/hosts
    fi
    
    log "Hostname changed to: $(hostname)"
else
    log "Keeping current hostname: ${CURRENT_HOSTNAME}"
fi

# -------------------------
# 2. Check that required binaries are installed
# -------------------------
for bin in kubeadm kubelet kubectl tailscale; do
    if ! command -v $bin &>/dev/null; then
        echo "❌ $bin not found. Please run preChecks.sh first."
        exit 1
    fi
done

log "✅ kubeadm, kubelet, kubectl, and tailscale are installed"

# -------------------------
# 3. Verify Tailscale is connected and get IP
# -------------------------
TS_IP=$(tailscale ip -4 | head -n1)
if [[ -z "${TS_IP}" ]]; then
    echo "❌ Tailscale not connected or no IPv4 address found"
    echo "   Run: tailscale status"
    echo "   Or: sudo tailscale up --auth-key=\$TS_AUTHKEY"
    exit 1
fi

log "✅ Tailscale connected: ${TS_IP}"

# -------------------------
# 4. Check if kubelet service is active
# -------------------------
if systemctl is-active --quiet kubelet; then
    log "✅ kubelet service is running"
else
    log "⚠️  kubelet is not running. Starting it now..."
    systemctl start kubelet
fi

# -------------------------
# 5. Initialize the control plane on Tailscale IP
# -------------------------
log "🚀 Initializing Kubernetes Control Plane on ${TS_IP}"
log "   API server will be reachable at: ${TS_IP}:6443"

sudo kubeadm init \
  --apiserver-advertise-address="${TS_IP}" \
  --apiserver-cert-extra-sans="${TS_IP}" \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name="${NEW_HOSTNAME}"

# -------------------------
# 6. Configure kubectl for the current user
# -------------------------
log "⚙️  Configuring kubectl for user: $USER"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# -------------------------
# 7. Deploy Calico CNI
# -------------------------
log "🌐 Installing Calico CNI..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Wait for Calico to be ready
log "⏳ Waiting for Calico pods to be ready..."
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=300s || true

# -------------------------
# 8. Untaint control plane to allow GPU workloads
# -------------------------
log "🔓 Removing control-plane taint to allow pod scheduling"
kubectl taint nodes "${NEW_HOSTNAME}" node-role.kubernetes.io/control-plane- || true

# -------------------------
# 9. Print join command for worker nodes
# -------------------------
echo ""
echo "✅ Control Plane setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 To join worker nodes, run this command on each worker:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
kubeadm token create --print-join-command
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Verify cluster status:"
echo "   kubectl get nodes"
echo "   kubectl get pods -A"
echo ""
echo "🎯 Control plane is schedulable (GPU pods can run here)"
echo "🌐 API server accessible at: ${TS_IP}:6443"
