FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git jq ca-certificates unzip zip wget apt-transport-https \
    software-properties-common lsb-release gnupg openssl \
    && rm -rf /var/lib/apt/lists/*

# Install deployment prerequisites at image-build time, not in unprivileged jobs.
# Review and pin the installer/package sources for a production image pipeline.
RUN curl --fail --show-error --silent --location \
    https://aka.ms/InstallAzureCLIDeb -o /opt/install-azure-cli.sh \
    && bash /opt/install-azure-cli.sh \
    && rm /opt/install-azure-cli.sh \
    && az version >/dev/null \
    && zip -v >/dev/null

RUN useradd -m runner
WORKDIR /home/runner/actions-runner

# Supply a supported version and its official Linux x64 SHA-256 release checksum.
ARG RUNNER_VERSION
ARG RUNNER_SHA256
RUN test -n "$RUNNER_VERSION" && test -n "$RUNNER_SHA256" \
    && curl --fail --show-error --silent --location -o actions-runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && printf '%s  actions-runner.tar.gz\n' "$RUNNER_SHA256" | sha256sum --check --strict \
    && tar xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz

RUN ./bin/installdependencies.sh
COPY start.sh .
RUN chmod 0755 start.sh && chown -R runner:runner /home/runner

USER runner
ENTRYPOINT ["./start.sh"]
