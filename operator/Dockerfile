# TODO: Build shell-operator
FROM ghcr.io/flant/shell-operator:v1.6.2 AS shell-operator-base

FROM node:24-slim AS builder

# Build arguments for OCI labels
ARG VERSION
ARG BUILD_DATE
ARG VCS_REF

ENV KUBECTL_VERSION=v1.33.0 \
    AWS_CLI_VERSION=2.27.50

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -L "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

RUN curl -sfL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip ./aws

RUN npm install -g aws-cdk

FROM node:24-slim

# Build arguments for OCI labels (redeclared for final stage)
ARG VERSION
ARG BUILD_DATE
ARG VCS_REF

# OCI Labels - https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL org.opencontainers.image.title="AWS CDK Operator" \
      org.opencontainers.image.description="A Kubernetes operator that enables declarative management of AWS CDK (Cloud Development Kit) stacks using Custom Resource Definitions (CRDs). Deploy, update, and manage your AWS infrastructure directly from Kubernetes manifests with full lifecycle support." \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/awscdk-operator/cdk-ts-operator" \
      org.opencontainers.image.url="https://github.com/awscdk-operator/cdk-ts-operator" \
      org.opencontainers.image.documentation="https://awscdk.dev" \
      org.opencontainers.image.licenses="Apache-2.0" \      
      org.opencontainers.image.authors="Ilia Belov <belov38@gmail.com>" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    git \
    curl \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=shell-operator-base /shell-operator /usr/local/bin/shell-operator
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/aws-cli/ /usr/local/aws-cli/

COPY --from=builder /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

RUN ln -s /usr/local/lib/node_modules/aws-cdk/bin/cdk /usr/local/bin/cdk
RUN ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws

COPY hooks/ /hooks/
RUN chmod +x /hooks/*.sh

# Metrics https://flant.github.io/shell-operator/metrics/METRICS_FROM_HOOKS.html
ENV METRICS_PATH="/metrics.txt"

WORKDIR /
ENTRYPOINT ["/usr/local/bin/shell-operator"]
