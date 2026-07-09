# Headless Godot dedicated server for the zombie game (Railway), fronted by the
# Go "director" so one container can run several concurrent matches.
#
# The director listens on Railway's $PORT and, per incoming client, routes the
# WebSocket to a pooled single-match Godot child (spawned with --port/--room).
# See docs/superpowers/specs/2026-07-09-concurrent-games-director-design.md.

# ---- Stage 1: build the Go director -----------------------------------------
FROM golang:1.26-bookworm AS director-build
WORKDIR /src
# The director module is self-contained (stdlib only), so the source is all we
# need — no module download step.
COPY server/director/ ./
RUN CGO_ENABLED=0 go build -trimpath -o /out/director ./cmd/director

# ---- Stage 2: headless Godot + director -------------------------------------
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
COPY --from=director-build /out/director /usr/local/bin/director

# Pre-import resources so the first child boots fast (re-imports at runtime if needed).
RUN godot --headless --import || true

# The director reads $PORT (Railway sets it) and spawns Godot children on
# internal ports 8911+. Tunables: MAX_GAMES (default 5), INTERNAL_BASE_PORT,
# IDLE_SPAWN_TIMEOUT_SEC. GODOT_BIN defaults to "godot", PROJECT_PATH to "/app".
CMD ["director"]
