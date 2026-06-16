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

# Datadog APM: ddtrace-run instrumenta Flask, gunicorn e clientes Azure SDK.
# Configurar via env: DD_AGENT_HOST, DD_TRACE_AGENT_PORT, DD_SERVICE,
# DD_ENV, DD_VERSION, DD_LOGS_INJECTION=true, DD_TRACE_ENABLED=true.
ENV DD_SERVICE=volunteer-service \
    DD_TRACE_ENABLED=true \
    DD_LOGS_INJECTION=true

CMD ["ddtrace-run", "gunicorn", "--bind", "0.0.0.0:8083", "--workers", "2", "--threads", "2", "app:app"]
