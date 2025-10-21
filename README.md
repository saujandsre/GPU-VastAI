# GPU-VastAI ⚙️

Personal lab project for experimenting with **GPU workloads**, **Python GPU utilities**, and **Kubernetes automation**.

---

## 🗂️ Structure

```bash
GPU-VastAI/
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
└── PythonScripts/
    ├── checkCUDA_GPUinfo.py
    └── continousMatrixMultiplication.py

🧩 Description

    K8s/ → Shell scripts and YAML files to automate a single-node Kubernetes cluster with GPU support and monitoring stack.

    PythonScripts/ → Python utilities for GPU diagnostics and basic GPU workload tests.

🚀 Quick Start

git clone https://github.com/<your-username>/GPU-VastAI.git
cd GPU-VastAI/K8s/SingleNodeClusterSetup
chmod +x *.sh
./runall.sh

👤 Author

Saujan DSRE
SRE | AI/ML Infrastructure & GPU Enthusiast
🔗 YouTube : https://www.youtube.com/@SaujanBohara
• LinkedIn : https://www.linkedin.com/in/saujanya-bohara/
