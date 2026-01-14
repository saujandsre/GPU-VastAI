# Minimal GPU FastAPI inference image (CUDA 12.4 runtime + PyTorch cu124)

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Tiny base: only Python + pip
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# --- Python deps ---
# 1) Install CUDA-enabled PyTorch that matches the base image (cu124)
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    python3 -m pip install --no-cache-dir \
      torch==2.4.1+cu124 torchvision==0.19.1+cu124 \
      --extra-index-url https://download.pytorch.org/whl/cu124

# 2) Minimal app deps
COPY app/requirements.txt /app/requirements.txt
RUN python3 -m pip install --no-cache-dir -r /app/requirements.txt

# --- App code ---
COPY app/ /app/

EXPOSE 8000

# Start the API
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

