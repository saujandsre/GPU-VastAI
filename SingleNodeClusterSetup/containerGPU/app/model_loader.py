import os
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

def load_model():
    model_id = os.getenv("MODEL_PATH")
    if not model_id:
        raise RuntimeError("MODEL_PATH not set (HF repo id like 'Qwen/Qwen2.5-3B-Instruct' or a local path).")

    print(f"🔍 Loading model from: {model_id}")

    tokenizer = AutoTokenizer.from_pretrained(model_id, use_fast=True, trust_remote_code=True)
    # Keep it simple: fp16 to save VRAM, and move the whole thing to CUDA if present.
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        trust_remote_code=True,
        torch_dtype=torch.float16 if torch.cuda.is_available() else None,
    )

    if torch.cuda.is_available():
        model = model.to("cuda")
        print("✅ Model on GPU")
    else:
        print("⚠️ CUDA not available, running on CPU")

    return tokenizer, model

