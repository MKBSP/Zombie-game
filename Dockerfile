# Headless Godot dedicated server for the zombie game (Railway).
# Runs the project with --server; the server reads Railway's $PORT.

FROM debian:bookworm-slim

# MUST match the Godot version your project uses (see the editor title bar).
ARG GODOT_VERSION=4.6.3-stable

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates unzip wget \
    && rm -rf /var/lib/apt/lists/*

# Download the Linux Godot binary (the standard editor binary runs headless too).
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY . /app

# Pre-import resources so the first boot is fast (re-imports at runtime if needed).
RUN godot --headless --import || true

# Railway sets $PORT; scripts/network.gd reads it. WebSocket binds 0.0.0.0 by default.
CMD ["godot", "--headless", "--path", ".", "--", "--server"]
