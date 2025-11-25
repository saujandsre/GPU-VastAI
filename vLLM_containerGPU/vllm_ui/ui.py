import os
import time

from fastapi import FastAPI, Request, Form, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import httpx

# --- Prometheus ---
from prometheus_client import (
    Counter,
    Histogram,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

# ---------- Config ----------
VLLM_URL = os.environ.get("VLLM_URL", "http://127.0.0.1:8000")
MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-3B-Instruct")

print(">>> VLLM_URL:", VLLM_URL)
print(">>> MODEL_ID:", MODEL_ID)

# ---------- Prometheus metrics ----------
# Track request count by HTTP status
REQUEST_COUNT = Counter(
    "ui_http_requests_total",
    "Total HTTP requests",
    ["status"],
)

# Track latency by path (Histogram is better for percentiles)
REQUEST_LATENCY = Histogram(
    "ui_http_request_latency_seconds",
    "Latency of HTTP requests",
    ["path"],
)

# Count tokens in/out from vLLM usage
TOKENS_IN = Counter(
    "ui_tokens_in_total",
    "Total prompt tokens sent to model",
)

TOKENS_OUT = Counter(
    "ui_tokens_out_total",
    "Total completion tokens generated",
)

# ---------- App setup ----------
app = FastAPI()
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")


# ---------- Middleware for global metrics ----------
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """
    Middleware runs on *every* request.
    Measures latency + counts responses.

    Keeping this general means you don’t need to instrument every route manually.
    """
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start

    REQUEST_LATENCY.labels(request.url.path).observe(duration)
    REQUEST_COUNT.labels(status=str(response.status_code)).inc()

    return response


# ---------- Metrics endpoint ----------
@app.get("/metrics")
def metrics():
    """
    Prometheus scrapes this endpoint.
    No auth here — in real production you'd restrict it using mTLS or network policies.
    """
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


# ---------- UI ----------
@app.get("/", response_class=HTMLResponse)
async def get_ui(request: Request):
    return templates.TemplateResponse(
        "index.html",
        {"request": request, "model_id": MODEL_ID},
    )


# ---------- LLM generate ----------
@app.post("/api/generate")
async def generate(prompt: str = Form(...)):
    """
    Sends prompt → vLLM backend → returns text + usage.
    Also updates token metrics.
    """
    payload = {
        "model": MODEL_ID,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
        "temperature": 0.2,
    }

    start = time.monotonic()

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            r = await client.post(f"{VLLM_URL}/v1/chat/completions", json=payload)

        elapsed_ms = (time.monotonic() - start) * 1000.0

        r.raise_for_status()
        data = r.json()

        text = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})

        # --- Token metrics ---
        TOKENS_IN.inc(usage.get("prompt_tokens", 0))
        TOKENS_OUT.inc(usage.get("completion_tokens", 0))

    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": f"Failed to contact vLLM: {e}"},
        )

    return {
        "response": text.strip(),
        "latency_ms": round(elapsed_ms, 1),
        "usage": usage,
    }


# ---------- Local Dev ----------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("ui:app", host="0.0.0.0", port=8080, reload=True)

