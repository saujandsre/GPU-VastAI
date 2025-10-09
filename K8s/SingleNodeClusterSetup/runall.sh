#!/bin/bash
# Runs: preChecks.sh -> controlNode.sh -> GPUNodes.sh -> monitoring.sh
# Assumes all four scripts are in the *same directory* as this file.

set -euo pipefail

# Resolve this script's directory so you can run from anywhere
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Exact filenames found in your ls output (after renaming Monitoring.sh -> monitoring.sh)
SCRIPTS=(
  "preChecks.sh"
  "controlNode.sh"
  "GPUNodes.sh"
  "monitoring.sh"
)

# Verify presence and make executable
for s in "${SCRIPTS[@]}"; do
  if [[ ! -f "$DIR/$s" ]]; then
    echo "Missing: $s (expected in $DIR)"
    exit 1
  fi
  chmod +x "$DIR/$s"
done

echo "▶️  Running prechecks..."
"$DIR/preChecks.sh"

echo "▶️  Running control-plane setup..."
"$DIR/controlNode.sh"

echo "▶️  Running GPU node setup..."
"$DIR/GPUNodes.sh"

echo "▶️  Installing monitoring stack + starting Grafana port-forward (tmux)..."
"$DIR/monitoring.sh"

echo "✅ All steps complete."
echo "ℹ️  From your laptop, open the tunnel and browse Grafana:"
echo "    ssh -p <SSH_PORT> -N -L 3000:localhost:80 <user>@<public_ip>"
echo '    → http://localhost:3000'

