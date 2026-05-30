FROM jenkins/jenkins:lts

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

RUN curl -fsSL https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN jenkins-plugin-cli \
    --plugin-file /usr/share/jenkins/ref/plugins.txt

ENV CASC_JENKINS_CONFIG=${CASC_JENKINS_CONFIG}

ENTRYPOINT ["/usr/bin/tini", "--"]

USER jenkins