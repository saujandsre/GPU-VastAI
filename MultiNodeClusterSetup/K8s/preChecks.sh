#!/bin/bash
# Basic Kubernetes node prep script (for all nodes)
# Performs: apt update, install essentials, disable swap, install containerd, enable systemd cgroup,
# add Kubernetes repo, install kubelet/kubeadm/kubectl, install Tailscale, configure kubelet node-ip

set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
	   echo "❌ This script must be run as root (use sudo)" 
	      exit 1
fi

# -------------------------
# 1) Update apt (no upgrade)
# -------------------------
log "Updating apt package list"
apt update -y

# -------------------------
# 2) Install basic packages
# -------------------------
log "Installing basic packages"
apt install -y apt-transport-https ca-certificates curl gpg

# -------------------------
# 3) Disable swap immediately and permanently
# -------------------------
log "Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# -------------------------
# 4) Install containerd
# -------------------------
log "Installing containerd"
apt install -y containerd

# -------------------------
# 5) Generate default config and enable systemd cgroup
# -------------------------
log "Configuring containerd with systemd cgroup"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# -------------------------
# 6) Restart and enable containerd
# -------------------------
log "Restarting containerd"
systemctl restart containerd
systemctl enable containerd

# -------------------------
# 7) Add Kubernetes repo and key
# -------------------------
log "Adding Kubernetes repository"
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
	  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
	  | sudo tee /etc/apt/sources.list.d/kubernetes.list

apt update -y

# -------------------------
# 8) Install kubelet, kubeadm, kubectl
# -------------------------
log "Installing kubelet, kubeadm, kubectl"
apt install -y kubelet kubeadm kubectl

# -------------------------
# 9) Tailscale installation
# -------------------------
log "Installing Tailscale"
if ! command -v tailscale &>/dev/null; then
	    curl -fsSL https://tailscale.com/install.sh | sh
    else
	        log "Tailscale already installed"
fi

# -------------------------
# 10) Tailscale auth (requires TS_AUTHKEY environment variable)
# -------------------------
if [[ -z "${TS_AUTHKEY:-}" ]]; then
	    echo ""
	        echo "⚠️  TS_AUTHKEY environment variable not set"
		    echo "   To connect this node to Tailscale, run:"
		        echo "   export TS_AUTHKEY='tskey-auth-xxxxx'"
			    echo "   Then re-run this script OR manually run:"
			        echo "   sudo tailscale up --auth-key=\$TS_AUTHKEY --ssh"
				    echo ""
				        echo "✅ Kubernetes prerequisites installed (Tailscale pending auth)"
					    exit 0
fi

log "Connecting to Tailscale network"
tailscale up --auth-key="${TS_AUTHKEY}" --ssh --accept-routes

# Optional: Set hostname in Tailscale (uses current hostname)
CURRENT_HOSTNAME=$(hostname)
tailscale set --hostname="${CURRENT_HOSTNAME}" >/dev/null 2>&1 || true

# Get Tailscale IP
TS_IP=$(tailscale ip -4 | head -n1)
if [[ -z "${TS_IP}" ]]; then
	    echo "❌ Could not determine Tailscale IPv4 address"
	        echo "   Run: tailscale status"
		    exit 1
fi

log "Tailscale IPv4: ${TS_IP}"

# -------------------------
# 11) Force kubelet to use Tailscale IP as node-ip (CRITICAL)
# -------------------------
log "Configuring kubelet to use Tailscale IP: ${TS_IP}"
echo "KUBELET_EXTRA_ARGS=--node-ip=${TS_IP}" > /etc/default/kubelet
systemctl daemon-reload

# Don't restart kubelet yet if cluster not initialized
# It will start properly after kubeadm init/join
log "Kubelet configured (will use ${TS_IP} as node IP)"

echo ""
echo "✅ Kubernetes prerequisites installed successfully"
echo "✅ Tailscale connected: ${TS_IP}"
echo "✅ Kubelet configured to use Tailscale IP"
echo ""
echo "Next steps:"
echo "  - Control plane: run ./controlNode.sh"
echo "  - Worker node: run kubeadm join command from control plane"
