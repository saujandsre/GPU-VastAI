# ~/GPU-VastAI/BareMetalGPU/run_model_fp32.py

import os
import time
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def load_model(model_name_or_path=None):
    model_name_or_path = model_name_or_path or os.getenv("MODEL_PATH", "gpt2")
    trust_remote = os.getenv("TRUST_REMOTE_CODE", "0") in ("1", "true", "True")

    print(f"Loading model from: {model_name_or_path}")

    start = time.time()
    tokenizer = AutoTokenizer.from_pretrained(model_name_or_path, trust_remote_code=trust_remote)
    model = AutoModelForCausalLM.from_pretrained(
        model_name_or_path,
        low_cpu_mem_usage=True,
        trust_remote_code=trust_remote,
        # No dtype specified → FP32 by default
    )
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)
    load_time = time.time() - start

    print(f"Model loaded on {device.upper()} in {load_time:.2f} seconds")
    if device == "cuda":
        torch.cuda.synchronize()
        print(f"GPU memory allocated: {torch.cuda.memory_allocated()/1e9:.2f} GB")
        print(f"GPU memory reserved : {torch.cuda.memory_reserved()/1e9:.2f} GB")
    return tokenizer, model, device

def generate_text(tokenizer, model, device, prompt, max_new_tokens=200):
    inputs = tokenizer(prompt, return_tensors="pt").to(device)
    print(f"\nRunning inference (max_new_tokens={max_new_tokens})...")
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
    print(f"Inference time: {elapsed:.2f}s\n")
    print("Output:")
    print(text_out)

if __name__ == "__main__":
    os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
    model_name = os.getenv("MODEL_PATH", "gpt2")
    max_new = int(os.getenv("MAX_NEW_TOKENS", "200"))

    prompt = input("Enter your prompt: ")
    tokenizer, model, device = load_model(model_name)
    generate_text(tokenizer, model, device, prompt, max_new_tokens=max_new)

