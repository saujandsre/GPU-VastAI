# Multi-Node K8s Cluster Debugging Session

**Date:** 6 February 2026
**Cluster:** Local control plane (saujan) + Vast.ai GPU worker (vast-worker-1)
**Networking:** Tailscale VPN mesh between nodes

---

## Cluster Topology

```
┌──────────────────────────┐         Tailscale VPN         ┌──────────────────────────┐
│  saujan (control-plane)  │◄──────────────────────────────►│  vast-worker-1 (GPU)     │
│  Ubuntu 24.04            │     100.105.216.68 ↔           │  Ubuntu 22.04            │
│  k8s v1.34.3             │          100.99.161.5          │  k8s v1.34.3             │
│  Calico CNI              │                                │  NVIDIA GPU Operator     │
│  Prometheus + Grafana    │                                │  vLLM + UI pods          │
└──────────────────────────┘                                └──────────────────────────┘
```

---

## Problem 1: vLLM UI pod cannot reach vLLM API pod (DNS failure)

### Symptom

```
Failed to contact vLLM: [Errno -3] Temporary failure in name resolution
```

The UI pod (`vllm-ui`) on `vast-worker-1` could not resolve `vllm-api.default.svc.cluster.local`, even though both pods were on the same worker node.

### Why DNS still needs cross-node connectivity

Even when two pods are on the same node, DNS resolution goes through CoreDNS, which runs on the control plane (`saujan`). The pod's `/etc/resolv.conf` points to `nameserver 10.96.0.10` (the `kube-dns` ClusterIP). For the worker pod to reach that ClusterIP, kube-proxy NATs the request to the actual CoreDNS pod IP on `saujan` — which requires working cross-node pod networking.

### Diagnostic commands used

```bash
# Check if DNS resolves from the pod
kubectl exec vllm-ui-79c6784f94-r5kln -- python3 -c "
import socket
try:
    print(socket.getaddrinfo('vllm-api.default.svc.cluster.local', 8000))
except Exception as e:
    print(f'DNS FAIL: {e}')
"
# Result: DNS FAIL: [Errno -3] Temporary failure in name resolution

# Check resolv.conf
kubectl exec vllm-ui-79c6784f94-r5kln -- cat /etc/resolv.conf
# Result: nameserver 10.96.0.10 (correct — points to kube-dns ClusterIP)

# Check if CoreDNS ClusterIP is reachable via TCP
kubectl exec vllm-ui-79c6784f94-r5kln -- python3 -c "
import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(3)
try:
    s.connect(('10.96.0.10', 53)); print('CoreDNS reachable')
except: print('CoreDNS UNREACHABLE')
finally: s.close()
"
# Result: CoreDNS UNREACHABLE

# Check pod-to-pod (bypassing ClusterIP) — direct CoreDNS pod IP
kubectl exec vllm-ui-79c6784f94-r5kln -- python3 -c "
import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
try:
    s.connect(('192.168.153.189', 53)); print('Pod-to-pod REACHABLE')
except: print('Pod-to-pod UNREACHABLE')
finally: s.close()
"
# Result: Pod-to-pod UNREACHABLE

# From vast-worker-1 host — can it ping saujan's pod CIDR?
ping -c 2 192.168.153.138
# Result: 100% packet loss
```

**Conclusion:** Complete pod-to-pod networking failure between nodes. The issue is at the CNI overlay level, not DNS itself.

---

## Root Cause 1: kubelet advertising wrong IP (LAN IP vs Tailscale IP)

### What was wrong

```bash
kubectl get nodes -o wide
# saujan: InternalIP = 192.168.68.117   ← LAN IP (unreachable from Vast.ai)
# vast-worker-1: InternalIP = 100.99.161.5  ← Tailscale IP (correct)
```

Calico uses the node's InternalIP for BGP peering and IPIP tunnel endpoints. The worker was trying to send encapsulated traffic to `192.168.68.117`, which is saujan's LAN IP — completely unreachable from the internet/Tailscale.

### Fix applied

```bash
# On saujan (control plane):
echo "KUBELET_EXTRA_ARGS=--node-ip=$(tailscale ip -4)" | sudo tee /etc/default/kubelet
sudo systemctl restart kubelet
```

### Result after fix

```bash
kubectl get nodes -o wide
# saujan: InternalIP = 100.105.216.68   ← Tailscale IP (correct now)
# vast-worker-1: InternalIP = 100.99.161.5  ← Tailscale IP (was already correct)
```

**But pod-to-pod was still broken.** This fix was necessary but not sufficient.

---

## Root Cause 2: Calico IPIP encapsulation doesn't work over Tailscale

### What was wrong

```bash
kubectl get ippools.crd.projectcalico.org -o yaml | grep -A2 ipipMode
# ipipMode: Always
```

Calico's default `ipipMode: Always` uses **IP-in-IP encapsulation (IP protocol 4)**. This is a raw IP protocol, not TCP or UDP. Tailscale's userspace WireGuard tunnel only carries TCP and UDP traffic — it silently drops IP protocol 4 packets.

### How IPIP works (and why it fails)

```
Normal UDP packet:
  [Tailscale outer] → [UDP header] → [payload]  ✅ Tailscale forwards this

IPIP encapsulated packet:
  [Tailscale outer] → [IP proto 4 header] → [inner IP packet]  ❌ Tailscale drops this
```

### VXLAN alternative

VXLAN encapsulates overlay traffic inside **UDP packets (port 4789)**, which Tailscale handles perfectly.

```
VXLAN encapsulated packet:
  [Tailscale outer] → [UDP:4789 header] → [VXLAN header] → [inner frame]  ✅ Works
```

### Fix applied

```bash
# Switch from IPIP to VXLAN
kubectl patch ippool default-ipv4-ippool --type merge -p \
  '{"spec":{"ipipMode":"Never","vxlanMode":"Always"}}'

# Restart Calico to pick up changes
kubectl rollout restart daemonset calico-node -n kube-system

# Verified both Calico pods came up 1/1
kubectl -n kube-system get pods -l k8s-app=calico-node -o wide
```

### Result after fix

```bash
# CoreDNS now reachable from worker pods
CoreDNS REACH

---

## Problem 2: Grafana showing only 1 GPU

### Symptom

GPU dashboard in Grafana only showed metrics for saujan's GPU, not vast-worker-1's GPU.

### Diagnosis

```bash
# DCGM exporter pods — running on both nodes ✅
kubectl get pods -l app=nvidia-dcgm-exporter -o wide
# nvidia-dcgm-exporter-rbgbl  vast-worker-1
# nvidia-dcgm-exporter-rlvsz  saujan

# DCGM Service endpoints — both IPs present ✅
kubectl get endpoints nvidia-dcgm-exporter
# 192.168.153.139:9400, 192.168.242.194:9400

# ServiceMonitor exists ✅
kubectl get servicemonitor -n monitoring | grep dcgm
# dcgm-exporter   16d
```

### Root cause

Same networking issue. Prometheus (running on saujan) couldn't scrape the DCGM exporter pod on vast-worker-1 (192.168.242.194) because pod-to-pod traffic was broken.

### Fix

The Calico IPIP → VXLAN fix above resolves this too. Once pod overlay networking works, Prometheus can scrape both endpoints.

### Verification

After the VXLAN fix, check Prometheus targets:

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
# Open http://localhost:9090/targets → look for dcgm-exporter → should show 2 endpoints UP
```

---

## Problem 3: Port 8080 already in use for port-forward

### Symptom

```
Error listen tcp4 127.0.0.1:8080: bind: address already in use
```

### Cause

An existing SSH tunnel was occupying port 8080:

```bash
ss -tulnp | grep 8080
# tcp  LISTEN  0  128  127.0.0.1:8080  users:(("ssh",pid=32440,fd=5))
```

### Workaround

Used a different local port:

```bash
kubectl port-forward svc/vllm-ui 6060:8080 &
# Access UI at http://localhost:6060
```

---

## Summary of all fixes applied

| # | Problem | Root cause | Fix |
|---|---------|-----------|-----|
| 1 | saujan InternalIP was LAN IP | kubelet not configured for Tailscale | `--node-ip=$(tailscale ip -4)` in `/etc/default/kubelet` |
| 2 | Pod-to-pod traffic dropped | Calico IPIP (IP proto 4) not carried by Tailscale | Patched IPPool: `ipipMode: Never`, `vxlanMode: Always` |
| 3 | DNS failure in worker pods | Consequence of #2 — couldn't reach CoreDNS | Fixed by #2 |
| 4 | Grafana missing worker GPU | Consequence of #2 — Prometheus couldn't scrape worker | Fixed by #2 |
| 5 | Port 8080 conflict | SSH tunnel occupying the port | Used alternative port 6060 |

---

## Key takeaway

**When using Tailscale (or any userspace VPN) as the node-to-node transport for Kubernetes, you must use a UDP-based CNI overlay (VXLAN, Geneve, WireGuard-native) — never IPIP or raw IP encapsulation.** Tailscale's WireGuard tunnel only forwards TCP and UDP, silently dropping other IP protocols.

The chain of failures was:

```
Tailscale drops IP protocol 4
  → Calico IPIP tunnel broken
    → No pod-to-pod connectivity across nodes
      → CoreDNS unreachable from worker pods
        → DNS fails → Services fail → UI can't talk to vLLM
      → Prometheus can't scrape worker DCGM exporter
        → Grafana missing GPU metrics
```

---

## Next step: Cilium migration

Cilium defaults to VXLAN (UDP 8472) encapsulation, which works natively over Tailscale. It also offers:

- eBPF-based dataplane (replaces kube-proxy iptables rules)
- Hubble for network observability
- Network policies with L7 visibility
- Native WireGuard encryption option

### Migration plan (separate session)

1. Drain and cordon the worker node
2. `kubeadm reset` on the worker
3. Remove Calico from the control plane (`kubectl delete -f calico.yaml`)
4. Flush iptables and remove CNI configs on both nodes
5. Install Cilium via Helm on the control plane
6. Re-join the worker with `kubeadm join`
7. Redeploy GPU Operator + vLLM stack
8. Verify with Hubble

---

## Useful debug commands reference

```bash
# Check node IPs
kubectl get nodes -o wide

# Check Calico encapsulation mode
kubectl get ippools.crd.projectcalico.org -o yaml | grep -E "ipipMode|vxlanMode"

# Test pod-to-pod TCP connectivity
kubectl exec <pod> -- python3 -c "
import socket; s=socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
try: s.connect(('<target-pod-ip>', <port>)); print('REACHABLE')
except: print('UNREACHABLE')
finally: s.close()
"

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Check DCGM exporter endpoints
kubectl get endpoints nvidia-dcgm-exporter

# Check Calico node status
kubectl -n kube-system get pods -l k8s-app=calico-node -o wide

# Check Prometheus scrape targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets

# Check kubelet node-ip config
cat /etc/default/kubelet
```
