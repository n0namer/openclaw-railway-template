FROM node:24-bookworm

ARG OPENCLAW_VERSION=2026.4.26

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 \
    build-essential \
    zip \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@${OPENCLAW_VERSION} clawhub@latest

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY seed ./seed
COPY --chmod=755 scripts ./scripts
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app \
  && mkdir -p /data && chown openclaw:openclaw /data \
  && mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json
ENV OPENCLAW_SKILLS_DIR=/data/.openclaw/skills
ENV OPENCLAW_PLUGINS_DIR=/data/openclaw-plugins
ENV CLAWDBOT_STATE_DIR=/data/.clawdbot
ENV CLAWDBOT_WORKSPACE_DIR=/data/workspace
ENV CLAWDBOT_SKILLS_DIR=/data/.clawdbot/skills
ENV CLAWDBOT_PLUGINS_DIR=/data/clawdbot-plugins
ENV CLAWDBOT_AUTO_CONFIG=auto
ENV CLAWDBOT_INSTALL_VK_PLUGIN=true
ENV CLAWDBOT_VK_PLUGIN_REPO=https://github.com/fibbersha-hub/openclaw-vk-plugin.git
ENV INTERNAL_GATEWAY_BIND=lan
ENV SELF_HEAL_MAX_ATTEMPTS=3

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["./entrypoint.sh"]
