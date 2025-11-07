# ~/GPU-VastAI/BareMetalGPU/run_model.py

import os
import time
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def load_model(model_name_or_path=None):
    """
    Load a transformer model and tokenizer on GPU if available.
    """
    model_name_or_path = model_name_or_path or os.getenv("MODEL_PATH", "gpt2")
    print(f"🔍 Loading model from: {model_name_or_path}")

    start = time.time()
    tokenizer = AutoTokenizer.from_pretrained(model_name_or_path)
    model = AutoModelForCausalLM.from_pretrained(model_name_or_path)
    load_time = time.time() - start

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)
    print(f"✅ Model loaded on {device.upper()} in {load_time:.2f} seconds")
    if device == "cuda":
        print(f"💽 GPU memory allocated: {torch.cuda.memory_allocated() / 1e9:.2f} GB")

    return tokenizer, model, device


def generate_text(tokenizer, model, device, prompt, max_new_tokens=50):
    """
    Run generation and print results with timing.
    """
    inputs = tokenizer(prompt, return_tensors="pt").to(device)

    print(f"\n⚙️ Running inference (max_new_tokens={max_new_tokens})...")
    start = time.time()
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=max_new_tokens,
            do_sample=True,
            top_k=50,
            top_p=0.95,
        )
    elapsed = time.time() - start

    text_out = tokenizer.decode(outputs[0], skip_special_tokens=True)
    print(f"🕒 Inference time: {elapsed:.2f}s\n")
    print("🧠 Output:")
    print(text_out)


if __name__ == "__main__":
    # Choose your model
    model_name = os.getenv("MODEL_PATH", "gpt2")
    prompt = input("💬 Enter your prompt: ")

    tokenizer, model, device = load_model(model_name)
    generate_text(tokenizer, model, device, prompt)

