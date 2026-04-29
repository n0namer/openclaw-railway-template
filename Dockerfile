FROM node:24-bookworm

ARG OPENCLAW_VERSION

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

RUN set -eux; \
  OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.4.23}"; \
  npm install -g "openclaw@${OPENCLAW_VERSION}" clawhub@latest; \
  mkdir -p /opt/clawdbot; \
  printf '%s\n' "${OPENCLAW_VERSION}" > /opt/clawdbot/openclaw-version

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY client-pack ./client-pack
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

RUN useradd -m -s /bin/bash openclaw \
  && chown -R openclaw:openclaw /app /opt/clawdbot \
  && mkdir -p /home/linuxbrew/.linuxbrew \
  && chown -R openclaw:openclaw /home/linuxbrew

USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV HOME=/data
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV OPENCLAW_CONFIG_PATH=/data/.openclaw/openclaw.json
ENV OPENCLAW_SKILLS_DIR=/data/.openclaw/skills
ENV OPENCLAW_PLUGINS_DIR=/data/.openclaw/extensions
ENV CLAWDBOT_STATE_DIR=/data/.clawdbot
ENV CLAWDBOT_WORKSPACE_DIR=/data/workspace
ENV CLAWDBOT_SKILLS_DIR=/data/.clawdbot/skills
ENV CLAWDBOT_PLUGINS_DIR=/data/.openclaw/extensions
ENV CLAWDBOT_CLIENT_PACK=default
ENV CLAWDBOT_AUTO_CONFIG=auto
ENV CLAWDBOT_BOOTSTRAP_SKILLS=true
ENV CLAWDBOT_BOOTSTRAP_PLUGINS=true
ENV CLAWDBOT_SKILLS_SYNC_ENABLED=true
ENV CLAWDBOT_SKILLS_SYNC_INTERVAL_SECONDS=1800
ENV CLAWDBOT_SKILLS_UPDATE_ALL=false
ENV CLAWDBOT_SKILLS_ALLOWLIST_PATH=/data/.clawdbot/skills.allowlist
ENV CLAWDBOT_ENABLE_VK=false
ENV INTERNAL_GATEWAY_BIND=lan
ENV INTERNAL_GATEWAY_PORT=18789
ENV SELF_HEAL_MAX_ATTEMPTS=3
ENV TELEGRAM_ENABLED=false
ENV NPM_CONFIG_CACHE=/data/npm-cache
ENV NPM_CONFIG_PREFIX=/data/npm
ENV PNPM_HOME=/data/pnpm
ENV PNPM_STORE_DIR=/data/pnpm-store

VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root
ENTRYPOINT ["./entrypoint.sh"]
