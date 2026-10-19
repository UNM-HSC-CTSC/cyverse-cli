FROM ubuntu:24.04

LABEL org.label-schema.name="CyVerse Batch Shell" \
    org.label-schema.description="Non-interactive CloudShell: runs a user init.sh then run.sh as a DE batch app" \
    org.label-schema.vcs-url="https://github.com/UNM-HSC-CTSC/cyverse-cli" \
    org.label-schema.schema-version="1.0.0"

ARG MINIFORGE_VERSION=26.7.2-0

# Runs as root on purpose: DE batch steps ignore the Tool's UID setting and get
# no securityContext, and the /de-app-work volume is created root-owned without
# an fsGroup, so a non-root user could not write its outputs. Root also lets a
# user's init.sh apt-get install without sudo.
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=America/Denver \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PATH=/opt/conda/bin:$PATH

# The apt lists are removed to keep the image small, so init.sh must run
# `apt-get update` before installing anything.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bzip2 unzip zip xz-utils \
    build-essential tzdata less vim-tiny && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Miniforge: conda + mamba, conda-forge as the default channel.
RUN curl -fsSL "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh" -o /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh && \
    /opt/conda/bin/conda clean -afy

COPY batch-runner /usr/local/bin/batch-runner
RUN chmod 755 /usr/local/bin/batch-runner

# Matches the DE's batch working directory, for local testing. The DE sets the
# working directory itself and replaces this ENTRYPOINT with its own script, so
# the Tool's Entrypoint field must also be set to batch-runner.
WORKDIR /de-app-work
ENTRYPOINT ["batch-runner"]
