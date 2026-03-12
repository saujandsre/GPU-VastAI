"""
Model Router — Phase 1b: Redis-backed backend metrics
Reads backend health from Redis. Falls back to ConfigMap file if Redis is down.
Enhanced routing: status → kv_cache → queue_depth → gpu_util
"""
import json
import os
from fastapi import FastAPI
from datetime import datetime

import redis

app = FastAPI(title="Model Router", version="0.2.0")

# --- Config ---
REDIS_HOST = os.getenv("REDIS_HOST", "redis-svc")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
CONFIG_PATH = os.getenv("BACKENDS_CONFIG", "/config/backends.json")

# Redis connection (lazy, reconnects automatically)
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def load_backends() -> dict:
    """
    Try Redis first, fall back to ConfigMap file.
    Redis keys: backend:<name> → JSON string
    """
    backends = {}

    # --- Try Redis ---
    try:
        keys = r.keys("backend:*")
        if keys:
            for key in keys:
                name = key.replace("backend:", "")
                raw = r.get(key)
                if raw:
                    backends[name] = json.loads(raw)
            return backends
    except redis.ConnectionError:
        pass  # Redis down, fall through to ConfigMap

    # --- Fallback: ConfigMap file ---
    try:
        with open(CONFIG_PATH, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


@app.get("/health")
def health():
    # Check Redis connectivity
    try:
        r.ping()
        redis_status = "connected"
    except redis.ConnectionError:
        redis_status = "disconnected"

    return {
        "status": "ok",
        "phase": "1b-redis",
        "redis": redis_status,
        "timestamp": str(datetime.utcnow()),
    }


@app.get("/backends")
def list_backends():
    """Return all backend statuses."""
    return {"backends": load_backends()}


@app.get("/route")
def route_request():
    """
    Pick the best backend using weighted scoring.

    Scoring (lower = better):
      1. Status:    green=0, yellow=50, red=100
      2. KV cache:  usage * 40  (0.0-1.0 scaled to 0-40)
      3. Queue:     depth * 3   (each queued request adds 3)
      4. GPU util:  util * 0.1  (0-100 scaled to 0-10)

    Why this order:
      - Status is the hard gate (red backends are last resort)
      - KV cache filling up = about to reject requests (most urgent)
      - Queue depth = latency for next request
      - GPU util = least important (high util is fine if queue is low)
    """
    backends = load_backends()
    if not backends:
        return {"error": "No backends available"}

    STATUS_WEIGHT = {"green": 0, "yellow": 50, "red": 100}

    scored = []
    for name, metrics in backends.items():
        score = (
            STATUS_WEIGHT.get(metrics.get("status", "red"), 100)
            + metrics.get("kv_cache_usage", 0) * 40
            + metrics.get("queue_depth", 0) * 3
            + metrics.get("gpu_util", 0) * 0.1
        )
        scored.append((name, metrics, round(score, 2)))

    scored.sort(key=lambda x: x[2])

    chosen_name, chosen_data, chosen_score = scored[0]

    return {
        "routed_to": chosen_name,
        "backend_status": chosen_data,
        "score": chosen_score,
        "all_scores": {name: s for name, _, s in scored},
        "reason": "status(0/50/100) + kv_cache*40 + queue*3 + gpu_util*0.1",
    }
