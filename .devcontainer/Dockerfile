FROM mcr.microsoft.com/devcontainers/python:3.11-bookworm

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl wget git jq ca-certificates dnsutils iputils-ping net-tools \
      xvfb fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# Python deps (browser automation + helpers)
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
 && python -m playwright install-deps chromium
