FROM python:3.11-slim

WORKDIR /app

RUN useradd -m appuser

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY router.py .

RUN chown -R appuser /app
USER appuser


EXPOSE 9090

CMD ["uvicorn", "router:app", "--host", "0.0.0.0", "--port", "9090"]

