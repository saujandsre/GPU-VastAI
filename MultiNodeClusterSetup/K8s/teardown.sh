#!/bin/bash
# Kubernetes Cluster Teardown Script
# Completely removes Kubernetes cluster and cleans up all components

set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (use sudo)" 
   exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔥 Kubernetes Cluster Teardown"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  WARNING: This will completely destroy the cluster!"
echo ""
read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Teardown cancelled"
    exit 0
fi

echo ""
log "Starting cluster teardown..."

# -------------------------
# 1. Drain and delete nodes (if kubectl is available)
# -------------------------
if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
    log "Draining all nodes..."
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
        kubectl drain "$node" --delete-emptydir-data --force --ignore-daemonsets || true
    done
    
    log "Deleting all nodes..."
    for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
        kubectl delete node "$node" || true
    done
fi

# -------------------------
# 2. Reset kubeadm on this node
# -------------------------
log "Running kubeadm reset..."
kubeadm reset -f

# -------------------------
# 3. Remove CNI configurations
# -------------------------
log "Removing CNI configurations..."
rm -rf /etc/cni/net.d/*
rm -rf /opt/cni/bin/*

# -------------------------
# 4. Remove kubectl config
# -------------------------
log "Removing kubectl config..."
rm -rf $HOME/.kube

# If running as sudo, also remove for actual user
if [[ -n "${SUDO_USER:-}" ]]; then
    SUDO_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    rm -rf "$SUDO_HOME/.kube"
fi

# -------------------------
# 5. Clean up iptables rules
# -------------------------
log "Flushing iptables rules..."
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

# -------------------------
# 6. Remove IP routes created by CNI
# -------------------------
log "Cleaning up IP routes..."
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete tunl0 2>/dev/null || true

# -------------------------
# 7. Stop and disable kubelet
# -------------------------
log "Stopping kubelet..."
systemctl stop kubelet || true
systemctl disable kubelet || true

# -------------------------
# 8. Remove kubelet node-ip configuration
# -------------------------
log "Removing kubelet configuration..."
rm -f /etc/default/kubelet
systemctl daemon-reload

# -------------------------
# 9. Clean up container runtime
# -------------------------
log "Cleaning up containers..."
if command -v crictl &>/dev/null; then
    crictl rm $(crictl ps -aq) 2>/dev/null || true
    crictl rmi $(crictl images -q) 2>/dev/null || true
fi

# -------------------------
# 10. Remove Helm releases (optional)
# -------------------------
if command -v helm &>/dev/null; then
    log "Removing Helm releases..."
    helm list --all-namespaces --short | xargs -r -L1 helm uninstall --namespace default || true
fi

# -------------------------
# 11. Remove persistent volumes (optional)
# -------------------------
log "Cleaning up persistent volume data..."
rm -rf /var/lib/kubelet/*
rm -rf /var/lib/etcd/*

# -------------------------
# 12. Restart containerd
# -------------------------
log "Restarting containerd..."
systemctl restart containerd

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Cluster teardown complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 What was cleaned up:"
echo "   ✓ Kubernetes cluster reset"
echo "   ✓ CNI configurations removed"
echo "   ✓ kubectl configs removed"
echo "   ✓ iptables rules flushed"
echo "   ✓ Container images and pods removed"
echo "   ✓ kubelet stopped and disabled"
echo "   ✓ Persistent volumes cleaned"
echo ""
echo "🔄 To rebuild the cluster:"
echo "   1. Run: ./runall.sh"
echo "   2. Or manually: ./preChecks.sh && ./controlNode.sh"
echo ""
echo "💡 Note: Tailscale connection is still active"
echo "   To disconnect: sudo tailscale down"
echo ""
