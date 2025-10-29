# CUDA 12.9 runtime (matches your 575.51.03 driver)
FROM nvidia/cuda:12.9.0-cudnn-runtime-ubuntu22.04

WORKDIR /app
RUN apt-get update && apt-get install -y python3-pip 

# Deps
COPY app/requirements.txt /app/app/requirements.txt
RUN pip3 install  --upgrade pip \
 && pip3 install  -r /app/app/requirements.txt \
 # PyTorch built for CUDA 12.x (cu124 works fine with 12.9 drivers)
 && pip3 install  --index-url https://download.pytorch.org/whl/cu124 \
    torch==2.4.1 torchvision==0.19.1

#APP
COPY app /app/app

#Service
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
