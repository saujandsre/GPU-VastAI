#!/usr/bin/env bash
# Simple one-shot venv setup for your lab.
# Creates ~/venvs/aml-gpu and installs Torch (CUDA 12.4) + HF tools.

set -e

ENV_DIR="$HOME/venvs/aml-gpu"

echo "[+] Creating venv at: $ENV_DIR"
mkdir -p "$(dirname "$ENV_DIR")"
python3 -m venv "$ENV_DIR"

echo "[+] Activating venv"
# shellcheck disable=SC1090
source "$ENV_DIR/bin/activate"

echo "[+] Upgrading pip"
python -m pip install -U pip

echo "[+] Installing PyTorch (CUDA 12.4 runtime wheels)"
python -m pip install --index-url https://download.pytorch.org/whl/cu124 \
  torch torchvision torchaudio

echo "[+] Installing Hugging Face tooling"
python -m pip install -U transformers accelerate safetensors sentencepiece huggingface_hub

echo "[+] Verifying"
python - <<'PY'
import torch
print("torch:", torch.__version__, "| cuda:", torch.version.cuda, "| gpu?", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu[0]:", torch.cuda.get_device_name(0))
PY

echo
echo "[✓] Done. To use this env in any new shell:"
echo "    source $ENV_DIR/bin/activate"

