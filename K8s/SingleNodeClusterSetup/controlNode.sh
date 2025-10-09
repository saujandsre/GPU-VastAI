#!/bin/bash
# Control Plane setup script
# Checks kube binaries, runs kubeadm init, sets up kubectl config, and installs Calico CNI.

# 1. Check that required binaries are installed
for bin in kubeadm kubelet kubectl; do
    if ! command -v $bin &>/dev/null; then
        echo "❌ $bin not found. Please run precheck.sh first."
        exit 1
    fi
done

echo "✅ kubeadm, kubelet, and kubectl are installed."

# 2. Check if kubelet service is active
if systemctl is-active --quiet kubelet; then
    echo "✅ kubelet service is running."
else
    echo "⚠️ kubelet is not running. Starting it now..."
    systemctl start kubelet
fi

# 3. Initialize the control plane
echo "🚀 Initializing Kubernetes Control Plane..."
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# 4. Configure kubectl for the current user
echo "⚙️ Configuring kubectl for user: $USER"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 5. Deploy Calico CNI (run only on control plane)
echo "🌐 Installing Calico CNI..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

echo "✅ Control Plane setup complete!"
echo "👉 Use the kubeadm join command below (shown at the end of kubeadm init) on worker nodes."

