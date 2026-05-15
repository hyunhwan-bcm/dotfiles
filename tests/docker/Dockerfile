FROM debian:bookworm-slim

ARG TARGETARCH

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git stow xz-utils \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -s /bin/sh tester

RUN case "$TARGETARCH" in \
    amd64) nvim_arch=x86_64 ;; \
    arm64) nvim_arch=arm64 ;; \
    *) printf 'Unsupported Docker architecture: %s\n' "$TARGETARCH" >&2; exit 1 ;; \
  esac \
  && curl -fsSL "https://github.com/neovim/neovim/releases/download/stable/nvim-linux-${nvim_arch}.tar.gz" -o /tmp/nvim.tar.gz \
  && tar -C /opt -xzf /tmp/nvim.tar.gz \
  && ln -s "/opt/nvim-linux-${nvim_arch}/bin/nvim" /usr/local/bin/nvim \
  && rm /tmp/nvim.tar.gz

# Install Rust (cargo) via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Set default toolchain
RUN . /root/.cargo/env && rustup default stable

# Install Node.js via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && apt-get install -y nodejs

# Copy cargo binaries to /usr/local/bin for all users
RUN cp /root/.cargo/bin/cargo /usr/local/bin/ && cp /root/.cargo/bin/rustc /usr/local/bin/ && cp /root/.cargo/bin/rustup /usr/local/bin/

# Copy rustup configuration to tester user's home
RUN mkdir -p /home/tester/.rustup && cp -r /root/.rustup/* /home/tester/.rustup/ && chown -R tester:tester /home/tester/.rustup

USER tester
WORKDIR /workspace

CMD ["sh", "/workspace/tests/docker/startup_smoke.sh"]
