# Borderless public relay. Built on the box from the deploy bundle (context = bundle root).
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN pip install --no-cache-dir websockets==16.0 \
    && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin relay \
    && mkdir /data \
    && chown relay /data \
    && chmod 700 /data

WORKDIR /app
COPY budget_relay ./budget_relay
COPY conversation_relay ./conversation_relay
COPY voice_relay ./voice_relay

USER relay
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=4)"]
CMD ["python", "-m", "conversation_relay.hosted", "--bind", "0.0.0.0", "--port", "8080", "--behind-proxy", \
     "--data-dir", "/data", "--secrets-dir", "/run/borderless", "--control-dir", "/control"]
