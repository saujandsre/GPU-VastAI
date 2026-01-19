#!/bin/bash
# Runs: preChecks.sh -> controlNode.sh -> GPUNodes.sh -> monitoring.sh -> setup_torch_venv.sh
# Assumes all scripts are in the *same directory* as this file.

set -euo pipefail

# Resolve this script's directory so you can run from anywhere
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Core scripts (must exist)
CORE_SCRIPTS=(
  "preChecks.sh"
  "controlNode.sh"
  "GPUNodes.sh"
  "monitoring.sh"
)

# Verify presence of core scripts and make everything executable
for s in "${CORE_SCRIPTS[@]}"; do
  if [[ ! -f "$DIR/$s" ]]; then
    echo "❌ Missing: $s (expected in $DIR)"
    exit 1
  fi
  chmod +x "$DIR/$s"
done

echo "▶️  Running prechecks..."
"$DIR/preChecks.sh"

echo "▶️  Setting up control plane..."
"$DIR/controlNode.sh"

echo "▶️  Setting up GPU node(s)..."
"$DIR/GPUNodes.sh"

echo "▶️  Installing monitoring stack (Prometheus/Grafana) and starting port-forward (if any)..."
"$DIR/monitoring.sh"


# Helpful connection tip
echo
echo "ℹ️  From your laptop, open an SSH tunnel to Grafana then browse:"
echo "    ssh -p <SSH_PORT> -N -L 3000:localhost:80 <user>@<public_ip>"
echo "    → http://localhost:3000"

#Creating the servicemonitor for DCGM exports
kubectl apply -f "$DIR/serviceMonitorGPU.yml"


