# Lightweight Python image
FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy router code
COPY router.py .

EXPOSE 8080

CMD ["uvicorn", "router:app", "--host", "0.0.0.0", "--port", "8080"]
