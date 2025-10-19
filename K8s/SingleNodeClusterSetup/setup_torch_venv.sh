#!/usr/bin/env bash
ENV_NAME="${1:-venv}"

python3 -m pip --version >/dev/null 2>&1 || python3 -m ensurepip --upgrade
python3 -m venv "$ENV_NAME"
. "$ENV_NAME/bin/activate"
pip install -U pip

pip install --index-url https://download.pytorch.org/whl/cu124 torch torchvision torchaudio

python -c 'import torch; print("torch", torch.__version__, "cuda?", torch.cuda.is_available())'
echo "Activate later with: source $ENV_NAME/bin/activate"

