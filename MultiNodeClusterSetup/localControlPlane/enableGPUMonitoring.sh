#!/bin/bash
# Enable GPU Monitoring (run AFTER workers with GPU join)
# Applies ServiceMonitor to tell Prometheus to scrape GPU metrics

set -euo pipefail

log() { echo "[$(date +'%H:%M:%S')] $*"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Enabling GPU Metrics Collection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if ServiceMonitor CRD exists (installed by kube-prometheus-stack)
if ! kubectl get crd servicemonitors.monitoring.coreos.com &>/dev/null; then
    echo "❌ ServiceMonitor CRD not found"
    echo "   Run monitoring_local.sh first to install Prometheus stack"
    exit 1
fi

# Check if serviceMonitorGPU.yml exists
if [[ ! -f "serviceMonitorGPU.yml" ]]; then
    echo "⚠️  serviceMonitorGPU.yml not found in current directory"
    echo "   Creating it now..."
    
    cat > serviceMonitorGPU.yml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dcgm-exporter
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - default        # namespace where the DCGM exporter Service lives
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter  # must match labels on the Service
  endpoints:
    - port: gpu-metrics
      path: /metrics
      interval: 15s
      scheme: http
EOF
    
    log "✅ Created serviceMonitorGPU.yml"
fi

# Apply the ServiceMonitor
log "Applying ServiceMonitor for GPU metrics..."
kubectl apply -f serviceMonitorGPU.yml

# Wait a moment for it to be created
sleep 2

# Verify
if kubectl get servicemonitor dcgm-exporter -n monitoring &>/dev/null; then
    log "✅ ServiceMonitor created successfully"
else
    echo "❌ ServiceMonitor creation failed"
    exit 1
fi

# Check if any GPU nodes exist
GPU_NODES=$(kubectl get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ GPU Monitoring Enabled!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 GPU nodes detected: $GPU_NODES"
echo ""

if [[ $GPU_NODES -eq 0 ]]; then
    echo "⚠️  No GPU nodes found yet"
    echo ""
    echo "   Waiting for workers to join and GPU Operator to install..."
    echo "   GPU metrics will appear automatically once:"
    echo "   1. Worker joins cluster"
    echo "   2. GPU Operator creates DCGM exporter pods"
    echo "   3. DCGM exporter Service is created"
else
    echo "✅ GPU nodes found!"
    echo ""
    echo "   Verify DCGM exporter is running:"
    echo "   kubectl get pods -l app=nvidia-dcgm-exporter"
    echo ""
    echo "   Check if metrics are being scraped:"
    echo "   kubectl get servicemonitor -n monitoring"
    echo ""
    echo "   View GPU metrics in Grafana:"
    echo "   http://localhost:3000"
    echo "   Import dashboard from: Grafana/GPU-Dash.json"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
