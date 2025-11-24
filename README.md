# GPU-VastAI ⚙️

Personal lab project for experimenting with **GPU workloads**, **Python GPU utilities**, and **Kubernetes automation** across:

- Bare-metal GPU runs  
- Containerized GPU workloads  
- vLLM-based serving on Kubernetes  

---

## 🗂️ Repository Structure

```bash
GPU-VastAI/
│
├── bare-metal-gpu/
│   └── Scripts / notes for running models directly on the GPU host
│
├── container-gpu/
│   └── Docker / container setup for running the same workloads in containers
│
├── vllm-container-gpu/
│   ├── app/                     # vLLM server + UI / client code
│   └── kubernetes-cluster-setup/
│       └── ...                  # K8s manifests/scripts to prep the cluster for vLLM
│
├── K8s/
│   └── SingleNodeClusterSetup/
│       ├── preChecks.sh
│       ├── controlNode.sh
│       ├── GPUNodes.sh
│       ├── monitoring.sh
│       ├── runall.sh
│       ├── setup_torch_venv.sh
│       ├── general.txt
│       └── ymls/
│           ├── GPU_Access.yml
│           └── serviceMonitorGPU.yml
│
├── PythonScripts/
│   ├── checkCUDA_GPUinfo.py
│   └── continousMatrixMultiplication.py
│
└── Grafana/
    └── GPU-Dash.json

What each area is for

    bare-metal-gpu/
    Run models directly on the GPU host (no containers). Useful for baseline measurements and simple experiments.

    container-gpu/
    Run the same or similar workloads inside containers (e.g. Docker). Good for comparing bare-metal vs container overhead and for more reproducible runs.

    vllm-container-gpu/
    vLLM-based serving in containers.

        Includes everything needed to stand up a vLLM deployment.

        Contains its own Kubernetes cluster setup under kubernetes-cluster-setup/ that is tuned for this vLLM environment.

        The wider K8s/SingleNodeClusterSetup still works for vLLM as well, but it has extra dependencies; vllm-container-gpu is the recommended path if you just want vLLM running quickly.

    K8s/SingleNodeClusterSetup/
    Generic single-node Kubernetes cluster setup with GPU support and monitoring:

        Control-plane and GPU node bootstrap scripts

        GPU access YAMLs

        Prometheus + DCGM Exporter + Grafana stack via monitoring.sh

    PythonScripts/
    Small Python utilities for:

        GPU diagnostics (checkCUDA_GPUinfo.py)

        Simple CUDA-based workload testing (continousMatrixMultiplication.py)

    Grafana/
    Custom GPU dashboard JSON (GPU-Dash.json) used with Prometheus + DCGM Exporter to visualize:

        GPU utilization

        VRAM usage

        Temperature

        Cluster-level metrics

🚀 Quick Start
1. Clone the repo

git clone https://github.com/<your-username>/GPU-VastAI.git
cd GPU-VastAI

2. Stand up the generic single-node K8s + GPU monitoring stack (optional but reusable)

Use this if you want a general-purpose Kubernetes + monitoring environment:

cd K8s/SingleNodeClusterSetup
chmod +x *.sh
./runall.sh

This will:

    Bootstrap a single-node K8s cluster

    Configure GPU access

    Deploy Prometheus + DCGM Exporter + Grafana using the provided YAMLs

3. Choose your path

    Bare-metal GPU experiments

cd bare-metal-gpu
# See files in this directory for environment setup and run instructions

Containerized GPU workloads

cd container-gpu
# Build and run the GPU container(s) as documented here

vLLM in containers (recommended for vLLM)

    cd vllm-container-gpu
    # 1) Use kubernetes-cluster-setup/ to prepare the cluster for this vLLM stack
    # 2) Deploy vLLM server + UI from this directory

👤 Author

Saujan DSRE
SRE | AI/ML Infrastructure & GPU Enthusiast

🔗
YouTube: https://www.youtube.com/@SaujanBohara

LinkedIn: https://www.linkedin.com/in/saujanya-bohara/

