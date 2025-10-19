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

# Torch venv script: support either name (single or double underscores)
VENV_CANDIDATES=("setup_torch_venv.sh" "setup__torch__venv.sh")
SETUP_VENV=""
for cand in "${VENV_CANDIDATES[@]}"; do
  if [[ -f "$DIR/$cand" ]]; then
    SETUP_VENV="$cand"
    break
  fi
done

if [[ -z "$SETUP_VENV" ]]; then
  echo "⚠️  Could not find setup_torch_venv script. Looked for: ${VENV_CANDIDATES[*]}"
  echo "    (The rest will still run.)"
fi

# Verify presence of core scripts and make everything executable
for s in "${CORE_SCRIPTS[@]}"; do
  if [[ ! -f "$DIR/$s" ]]; then
    echo "❌ Missing: $s (expected in $DIR)"
    exit 1
  fi
  chmod +x "$DIR/$s"
done
if [[ -n "$SETUP_VENV" ]]; then
  chmod +x "$DIR/$SETUP_VENV"
fi

echo "▶️  Running prechecks..."
"$DIR/preChecks.sh"

echo "▶️  Setting up control plane..."
"$DIR/controlNode.sh"

echo "▶️  Setting up GPU node(s)..."
"$DIR/GPUNodes.sh"

echo "▶️  Installing monitoring stack (Prometheus/Grafana) and starting port-forward (if any)..."
"$DIR/monitoring.sh"

if [[ -n "$SETUP_VENV" ]]; then
  echo "▶️  Creating Python venv and installing Torch (via $SETUP_VENV)..."
  "$DIR/$SETUP_VENV"
else
  echo "⏭️  Skipping Torch venv setup (script not found)."
fi

echo "✅ All steps complete."

# Helpful connection tip
echo
echo "ℹ️  From your laptop, open an SSH tunnel to Grafana then browse:"
echo "    ssh -p <SSH_PORT> -N -L 3000:localhost:80 <user>@<public_ip>"
echo "    → http://localhost:3000"

# Print a tiny venv how-to (even if the torch setup ran)
cat <<'EOF'

— Python venv quick start —
Create a new environment named "torch":
  python3 -m venv ~/venvs/torch

Activate it:
  source ~/venvs/torch/bin/activate

Deactivate when done:
  deactivate
EOF

