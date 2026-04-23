FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends stow \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -m -s /bin/sh tester

USER tester
WORKDIR /workspace

CMD ["sh", "/workspace/tests/docker/startup_smoke.sh"]
