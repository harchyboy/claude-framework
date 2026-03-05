# Dockerfile — Isolated environment for Claude Code agents
# Used by Ralph loop with --docker flag for safe autonomous development
#
# Build: docker build -t hartz-agent docker/
# Run:   See docker-compose.yml or scripts/ralph.sh --docker

FROM node:22-slim

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    bash \
    curl \
    jq \
    ca-certificates \
    openssh-client \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Install Playwright for verification (chromium only, headless)
RUN npx playwright install --with-deps chromium 2>/dev/null || true

# Create non-root user for agent
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /home/agent

# Git config for commits
RUN git config --global user.name "Hartz Agent" && \
    git config --global user.email "agent@hartz.land" && \
    git config --global init.defaultBranch main

# Create framework directories
RUN mkdir -p /home/agent/.hartz-claude-framework/review-queue \
             /home/agent/.hartz-claude-framework/logs

# Entry point — run Claude in headless mode
# Override CMD with your prompt via docker-compose or docker run
ENTRYPOINT ["claude"]
CMD ["--help"]
