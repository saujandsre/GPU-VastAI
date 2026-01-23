#!/bin/bash
# Monitoring Stack for Local Control Plane
# Installs Prometheus + Grafana on control plane to monitor remote GPU workers
# Port-forwards Grafana to localhost for easy access

set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $*"; }

ns="monitoring"
release="prometheus"
svc="prometheus-grafana"
session="grafana-pf"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Installing Monitoring Stack on Control Plane"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# -------------------------
# 1) Pre-flight checks
# -------------------------
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl not found. Run localControlPlane.sh first."
    exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
    log "Installing Helm..."
    if command -v snap >/dev/null 2>&1; then
        snap install helm --classic
    else
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
fi

# -------------------------
# 2) Add/Update Helm repos
# -------------------------
log "Adding Prometheus Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

# -------------------------
# 3) Install kube-prometheus-stack
# -------------------------
log "Installing kube-prometheus-stack (this may take 2-3 minutes)..."
helm upgrade --install "$release" prometheus-community/kube-prometheus-stack \
  -n "$ns" --create-namespace \
  --wait --timeout 10m

# -------------------------
# 4) Wait for Grafana to be ready
# -------------------------
log "Waiting for Grafana pods to be Ready..."
kubectl -n "$ns" wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=grafana --timeout=300s

log "Waiting for Grafana Service endpoints..."
until [ "$(kubectl -n "$ns" get endpoints "$svc" -o jsonpath='{.subsets[*].addresses[*].ip}')" != "" ]; do
  sleep 2
done

# -------------------------
# 5) Get Grafana admin password
# -------------------------
GRAFANA_PASSWORD=$(kubectl get secret -n "$ns" "$release-grafana" -o jsonpath="{.data.admin-password}" | base64 --decode)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Monitoring Stack Installed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Grafana Access:"
echo "   URL:      http://localhost:3000"
echo "   Username: admin"
echo "   Password: $GRAFANA_PASSWORD"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Open Grafana: http://localhost:3000"
echo ""
echo "2. After GPU workers join, apply ServiceMonitor:"
echo "   kubectl apply -f serviceMonitorGPU.yml"
echo ""
echo "3. Import GPU dashboard (see Grafana/GPU-Dash.json)"
echo ""
echo "4. Verify metrics are being scraped:"
echo "   kubectl get servicemonitor -n monitoring"
echo ""
echo "💡 Prometheus is scraping cluster-wide metrics"
echo "   GPU metrics will appear once workers with GPU Operator join"
echo ""
