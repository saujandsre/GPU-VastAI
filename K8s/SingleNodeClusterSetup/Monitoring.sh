#!/bin/bash
# 03-monitoring.sh
# Installs kube-prometheus-stack (Prometheus+Grafana) and runs a tmux port-forward for Grafana.

set -e

# 1) Add Helm repo + update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

# 2) Install (or upgrade) kube-prometheus-stack into 'monitoring'
#    This creates Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter, etc.
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# 3) Ensure tmux exists (only if missing; no upgrades)
if ! command -v tmux >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y tmux
fi

# 4) Start a detached tmux session that port-forwards Grafana Service -> remote localhost:80
#    You will SSH from your laptop with: ssh -p <port> -N -L 3000:localhost:80 <user>@<ip>
#    Then open http://localhost:3000
tmux has-session -t gf 2>/dev/null && tmux kill-session -t gf
tmux new -d -s gf "kubectl port-forward -n monitoring svc/prometheus-grafana 80:80"

