# app/model_loader.py
from transformers import AutoModelForCausalLM, AutoTokenizer

MODEL_PATH = "/app/models/gpt2"

def load_model():
    print("Loading GPT-2 model from", MODEL_PATH)
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
    model = AutoModelForCausalLM.from_pretrained(MODEL_PATH)
    return tokenizer, model

