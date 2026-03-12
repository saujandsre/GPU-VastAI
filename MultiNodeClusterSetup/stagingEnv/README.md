# Model Router — Staging Build Plan

## Architecture (what we're building)

```
[fake-ui pod] → [router-svc] → [redis-svc] → (later: real vLLM backends)
     curl          FastAPI        backend
                  routing          health
                  logic            store
```

All in `staging` namespace. No production impact.

---

## Phase 1a: UI → Router
 **Goal:** Prove svc-to-svc connectivity, router returns hardcoded backend status.

### Deploy
```bash
kubectl apply -f 00-namespace.yml
kubectl apply -f 01-router-configmap.yml
kubectl apply -f 02-router-deploy.yml
kubectl apply -f 03-fake-ui.yml
```

### Wait for router to be ready (~30s for pip install on first start)
```bash
kubectl get pods -n staging -w
# Wait until router pod shows 1/1 Running
```

### Test
```bash
kubectl exec -it fake-ui -n staging -- sh

# Inside the pod:
curl -s http://router-svc:8080/health
curl -s http://router-svc:8080/backends
curl -s http://router-svc:8080/route
```

### Expected output for /route:
```json
{
  "routed_to": "vllm-1",
  "backend_status": {"status": "green", "gpu_util": 45, "queue_depth": 2},
  "reason": "lowest priority score + queue_depth"
}
```

### ✅ Phase 1a DONE when:
- [x] fake-ui can curl router-svc
- [x] /backends returns 2 hardcoded backends
- [x] /route picks the green one

---

## Phase 1b: Add Redis 
**Goal:** Router reads backend status from Redis instead of hardcoded dict.
- Deploy Redis pod + service in staging
- Update router code to read from Redis
- Manually set keys: `redis-cli SET backend:vllm-1 '{"status":"yellow",...}'`
- Curl /backends and see it reflect Redis data
- Change Redis value to "red", curl again, see it change

## Phase 2: Routing Logic
- Three-tier classification (green/yellow/red)
- Weighted routing based on GPU util + queue depth
- /route returns different backends as you change Redis values

## Phase 3: Integrate with Production
- Move router into default namespace
- Point UI service → router-svc → vllm-api
- Router reads real vLLM /metrics for health data

## Phase 4: Autoscaling + Observability
- Prometheus metrics on router
- Grafana dashboard for routing decisions
- SLO-based scaling triggers
