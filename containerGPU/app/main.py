from fastapi import FastAPI
from pydantic import BaseModel
import torch
from model_loader import load_model

tokenizer, model = load_model()
app = FastAPI()

class Prompt(BaseModel):
    text: str
    max_tokens: int = 50

@app.post("/predict")
def predict(prompt: Prompt):
    device = next(iter(model.parameters())).device
    inputs = tokenizer(prompt.text, return_tensors="pt").to(device)
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=prompt.max_tokens,
            do_sample=True,
            top_k=50,
            top_p=0.95
        )
    return {"output": tokenizer.decode(outputs[0], skip_special_tokens=True)}

