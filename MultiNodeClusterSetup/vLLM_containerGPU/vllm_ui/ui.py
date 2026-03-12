"""
vLLM Chat UI v2 — Shows which pod served the request.
"""

import os
import time

from fastapi import FastAPI, Request, Form, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import httpx

from prometheus_client import (
    Counter,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

ROUTER_URL = os.environ.get("VLLM_URL", "http://inference-router:9090")
MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-3B-Instruct")

print(f">>> ROUTER_URL: {ROUTER_URL}")
print(f">>> MODEL_ID: {MODEL_ID}")

REQUEST_COUNT = Counter("ui_http_requests_total", "Total HTTP requests", ["status"])
REQUEST_LATENCY = Histogram("ui_http_request_latency_seconds", "Latency", ["path"])
TOKENS_IN = Counter("ui_tokens_in_total", "Prompt tokens")
TOKENS_OUT = Counter("ui_tokens_out_total", "Completion tokens")

app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    REQUEST_LATENCY.labels(request.url.path).observe(time.time() - start)
    REQUEST_COUNT.labels(status=str(response.status_code)).inc()
    return response


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/", response_class=HTMLResponse)
async def get_ui(request: Request):
    return templates.TemplateResponse("index.html", {"request": request, "model_id": MODEL_ID})


@app.post("/api/generate")
async def generate(prompt: str = Form(...)):
    payload = {
        "model": MODEL_ID,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
        "temperature": 0.2,
    }

    start = time.monotonic()

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            r = await client.post(f"{ROUTER_URL}/v1/chat/completions", json=payload)

        elapsed_ms = (time.monotonic() - start) * 1000.0
        data = r.json()

        if r.status_code == 503:
            return JSONResponse(
                status_code=503,
                content={
                    "error": data.get("error", "System busy"),
                    "tier": data.get("tier", "red"),
                    "pod": data.get("pod", "unknown"),
                    "retry_after_seconds": data.get("retry_after_seconds", 5),
                    "latency_ms": round(elapsed_ms, 1),
                },
            )

        r.raise_for_status()

        text = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        routing = data.get("_routing", {})

        TOKENS_IN.inc(usage.get("prompt_tokens", 0))
        TOKENS_OUT.inc(usage.get("completion_tokens", 0))

    except httpx.TimeoutException:
        return JSONResponse(status_code=504, content={"error": "Backend timeout"})
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": f"Failed: {e}"})

    return {
        "response": text.strip(),
        "latency_ms": round(elapsed_ms, 1),
        "usage": usage,
        "routing": {
            "tier": routing.get("tier", "unknown"),
            "pod": routing.get("pod", "unknown"),
            "backend": routing.get("backend", "unknown"),
            "max_tokens_used": routing.get("max_tokens_used", "n/a"),
            "queue_depth": routing.get("queue_depth_at_route", "n/a"),
            "cache_pct": routing.get("cache_pct_at_route", "n/a"),
            "load_score": routing.get("load_score", "n/a"),
        },
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("ui:app", host="0.0.0.0", port=8080, reload=True)
