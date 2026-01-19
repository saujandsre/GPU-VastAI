#!/bin/bash
# Worker Node Preparation Script
# Performs: K8s + Tailscale setup, sets hostname, prepares for manual kubeadm join

set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
	   echo "❌ This script must be run as root (use sudo)" 
	      exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Kubernetes Worker Node Preparation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# -------------------------
# 1) Prompt for hostname
# -------------------------
CURRENT_HOSTNAME=$(hostname)
echo "Current hostname: ${CURRENT_HOSTNAME}"
echo ""
read -p "Enter new hostname for this worker (e.g., worker-01): " NEW_HOSTNAME

if [[ -z "${NEW_HOSTNAME}" ]]; then
	    echo "❌ Hostname cannot be empty"
	        exit 1
fi

# Validate hostname format (basic check)
if [[ ! "${NEW_HOSTNAME}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
	    echo "❌ Invalid hostname format. Use lowercase letters, numbers, and hyphens only."
	        exit 1
fi

log "Will set hostname to: ${NEW_HOSTNAME}"

# -------------------------
# 2) Update apt
# -------------------------
log "Updating apt package list"
apt update -y

# -------------------------
# 3) Install basic packages
# -------------------------
log "Installing basic packages"
apt install -y apt-transport-https ca-certificates curl gpg

# -------------------------
# 4) Disable swap
# -------------------------
log "Disabling swap"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# -------------------------
# 5) Install containerd
# -------------------------
log "Installing containerd"
apt install -y containerd

# -------------------------
# 6) Configure containerd with systemd cgroup
# -------------------------
log "Configuring containerd with systemd cgroup"
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# -------------------------
# 7) Restart and enable containerd
# -------------------------
log "Restarting containerd"
systemctl restart containerd
systemctl enable containerd

# -------------------------
# 8) Add Kubernetes repo and key
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
# 9) Install kubelet, kubeadm, kubectl
# -------------------------
log "Installing kubelet, kubeadm, kubectl"
apt install -y kubelet kubeadm kubectl

# -------------------------
# 10) Install Tailscale
# -------------------------
log "Installing Tailscale"
if ! command -v tailscale &>/dev/null; then
	    curl -fsSL https://tailscale.com/install.sh | sh
    else
	        log "Tailscale already installed"
fi

# -------------------------
# 11) Check for Tailscale auth key
# -------------------------
if [[ -z "${TS_AUTHKEY:-}" ]]; then
	    echo ""
	        echo "⚠️  TS_AUTHKEY environment variable not set"
		    echo ""
		        echo "   Get a Tailscale auth key from:"
			    echo "   https://login.tailscale.com/admin/settings/keys"
			        echo ""
				    echo "   Then run:"
				        echo "   export TS_AUTHKEY='tskey-auth-xxxxx'"
					    echo "   sudo -E ./workerNode.sh"
					        echo ""
						    exit 1
fi

# -------------------------
# 12) Set hostname BEFORE connecting to Tailscale
# -------------------------
log "Setting hostname to: ${NEW_HOSTNAME}"
hostnamectl set-hostname "${NEW_HOSTNAME}"

# Update /etc/hosts
if grep -q "127.0.1.1" /etc/hosts; then
	    sed -i "s/127.0.1.1.*/127.0.1.1\t${NEW_HOSTNAME}/" /etc/hosts
    else
	        echo "127.0.1.1	${NEW_HOSTNAME}" >> /etc/hosts
fi

log "Hostname set to: $(hostname)"

# -------------------------
# 13) Connect to Tailscale with new hostname
# -------------------------
log "Connecting to Tailscale network"
tailscale up --auth-key="${TS_AUTHKEY}" --ssh --accept-routes --hostname="${NEW_HOSTNAME}"

# Get Tailscale IP
TS_IP=$(tailscale ip -4 | head -n1)
if [[ -z "${TS_IP}" ]]; then
	    echo "❌ Could not determine Tailscale IPv4 address"
	        echo "   Run: tailscale status"
		    exit 1
fi

log "Tailscale IPv4: ${TS_IP}"

# -------------------------
# 14) Configure kubelet to use Tailscale IP
# -------------------------
log "Configuring kubelet to use Tailscale IP: ${TS_IP}"
echo "KUBELET_EXTRA_ARGS=--node-ip=${TS_IP}" > /etc/default/kubelet
systemctl daemon-reload

# Don't start kubelet yet - it will start after kubeadm join
log "Kubelet configured (will use ${TS_IP} as node IP)"

# -------------------------
# 15) Final instructions
# -------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Worker Node Preparation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Node Information:"
echo "   Hostname:      ${NEW_HOSTNAME}"
echo "   Tailscale IP:  ${TS_IP}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Next Step: Run the kubeadm join command"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Get the join command from your control plane:"
echo ""
echo "   ssh <control-plane>"
echo "   kubeadm token create --print-join-command"
echo ""
echo "Then run it on this worker node:"
echo ""
echo "   sudo kubeadm join <TAILSCALE_IP>:6443 --token <TOKEN> \\"
echo "     --discovery-token-ca-cert-hash sha256:<HASH>"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 After joining, verify on control plane:"
echo "   kubectl get nodes"
echo "   kubectl get nodes -o wide  # Should show Tailscale IPs"
echo ""
