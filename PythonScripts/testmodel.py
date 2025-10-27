import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline

# >>> Update this to your local folder if different
MODEL_DIR = "/root/GPU-VastAI/K8s/SingleNodeClusterSetup/models/meta-llama-3B"

# Pick the best dtype for your GPU
if torch.cuda.is_available():
    # bf16 is great on Ada/Hopper; fall back to fp16 if bf16 unsupported
    dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
    device_map = "auto"
else:
    dtype = torch.float32
    device_map = None

print(f"Loading model from: {MODEL_DIR}")
tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR, use_fast=True)
model = AutoModelForCausalLM.from_pretrained(
    MODEL_DIR,
    torch_dtype=dtype,
    device_map=device_map,          # will put layers on GPU(s) automatically
    low_cpu_mem_usage=True
    # You can try faster attention if you have it installed:
    # attn_implementation="flash_attention_2",
)

# Build a chat-style prompt using the model's chat template
messages = [
    {"role": "system", "content": "You are a helpful assistant."},
    {
        "role": "user",
        "content": "In one paragraph, explain VRAM usage for LLMs (weights, activations, KV cache) in simple terms."
    },
]

# Turn messages into a single text prompt following the model's template
prompt = tokenizer.apply_chat_template(
    messages,
    add_generation_prompt=True,
    tokenize=False
)

# Quick pipeline for convenience
pipe = pipeline(
    "text-generation",
    model=model,
    tokenizer=tokenizer,
    torch_dtype=dtype,
    device_map=device_map
)

# Generation settings (tweak to taste)
GEN_KW = dict(
    max_new_tokens=256,
    temperature=0.7,
    top_p=0.9,
    do_sample=True,
    repetition_penalty=1.1,
    eos_token_id=tokenizer.eos_token_id,
)

print("\n=== Model Response ===\n")
out = pipe(prompt, **GEN_KW)[0]["generated_text"]
# The pipeline returns the full prompt + completion; slice off the prompt for clean print
print(out[len(prompt):].strip())

