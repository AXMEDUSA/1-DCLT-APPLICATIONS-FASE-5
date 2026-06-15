FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.11-slim

RUN useradd --no-create-home --shell /bin/false appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY app.py .

USER appuser

EXPOSE 8083

CMD ["gunicorn", "--bind", "0.0.0.0:8083", "--workers", "2", "--threads", "2", "app:app"]
