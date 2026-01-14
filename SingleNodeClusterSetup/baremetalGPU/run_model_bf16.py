# ~/GPU-VastAI/BareMetalGPU/run_model.py

import os
import time
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def pick_half_precision_dtype():
    """Prefer bf16 if CUDA supports it; otherwise use fp16."""
    if torch.cuda.is_available() and torch.cuda.is_bf16_supported():
        return torch.bfloat16
    return torch.float16

def load_model(model_name_or_path=None):
    """
    Load a transformer model and tokenizer; place model on GPU if available.
    Forces half-precision to keep VRAM sane.
    """
    model_name_or_path = model_name_or_path or os.getenv("MODEL_PATH", "gpt2")
    trust_remote = os.getenv("TRUST_REMOTE_CODE", "0") in ("1", "true", "True")

    print(f"🔍 Loading model from: {model_name_or_path}")
    dtype = pick_half_precision_dtype()
    print(f"🧪 Using dtype: {dtype}")

    start = time.time()
    tokenizer = AutoTokenizer.from_pretrained(model_name_or_path, trust_remote_code=trust_remote)
    model = AutoModelForCausalLM.from_pretrained(
        model_name_or_path,
        dtype=dtype,
        low_cpu_mem_usage=True,
        trust_remote_code=trust_remote,
    )
    load_time = time.time() - start

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)

    print(f"✅ Model loaded on {device.upper()} in {load_time:.2f} seconds")
    if device == "cuda":
        torch.cuda.synchronize()
        print(f"💽 GPU memory allocated: {torch.cuda.memory_allocated()/1e9:.2f} GB")
        print(f"💽 GPU memory reserved : {torch.cuda.memory_reserved()/1e9:.2f} GB")

    return tokenizer, model, device

def generate_text(tokenizer, model, device, prompt, max_new_tokens=200):
    """
    Run a single generation and print the result with timing.
    """
    inputs = tokenizer(prompt, return_tensors="pt").to(device)

    print(f"\n⚙️  Running inference (max_new_tokens={max_new_tokens})...")
    start = time.time()
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            do_sample=True,
            top_k=50,
            top_p=0.95,
            use_cache=True,
        )
    elapsed = time.time() - start

    text_out = tokenizer.decode(outputs[0], skip_special_tokens=True)
    print(f"🕒 Inference time: {elapsed:.2f}s\n")
    print("🧠 Output:")
    print(text_out)

if __name__ == "__main__":
    # Env controls
    # MODEL_PATH: e.g. export MODEL_PATH="Qwen/Qwen3-4B-Instruct-2507"
    # MAX_NEW_TOKENS: e.g. export MAX_NEW_TOKENS=120
    model_name = os.getenv("MODEL_PATH", "gpt2")
    max_new = int(os.getenv("MAX_NEW_TOKENS", "200"))

    # (Optional) Reduce allocator fragmentation / allow growth
    os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

    prompt = input("💬 Enter your prompt: ")
    tokenizer, model, device = load_model(model_name)
    generate_text(tokenizer, model, device, prompt, max_new_tokens=max_new)
