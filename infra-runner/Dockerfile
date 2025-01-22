# Source: https://github.com/dotnet/dotnet-docker
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy AS build

ARG TARGETOS
ARG TARGETARCH
ARG TARGETPLATFORM=linux/amd64
ARG RUNNER_VERSION=2.321.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.6.2
ARG DOCKER_VERSION=27.3.1
ARG BUILDX_VERSION=0.18.0
ARG VAULT_VERSION=1.16.2

RUN apt update -y && apt install curl unzip -y

WORKDIR /actions-runner
RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export RUNNER_ARCH=x64 ; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGETOS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

RUN export RUNNER_ARCH=${TARGETARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export DOCKER_ARCH=x86_64 ; fi \
    && if [ "$RUNNER_ARCH" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && curl -fLo docker.tgz https://download.docker.com/${TARGETOS}/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-buildx \
    "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${TARGETARCH}" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

ADD https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip vault_${VAULT_VERSION}_linux_amd64.zip
RUN unzip vault_${VAULT_VERSION}_linux_amd64.zip && \
    mv vault /usr/bin && \
    rm vault_${VAULT_VERSION}_linux_amd64.zip

FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=ubuntu22

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    ca-certificates \

    ssh \
    coreutils \
    sudo \
    lsb-release \
    build-essential \
    make \
    ack \
    wget unzip git jq curl gettext-base \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod 755 kubectl && \
    mv kubectl /usr/local/bin && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    sudo ./aws/install && \
    rm -f awscliv2.zip  \
    && curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION=2.2.3 bash \
    && curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash -s 5.3.0 \
    && sudo mv kustomize /usr/local/bin \
    && curl -s -L https://github.com/a8m/envsubst/releases/download/v1.4.2/envsubst-Linux-x86_64 -o envsubst \
    && chmod +x envsubst \
    && sudo mv envsubst /usr/local/bin/envsubst-a8m \
    && pip3 install jwt \
    && curl -s -L "https://go.dev/dl/go1.23.2.linux-amd64.tar.gz" -o go1.23.2.linux-amd64.tar.gz \
    && rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz

ARG TARGETARCH
ARG INFRA_EXEC_VERSION
ARG INFRA_EXEC_URL_PREFIX
ARG INFRA_EXEC_NAME

ADD ${INFRA_EXEC_URL_PREFIX}${INFRA_EXEC_VERSION}/${INFRA_EXEC_NAME}_${INFRA_EXEC_VERSION}_linux_${TARGETARCH}.zip ${INFRA_EXEC_NAME}_${INFRA_EXEC_VERSION}_linux_${TARGETARCH}.zip
RUN unzip -q ${INFRA_EXEC_NAME}_${INFRA_EXEC_VERSION}_linux_${TARGETARCH}.zip -d /usr/local/bin/ && \
    rm ${INFRA_EXEC_NAME}_${INFRA_EXEC_VERSION}_linux_${TARGETARCH}.zip && \
    chmod +x /usr/local/bin/terraform

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

WORKDIR /home/runner

COPY --chown=runner:docker --from=build /actions-runner .
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx
COPY --from=build /usr/bin/vault /usr/bin/vault

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker
RUN wget https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq
ADD bin/infra.sh bin
ADD bin/trap.sh bin
ADD bin/app-jwt.py bin
ADD providers.tf .
# ADD exec/infractl bin
USER runner
RUN mkdir -p /home/runner/.terraform.d
RUN export TF_PLUGIN_CACHE_DIR=/home/runner/.terraform.d/plugin-cache && terraform init
