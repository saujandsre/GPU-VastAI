#!/bin/bash
# Runs: prechecks.sh -> control_node.sh -> gpu_node.sh -> monitoring.sh
# Assumes all four scripts are in the same directory as this file.
# Tip: run as root since the inner scripts install packages, etc.

set -e  # stop if any script fails

# Required scripts (edit names here if yours differ)
SCRIPTS=(
  "prechecks.sh"
  "control_node.sh"
  "gpu_node.sh"
  "monitoring.sh"
)

# Make sure they exist and are executable
for s in "${SCRIPTS[@]}"; do
  if [[ ! -f "$s" ]]; then
    echo "Missing: $s (expected in current directory)"
    exit 1
  fi
done

chmod +x "${SCRIPTS[@]}"

echo "▶️  Running prechecks..."
./prechecks.sh

echo "▶️  Running control-plane setup..."
./control_node.sh

echo "▶️  Running GPU node setup..."
./gpu_node.sh

echo "▶️  Installing monitoring stack + starting Grafana port-forward (tmux)..."
./monitoring.sh

echo "✅ All steps complete."
echo "ℹ️ From your laptop, open the tunnel and browse Grafana:"
echo "    ssh -p <SSH_PORT> -N -L 3000:localhost:80 <user>@<public_ip>"
echo "    → http://localhost:3000"

