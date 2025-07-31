FROM ghcr.io/open-webui/mcpo:main

# Install Docker CLI
RUN apt-get update && apt-get install -y docker.io
