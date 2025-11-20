import os
import time

from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import httpx

# ---------- Config ----------
VLLM_URL = os.environ.get("VLLM_URL", "http://127.0.0.1:8000")
MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen/Qwen2.5-3B-Instruct")

print(">>> VLLM_URL:", VLLM_URL)
print(">>> MODEL_NAME:", MODEL_NAME)

# ---------- App setup ----------
app = FastAPI()

# Static files and templates (relative to this file's directory)
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")


# ---------- Routes ----------
@app.get("/", response_class=HTMLResponse)
async def get_ui(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.post("/api/generate")
async def generate(prompt: str = Form(...)):
    """Proxy prompt to vLLM and return text + stats."""
    payload = {
        "model": MODEL_NAME,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 512,
        "temperature": 0.2,
    }

    start = time.monotonic()
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            r = await client.post(f"{VLLM_URL}/v1/chat/completions", json=payload)
        elapsed_ms = (time.monotonic() - start) * 1000.0

        print(">>> vLLM status:", r.status_code)
        print(">>> vLLM body (truncated):", r.text[:400])

        r.raise_for_status()
        data = r.json()
        text = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
    except Exception as e:
        import traceback

        traceback.print_exc()
        return JSONResponse(
            status_code=500,
            content={"error": f"Failed to contact vLLM: {e}"},
        )

    return {
        "response": text.strip(),
        "latency_ms": round(elapsed_ms, 1),
        "usage": usage,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("ui:app", host="0.0.0.0", port=8080, reload=True)

