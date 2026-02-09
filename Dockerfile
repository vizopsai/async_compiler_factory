FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies: build tools, cross-compilers, QEMU for testing
RUN apt-get update && apt-get install -y \
    curl wget git build-essential pkg-config ca-certificates gnupg \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
    gcc-i686-linux-gnu g++-i686-linux-gnu \
    qemu-user-static \
    bc sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x (Claude Code requires Node >= 18)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Rust (stable)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create non-root user (Claude Code refuses --dangerously-skip-permissions as root)
RUN useradd -m -s /bin/bash agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Rust for the agent user too
USER agent
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/home/agent/.cargo/bin:${PATH}"

# Git identity
RUN git config --global user.name "Claude Opus 4.6" \
    && git config --global user.email "noreply@anthropic.com" \
    && git config --global pull.rebase true \
    && git config --global rebase.autoStash true

USER root

# Copy test suites into the image
COPY tests/ /test-suites/

# Set up workspace owned by agent
RUN mkdir -p /workspace && chown agent:agent /workspace

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER agent
WORKDIR /workspace

ENTRYPOINT ["/entrypoint.sh"]
