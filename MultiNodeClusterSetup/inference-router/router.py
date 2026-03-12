"""
Adaptive Inference Router v2 — Pod-Aware Edition

Key changes from v1:
  - Discovers vLLM pod IPs via K8s Endpoints API (watches vllm-api Service)
  - Polls each pod's /metrics individually (not via the Service)
  - Routes to the least-loaded pod (lowest queue depth + KV cache)
  - Tracks per-pod metrics in Prometheus
  - Injects pod identity into response so UI shows which pod served

Architecture:
  1. Endpoint watcher: periodically resolves vllm-api Service → list of pod IPs
  2. Per-pod poller: polls each pod's /metrics every 3s
  3. Router: picks best pod based on real load, classifies tier, forwards
"""

import os
import re
import time
import asyncio
import logging
from typing import Optional

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

from prometheus_client import (
    Counter,
    Gauge,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

# ─────────────────────────── Config ───────────────────────────

VLLM_SERVICE = os.environ.get("VLLM_SERVICE", "vllm-api")
VLLM_PORT = int(os.environ.get("VLLM_PORT", "8000"))
VLLM_NAMESPACE = os.environ.get("VLLM_NAMESPACE", "default")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "3"))
ENDPOINT_REFRESH_INTERVAL = int(os.environ.get("ENDPOINT_REFRESH_INTERVAL", "10"))
STALENESS_TIMEOUT = int(os.environ.get("STALENESS_TIMEOUT", "10"))

# Tier thresholds
GREEN_QUEUE_MAX = int(os.environ.get("GREEN_QUEUE_MAX", "5"))
GREEN_CACHE_MAX = float(os.environ.get("GREEN_CACHE_MAX", "0.70"))
RED_QUEUE_MIN = int(os.environ.get("RED_QUEUE_MIN", "10"))
RED_CACHE_MIN = float(os.environ.get("RED_CACHE_MIN", "0.90"))
RED_TPT_MIN = float(os.environ.get("RED_TPT_MIN", "0.100"))

GREEN_MAX_TOKENS = int(os.environ.get("GREEN_MAX_TOKENS", "512"))
YELLOW_MAX_TOKENS = int(os.environ.get("YELLOW_MAX_TOKENS", "128"))

# K8s API — uses in-cluster service account (auto-mounted in pods)
K8S_API = "https://kubernetes.default.svc"
K8S_TOKEN_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/token"
K8S_CA_PATH = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("router")


# ─────────────────────────── Pod Registry ─────────────────────

class PodMetrics:
    """Holds cached metrics for a single vLLM pod."""
    def __init__(self, ip: str):
        self.ip = ip
        self.url = f"http://{ip}:{VLLM_PORT}"
        self.num_requests_waiting: float = 0
        self.num_requests_running: float = 0
        self.gpu_cache_usage_perc: float = 0.0
        self.time_per_output_token_seconds: float = 0.0
        self.last_poll_ts: float = 0.0
        self.poll_healthy: bool = False
        self.requests_served: int = 0

    @property
    def load_score(self) -> float:
        """Lower is better. Combines queue, running requests, and cache pressure."""
        # FIX 2: includes num_requests_running so a pod with 49 running scores 49, not 0
        return self.num_requests_waiting + self.num_requests_running + (self.gpu_cache_usage_perc * 10)

    @property
    def is_stale(self) -> bool:
        return (time.time() - self.last_poll_ts) > STALENESS_TIMEOUT

    def tier(self) -> str:
        if self.is_stale or not self.poll_healthy:
            return "green"  # fail-open
        if (self.num_requests_waiting >= RED_QUEUE_MIN or
                self.gpu_cache_usage_perc >= RED_CACHE_MIN or
                self.time_per_output_token_seconds >= RED_TPT_MIN):
            return "red"
        if (self.num_requests_waiting >= GREEN_QUEUE_MAX or
                self.gpu_cache_usage_perc >= GREEN_CACHE_MAX):
            return "yellow"
        return "green"


# Registry of known pods
pod_registry: dict[str, PodMetrics] = {}  # ip -> PodMetrics


# ─────────────────────────── Endpoint Discovery ───────────────

async def _discover_endpoints():
    """
    Periodically query K8s Endpoints API to find vLLM pod IPs.
    This replaces hardcoded service URL with real pod discovery.
    """
    log.info(f"Endpoint watcher started — watching Service: {VLLM_SERVICE}")

    while True:
        try:
            token = ""
            if os.path.exists(K8S_TOKEN_PATH):
                with open(K8S_TOKEN_PATH) as f:
                    token = f.read().strip()

            url = f"{K8S_API}/api/v1/namespaces/{VLLM_NAMESPACE}/endpoints/{VLLM_SERVICE}"
            headers = {"Authorization": f"Bearer {token}"} if token else {}
            verify = K8S_CA_PATH if os.path.exists(K8S_CA_PATH) else False

            async with httpx.AsyncClient(timeout=5.0, verify=verify) as client:
                resp = await client.get(url, headers=headers)
                resp.raise_for_status()

            data = resp.json()
            current_ips = set()

            for subset in data.get("subsets", []):
                for addr in subset.get("addresses", []):
                    ip = addr["ip"]
                    current_ips.add(ip)

                    if ip not in pod_registry:
                        pod_registry[ip] = PodMetrics(ip)
                        log.info(f"Discovered new pod: {ip}")

            # Remove pods that are no longer in endpoints
            stale_ips = set(pod_registry.keys()) - current_ips
            for ip in stale_ips:
                del pod_registry[ip]
                log.info(f"Removed stale pod: {ip}")

            POD_COUNT.set(len(pod_registry))

        except Exception as e:
            log.warning(f"Endpoint discovery failed: {e}")
            if not pod_registry:
                fallback_ip = VLLM_SERVICE
                if fallback_ip not in pod_registry:
                    pod_registry[fallback_ip] = PodMetrics(fallback_ip)
                    pod_registry[fallback_ip].url = f"http://{VLLM_SERVICE}:{VLLM_PORT}"
                    log.info(f"Fallback: using service DNS {VLLM_SERVICE}")

        await asyncio.sleep(ENDPOINT_REFRESH_INTERVAL)


# ─────────────────────────── Metrics Parser ───────────────────

def _parse_vllm_metrics(text: str) -> dict:
    """
    Parse Prometheus text format from vLLM /metrics.

    vLLM versions use different metric name formats:
      - vllm:num_requests_waiting      (colon separator)
      - vllm_num_requests_waiting      (underscore separator)
      - num_requests_waiting           (no prefix)

    We handle all three by making the prefix optional.
    """
    parsed = {}

    # FIX 1: kv_cache_usage_perc is the actual vLLM metric name, NOT gpu_cache_usage_perc
    patterns = {
        "num_requests_waiting": r'^(?:vllm[_:])?num_requests_waiting\b.*?\s+([\d.eE+-]+)',
        "num_requests_running": r'^(?:vllm[_:])?num_requests_running\b.*?\s+([\d.eE+-]+)',
        "gpu_cache_usage_perc": r'^(?:vllm[_:])?kv_cache_usage_perc\b.*?\s+([\d.eE+-]+)',
        "avg_generation_throughput": r'^(?:vllm[_:])?avg_generation_throughput_toks_per_s\b.*?\s+([\d.eE+-]+)',
    }

    for key, pattern in patterns.items():
        matches = re.findall(pattern, text, re.MULTILINE)
        if matches:
            parsed[key] = float(matches[-1])

    throughput = parsed.get("avg_generation_throughput", 0)
    parsed["time_per_output_token_seconds"] = (1.0 / throughput) if throughput > 0 else 0.0

    return parsed


# ─────────────────────────── Per-Pod Poller ───────────────────

async def _poll_pod(pod: PodMetrics):
    """Poll a single pod's /metrics endpoint."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{pod.url}/metrics")
            resp.raise_for_status()

        parsed = _parse_vllm_metrics(resp.text)
        pod.num_requests_waiting = parsed.get("num_requests_waiting", 0)
        pod.num_requests_running = parsed.get("num_requests_running", 0)
        pod.gpu_cache_usage_perc = parsed.get("gpu_cache_usage_perc", 0.0)
        pod.time_per_output_token_seconds = parsed.get("time_per_output_token_seconds", 0.0)
        pod.last_poll_ts = time.time()
        pod.poll_healthy = True

        # Debug: log when pod has active requests so we can verify metrics are flowing
        if pod.num_requests_running > 0 or pod.num_requests_waiting > 0:
            log.info(f"Pod {pod.ip}: waiting={pod.num_requests_waiting}, "
                     f"running={pod.num_requests_running}, "
                     f"cache={pod.gpu_cache_usage_perc:.3f}, "
                     f"score={pod.load_score:.1f}")

        # Update per-pod Prometheus gauges
        POD_QUEUE_DEPTH.labels(pod=pod.ip).set(pod.num_requests_waiting)
        POD_CACHE_PCT.labels(pod=pod.ip).set(pod.gpu_cache_usage_perc)
        POD_TPT.labels(pod=pod.ip).set(pod.time_per_output_token_seconds)
        POD_RUNNING.labels(pod=pod.ip).set(pod.num_requests_running)
        POD_HEALTHY.labels(pod=pod.ip).set(1)

    except Exception as e:
        pod.poll_healthy = False
        POD_HEALTHY.labels(pod=pod.ip).set(0)
        log.warning(f"Poll failed for {pod.ip}: {e}")


async def _poll_loop():
    """Poll all known pods every POLL_INTERVAL seconds."""
    log.info(f"Poller started — interval: {POLL_INTERVAL}s")

    while True:
        if pod_registry:
            await asyncio.gather(*[_poll_pod(pod) for pod in pod_registry.values()])

            all_pods = list(pod_registry.values())
            healthy_pods = [p for p in all_pods if p.poll_healthy and not p.is_stale]

            if healthy_pods:
                max_queue = max(p.num_requests_waiting for p in healthy_pods)
                max_cache = max(p.gpu_cache_usage_perc for p in healthy_pods)
                max_tpt = max(p.time_per_output_token_seconds for p in healthy_pods)
                BACKEND_QUEUE_DEPTH.set(max_queue)
                BACKEND_CACHE_PCT.set(max_cache)
                BACKEND_TPT.set(max_tpt)
                POLLER_HEALTHY.set(1)
            else:
                POLLER_HEALTHY.set(0)

        await asyncio.sleep(POLL_INTERVAL)


# ─────────────────────────── Routing Logic ────────────────────

# FIX 3: round-robin counter for tiebreaking when pods have equal load scores
_round_robin_counter = 0

def pick_best_pod() -> Optional[PodMetrics]:
    """
    Pick the least-loaded healthy pod.
    When scores are tied, round-robin to distribute evenly.
    Returns None if all pods are RED or unhealthy.
    """
    global _round_robin_counter

    candidates = []
    for pod in pod_registry.values():
        if pod.is_stale or not pod.poll_healthy:
            candidates.append((pod, pod.load_score + 1000))  # deprioritise stale
        elif pod.tier() == "red":
            continue
        else:
            candidates.append((pod, pod.load_score))

    if not candidates:
        if pod_registry:
            return min(pod_registry.values(), key=lambda p: p.load_score)
        return None

    # Sort by load score
    candidates.sort(key=lambda x: x[1])
    best_score = candidates[0][1]

    # Find all pods tied at the best score
    tied = [c[0] for c in candidates if c[1] == best_score]

    # Round-robin among tied pods
    _round_robin_counter += 1
    chosen = tied[_round_robin_counter % len(tied)]

    return chosen


def classify_global_tier() -> str:
    """
    Global tier based on the BEST available pod.
    If at least one pod is GREEN, system is GREEN.
    """
    healthy = [p for p in pod_registry.values() if p.poll_healthy and not p.is_stale]
    if not healthy:
        return "green"  # fail-open

    tiers = [p.tier() for p in healthy]
    if "green" in tiers:
        return "green"
    if "yellow" in tiers:
        return "yellow"
    return "red"


# ─────────────────────────── Prometheus Metrics ───────────────

REQUESTS_TOTAL = Counter("router_requests_total", "Total requests by tier", ["tier"])
REQUESTS_SHED = Counter("router_requests_shed_total", "Total 503s")
REQUESTS_DEGRADED = Counter("router_requests_degraded_total", "Total YELLOW responses")
REQUEST_LATENCY = Histogram(
    "router_request_latency_seconds", "E2E latency", ["tier"],
    buckets=[0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0],
)

# Per-pod metrics
POD_QUEUE_DEPTH = Gauge("router_pod_queue_depth", "Queue depth per pod", ["pod"])
POD_CACHE_PCT = Gauge("router_pod_cache_pct", "KV cache % per pod", ["pod"])
POD_TPT = Gauge("router_pod_tpt_seconds", "Time per token per pod", ["pod"])
POD_RUNNING = Gauge("router_pod_requests_running", "Running requests per pod", ["pod"])
POD_HEALTHY = Gauge("router_pod_healthy", "Pod health status", ["pod"])
POD_SERVED = Counter("router_pod_requests_served_total", "Requests forwarded to pod", ["pod"])
POD_TOKENS = Counter("router_pod_tokens_total", "Tokens generated by pod", ["pod"])

# Aggregate metrics (for the top-row stat panels)
BACKEND_QUEUE_DEPTH = Gauge("router_backend_queue_depth", "Max queue depth across pods")
BACKEND_CACHE_PCT = Gauge("router_backend_cache_pct", "Max KV cache % across pods")
BACKEND_TPT = Gauge("router_backend_tpt_seconds", "Max time per token across pods")
POLLER_HEALTHY = Gauge("router_poller_healthy", "1 if at least one pod is polled")
POD_COUNT = Gauge("router_pod_count", "Number of discovered vLLM pods")


# ─────────────────────────── FastAPI App ──────────────────────

app = FastAPI(title="Adaptive Inference Router v2")


@app.on_event("startup")
async def startup():
    asyncio.create_task(_discover_endpoints())
    asyncio.create_task(_poll_loop())
    log.info("Router v2 started — endpoint watcher + per-pod poller launched")


@app.get("/health")
async def health():
    healthy_count = sum(1 for p in pod_registry.values() if p.poll_healthy)
    return {
        "status": "ok" if healthy_count > 0 else "degraded",
        "pods_total": len(pod_registry),
        "pods_healthy": healthy_count,
    }


@app.get("/status")
async def status():
    """Detailed status of all pods and global tier."""
    pods_status = {}
    for ip, pod in pod_registry.items():
        pods_status[ip] = {
            "tier": pod.tier(),
            "queue_depth": pod.num_requests_waiting,
            "running": pod.num_requests_running,
            "kv_cache_pct": round(pod.gpu_cache_usage_perc, 4),
            "time_per_token_s": round(pod.time_per_output_token_seconds, 6),
            "load_score": round(pod.load_score, 2),
            "healthy": pod.poll_healthy,
            "stale": pod.is_stale,
            "requests_served": pod.requests_served,
            "metrics_age_s": round(time.time() - pod.last_poll_ts, 1),
        }

    return {
        "global_tier": classify_global_tier(),
        "pod_count": len(pod_registry),
        "pods": pods_status,
        "thresholds": {
            "green_queue_max": GREEN_QUEUE_MAX,
            "green_cache_max": GREEN_CACHE_MAX,
            "red_queue_min": RED_QUEUE_MIN,
            "red_cache_min": RED_CACHE_MIN,
            "red_tpt_min_ms": RED_TPT_MIN * 1000,
        },
    }


@app.get("/metrics")
async def metrics_endpoint():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/v1/chat/completions")
async def proxy_chat_completions(request: Request):
    """
    Pod-aware proxy. Picks the least-loaded pod, classifies tier, forwards.
    """
    pod = pick_best_pod()

    if pod is None:
        REQUESTS_TOTAL.labels(tier="red").inc()
        REQUESTS_SHED.inc()
        return JSONResponse(
            status_code=503,
            content={"error": "No backends available", "tier": "red", "retry_after_seconds": 5},
            headers={"Retry-After": "5"},
        )

    tier = pod.tier()
    REQUESTS_TOTAL.labels(tier=tier).inc()

    # RED — shed
    if tier == "red" and classify_global_tier() == "red":
        REQUESTS_SHED.inc()
        log.info(f"RED — shedding (pod={pod.ip}, queue={pod.num_requests_waiting}, "
                 f"cache={pod.gpu_cache_usage_perc:.2f})")
        return JSONResponse(
            status_code=503,
            content={
                "error": "System busy — all backends overloaded",
                "tier": "red",
                "retry_after_seconds": 5,
                "pod": pod.ip,
                "queue_depth": pod.num_requests_waiting,
                "cache_pct": round(pod.gpu_cache_usage_perc, 2),
            },
            headers={"Retry-After": "5"},
        )

    # GREEN or YELLOW — forward to specific pod
    body = await request.json()

    if tier == "yellow":
        REQUESTS_DEGRADED.inc()
        original_tokens = body.get("max_tokens", GREEN_MAX_TOKENS)
        body["max_tokens"] = min(original_tokens, YELLOW_MAX_TOKENS)
        log.info(f"YELLOW — degrading to {body['max_tokens']} tokens (pod={pod.ip})")

    start = time.monotonic()

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{pod.url}/v1/chat/completions",
                json=body,
                headers={"Content-Type": "application/json"},
            )
        elapsed = time.monotonic() - start
        REQUEST_LATENCY.labels(tier=tier).observe(elapsed)

        data = resp.json()

        # Track per-pod stats
        pod.requests_served += 1
        POD_SERVED.labels(pod=pod.ip).inc()
        total_tokens = data.get("usage", {}).get("total_tokens", 0)
        POD_TOKENS.labels(pod=pod.ip).inc(total_tokens)

        # Inject routing metadata
        data["_routing"] = {
            "tier": tier,
            "pod": pod.ip,
            "max_tokens_used": body.get("max_tokens", GREEN_MAX_TOKENS),
            "backend": pod.url,
            "latency_ms": round(elapsed * 1000, 1),
            "queue_depth_at_route": pod.num_requests_waiting,
            "cache_pct_at_route": round(pod.gpu_cache_usage_perc, 2),
            "load_score": round(pod.load_score, 2),
        }

        return JSONResponse(
            status_code=resp.status_code,
            content=data,
            headers={
                "X-Router-Tier": tier,
                "X-Router-Pod": pod.ip,
                "X-Router-Queue": str(int(pod.num_requests_waiting)),
            },
        )

    except httpx.TimeoutException:
        elapsed = time.monotonic() - start
        REQUEST_LATENCY.labels(tier=tier).observe(elapsed)
        return JSONResponse(status_code=504, content={"error": "Backend timeout", "tier": tier, "pod": pod.ip})
    except Exception as e:
        log.error(f"Proxy error (pod={pod.ip}): {e}")
        return JSONResponse(status_code=502, content={"error": f"Backend error: {e}", "tier": tier, "pod": pod.ip})


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("router:app", host="0.0.0.0", port=9090, reload=True)
