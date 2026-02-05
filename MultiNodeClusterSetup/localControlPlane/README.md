# GPU-VastAI: Local Control Plane + Ephemeral GPU Workers (Tailscale)

This repo bootstraps a **Kubernetes control plane on your local desktop** and lets you attach **GPU worker nodes (e.g., Vast.ai)** without rebuilding the cluster.  
Monitoring is installed locally (Prometheus/Grafana), and GPU metrics are exported via NVIDIA DCGM.

## Repo layout

```bash
.
├── localControlPlane.sh        # install dependencies + init local control plane
├── localCleanUp.sh             # rollback/cleanup if control-plane setup goes wrong
├── monitoringLocal.sh          # install Prometheus + Grafana stack (kube-prometheus-stack style)
├── enableGPUMonitoring.sh      # enable GPU metrics scraping (ServiceMonitor / wiring)
├── GPUNodes.sh                 # install NVIDIA GPU Operator (on GPU-capable nodes)
├── serviceMonitorGPU.yml       # ServiceMonitor for DCGM exporter
└── Worker/
    └── workerNodePrep.sh       # run on each worker node before kubeadm join


Label the worker nodes

kubectl label node <vast-worker-name> node-role.kubernetes.io/worker=
