# Pinned to a digest for supply-chain integrity. Resolved from jenkins/jenkins:lts
# on 2026-06-03. Update both the tag comment and digest together when bumping.
FROM jenkins/jenkins:lts@sha256:01c992ffef29dcf41c7164e8c16285c657c2368c4943dda8d68c93fdf54447d5

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    curl \
    unzip \
    git \
    python3 \
    python3-pip \
    jq \
    tini \
    && rm -rf /var/lib/apt/lists/* \
    && if getent group docker >/dev/null 2>&1; then usermod -aG docker jenkins; fi

# Pin kubectl to a specific version and verify its published SHA-256 checksum
# instead of tracking the mutable "stable.txt" pointer.
ENV KUBECTL_VERSION=v1.31.3
ENV KUBECTL_SHA256=981f6b49577068bc174275184d8ee7105d8e54f40733792c519cd85023984c0f
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl && \
    echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - && \
    chmod +x /usr/local/bin/kubectl

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli \
    --plugin-file /usr/share/jenkins/ref/plugins.txt

ENV CASC_JENKINS_CONFIG=${CASC_JENKINS_CONFIG}

ENTRYPOINT ["/usr/bin/tini", "--"]

USER jenkins