#!/bin/bash
# GPU Node Setup Script
# Checks Kubernetes connectivity, installs Helm via snap, adds NVIDIA repo, installs GPU operator.

# 1. Confirm kubectl access (ensures we're connected to a cluster)
if ! kubectl get namespace &>/dev/null; then
    echo "❌ Unable to access Kubernetes cluster. Please verify kubeconfig."
    exit 1
fi
echo "✅ Kubernetes cluster connectivity verified."

# 2. Ensure snapd is installed
if ! command -v snap &>/dev/null; then
    echo "⚙️ snap not found — installing..."
    apt update -y
    apt install -y snapd
    systemctl enable --now snapd
else
    echo "✅ snap is already installed."
fi

# 3. Install Helm (using --classic flag)
if ! command -v helm &>/dev/null; then
    echo "⚙️ Installing Helm..."
    snap install helm --classic
else
    echo "✅ Helm is already installed."
fi

# 4. Add NVIDIA Helm repo
echo "➕ Adding NVIDIA Helm repository..."
helm repo add nvidia https://nvidia.github.io/gpu-operator
helm repo update

# 5. Install the NVIDIA GPU Operator
echo "🚀 Installing NVIDIA GPU Operator..."
helm install --wait --timeout 5m --generate-name nvidia/gpu-operator

# 6. Verify GPU resources on node
echo "🔍 Checking node GPU resources..."
kubectl describe nodes | grep -A4 "Capacity" | grep -E "Name|nvidia.com/gpu" || echo "⚠️ No NVIDIA GPU resources detected yet."

echo "✅ GPU setup complete. NVIDIA GPU Operator is now installed."

