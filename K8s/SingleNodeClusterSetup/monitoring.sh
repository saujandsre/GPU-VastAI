#!/bin/bash
# Monitoring.sh — install kube-prometheus-stack and keep a tmux port-forward running
set -euo pipefail

ns="monitoring"
release="prometheus" # helm release name
svc="prometheus-grafana"
session="gf"

# 0) Pre-flight checks
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm not found"; exit 1; }

# 1) Add/Update repo and install/upgrade the stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

# Install or upgrade into 'monitoring' ns
helm upgrade --install "$release" prometheus-community/kube-prometheus-stack \
  -n "$ns" --create-namespace

# 2) Ensure tmux exists
if ! command -v tmux >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y tmux
fi

# 3) Wait for Grafana to be actually reachable
echo "⏳ Waiting for Grafana pods to be Ready..."
kubectl -n "$ns" wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=grafana --timeout=300s

echo "⏳ Waiting for Service '$svc' to exist..."
# wait until the service shows up
until kubectl -n "$ns" get svc "$svc" >/dev/null 2>&1; do sleep 2; done

echo "⏳ Waiting for Grafana Endpoints..."
# wait until endpoints list at least one address
until [ "$(kubectl -n "$ns" get endpoints "$svc" -o jsonpath='{.subsets[*].addresses[*].ip}')" != "" ]; do
  sleep 2
done

# 4) Start/Restart tmux port-forward (remote localhost:80 -> svc:80)
#    SSH from laptop: ssh -p <PORT> -N -L 3000:localhost:80 <user>@<ip>  -> http://localhost:3000
pf_cmd="kubectl -n $ns port-forward svc/$svc 80:80"

# kill prior session if present
if tmux has-session -t "$session" 2>/dev/null; then
  tmux kill-session -t "$session"
fi

# start fresh, detached
tmux new -d -s "$session" "$pf_cmd"

# brief verification
sleep 1
if ! tmux has-session -t "$session" 2>/dev/null; then
  echo "❌ Failed to start tmux session '$session' for port-forward."
  echo "Command was: $pf_cmd"
  exit 1
fi

echo "✅ Monitoring stack ready. tmux session '$session' running port-forward: remote localhost:80 → Grafana."
echo "👉 From your laptop: ssh -p <SSH_PORT> -N -L 3000:localhost:80 <user>@<host>  ; open http://localhost:3000"

