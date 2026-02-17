# GPU-VastAI ⚙️

Hands-on lab for running **GPU inference workloads on Kubernetes** — from bare-metal scripts to production-style vLLM serving with full observability.

Two cluster modes:

| Mode | What it does |
|------|-------------|
| **SingleNodeClusterSetup** | Everything on one Vast.ai GPU box — quick experiments, model testing, baseline measurements |
| **MultiNodeClusterSetup** | Local control plane (your desktop) + ephemeral Vast.ai GPU workers joined via **Tailscale** — cost-effective, persistent cluster |

---

## Repository Structure

```
GPU-VastAI/
│
├── SingleNodeClusterSetup/
│   ├── baremetalGPU/                  # Run models directly on GPU host (no containers)
│   ├── containerGPU/                  # Dockerized FastAPI + HF Transformers inference
│   │   ├── app/                       #   FastAPI app (main.py, model_loader.py)
│   │   ├── k8s/                       #   Deployment, Service, ConfigMap manifests
│   │   └── Dockerfile
│   ├── vLLM_containerGPU/             # vLLM-based model serving on k8s
│   │   ├── k8s_clusterSetup/          #   Cluster bootstrap scripts + monitoring
│   │   ├── vllm_ymls/                 #   vLLM + UI deployments, services, configmaps
│   │   └── vllm_ui/                   #   FastAPI chat UI with Prometheus metrics
│   ├── PythonScripts/                 # GPU diagnostics & stress tests
│   └── Grafana/                       # Dashboard JSONs (GPU + LLM metrics)
│
├── MultiNodeClusterSetup/
│   ├── localControlPlane/             # Desktop-side control plane setup
│   │   ├── localControlPlane.sh       #   kubeadm init with Tailscale + Cilium CNI
│   │   ├── localCleanUp.sh            #   Full cluster teardown
│   │   ├── monitoringLocal.sh         #   Prometheus + Grafana stack
│   │   ├── enableGPUMonitoring.sh     #   Wire DCGM exporter → Prometheus
│   │   ├── GPUNodes.sh                #   NVIDIA GPU Operator install
│   │   ├── serviceMonitorGPU.yml      #   ServiceMonitor for DCGM metrics
│   │   └── Worker/
│   │       └── workerNodePrep.sh      #   Vast.ai worker bootstrap + Tailscale join
│   └── vLLM_containerGPU/             # vLLM serving manifests (multi-node variant)
│       ├── vllm_ymls/                 #   Same structure as single-node
│       └── vllm_ui/                   #   Chat UI + Prometheus instrumentation
│
└── README.md
```

---

## Quick Start

### Option A — Single-Node (Vast.ai GPU box)

```bash
cd SingleNodeClusterSetup/vLLM_containerGPU/k8s_clusterSetup
chmod +x *.sh
./runall.sh          # bootstraps k8s, GPU operator, Prometheus/Grafana

# Deploy vLLM
cd ../vllm_ymls
kubectl apply -f configMap.yml -f vllmDeploy.yml -f vllmService.yml
kubectl apply -f deployUI.yml -f serviceUI.yml -f serviceMonitorUI.yml

# Access
kubectl port-forward svc/vllm-ui 8080:8080 &
```

### Option B — Multi-Node (Local Desktop + Vast.ai Workers)

**On your desktop (control plane):**
```bash
cd MultiNodeClusterSetup/localControlPlane
sudo bash localControlPlane.sh    # kubeadm init + Cilium + Tailscale
bash monitoringLocal.sh            # Prometheus + Grafana
```

**On each Vast.ai worker:**
```bash
export TS_AUTHKEY="tskey-auth-..."
sudo -E bash workerNodePrep.sh     # installs k8s + Tailscale, configures kubelet
sudo kubeadm join <TAILSCALE_IP>:6443 --token ... --discovery-token-ca-cert-hash ...
```

**Back on control plane:**
```bash
kubectl label node <worker> node-role.kubernetes.io/worker=
bash GPUNodes.sh                   # installs NVIDIA GPU Operator
bash enableGPUMonitoring.sh        # wires DCGM → Prometheus

# Deploy vLLM
cd ../vLLM_containerGPU/vllm_ymls
kubectl apply -f configMap.yml -f vllmDeploy.yml -f vllmService.yml
kubectl apply -f deployUI.yml -f serviceUI.yml -f serviceMonitorUI.yml
kubectl port-forward svc/vllm-ui 8080:8080 &
```

---

## Monitoring

Two Grafana dashboards are provided in `SingleNodeClusterSetup/Grafana/`:

| Dashboard | Metrics |
|-----------|---------|
| **GPU-Dash.json** | SM clock frequency, GPU temperature, VRAM used/free, GPU utilization (via DCGM) |
| **LLM-Dash.json** | Request latency (P50/P95/P99), tokens in/out, request rate, error rate (via UI Prometheus metrics) |

Import via Grafana → Dashboards → Import → Upload JSON.

---

## Tech Stack

Kubernetes (kubeadm) · Cilium CNI · Tailscale VPN · NVIDIA GPU Operator · DCGM Exporter · Prometheus · Grafana · vLLM · FastAPI · PyTorch · Docker

---

## Author

**Saujan DSRE** — Production SRE @ IBM Cloud | AI/ML Infrastructure

- YouTube: [youtube.com/@SaujanBohara](https://www.youtube.com/@SaujanBohara)
- LinkedIn: [linkedin.com/in/saujanya-bohara](https://www.linkedin.com/in/saujanya-bohara/)
