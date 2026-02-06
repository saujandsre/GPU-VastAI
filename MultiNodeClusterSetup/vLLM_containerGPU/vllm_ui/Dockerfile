# small base image

FROM python:3.11-slim

WORKDIR /app

#Create non-root user
RUN useradd -m appuser

#Install pythno deps
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

#COPY app code html, css and python code
COPY ui.py ./ui.py
COPY templates ./templates
COPY static ./static

#Ensure files are owned by non-root user
RUN chown -R appuser /app
USER appuser

EXPOSE 8080

CMD ["uvicorn", "ui:app", "--host", "0.0.0.0", "--port", "8080"]

