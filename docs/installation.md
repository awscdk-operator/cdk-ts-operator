# Installation

This guide covers different methods to install the AWS CDK Operator in your Kubernetes cluster.

## Prerequisites

Before installing the AWS CDK Operator, ensure you have:

- Kubernetes cluster 1.20+
- `kubectl` configured to access your cluster
- Appropriate RBAC permissions to create CRDs and operators
- Helm 3.x (for Helm installation method)

## Installation Methods

### Method 1: Helm Chart (Recommended)

The recommended way to install the AWS CDK Operator is using the Helm chart.

#### Add the Helm Repository

```bash
# Add the Helm repository (when published)
helm repo add aws-cdk-operator https://awscdk.dev/charts
helm repo update
```

#### Install using Helm CLI

```bash
# Create namespace
kubectl create namespace awscdk-operator-system

# Install the operator
helm install awscdk-operator aws-cdk-operator/aws-cdk-operator \
  --namespace awscdk-operator-system \
  --create-namespace \
  --set operator.env.debugMode=false
```

#### Install with Custom Values

Create a `values.yaml` file to customize the installation:

```yaml
# values.yaml
operator:
  namespace: "awscdk-operator-system"
  env:
    debugMode: true
    driftCheckCron: "*/5 * * * *"
    gitSyncCheckCron: "*/2 * * * *"

image:
  repository: "ghcr.io/awscdk-operator/cdk-ts-operator"
  tag: "latest"

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

# SSH configuration for private Git repositories
ssh:
  secretName: "awscdk-operator-ssh-key"
  hosts:
    github:
      hostname: "github.com"
      user: "git"
      strictHostKeyChecking: true
```

Then install with custom values:

```bash
helm install awscdk-operator aws-cdk-operator/aws-cdk-operator \
  --namespace awscdk-operator-system \
  --create-namespace \
  -f values.yaml
```

### Method 2: ArgoCD Application

For GitOps workflows with ArgoCD, create an Application resource:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: awscdk
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: aws-cdk-operator
    repoURL: https://awscdk.dev/charts
    targetRevision: 0.0.105
    helm:
      valuesObject:
        image:
          tag: "v0.0.104"
        operator:
          env:
            debugMode: true
            driftCheckCron: "*/10 * * * *"
            gitSyncCheckCron: "*/5 * * * *"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: awscdk-operator-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Apply the ArgoCD Application:

```bash
kubectl apply -f argocd-awscdk-operator.yaml
```



## Post-Installation Setup

### 1. Create AWS Credentials Secret

Create a Kubernetes secret with your AWS credentials:

```bash
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=your-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-secret-key \
  --namespace=awscdk-operator-system
```

> ⚠️ **Security Warning**: Never commit real AWS credentials to version control!

### 2. (Optional) Create SSH Key Secret for Private Repositories

If you plan to use private Git repositories:

```bash
kubectl create secret generic awscdk-operator-ssh-key \
  --from-file=ssh-privatekey=/path/to/your/private/key \
  --namespace=awscdk-operator-system
```

### 3. Verify Installation

Check that the operator is running:

```bash
# Check operator deployment
kubectl get deployment -n awscdk-operator-system

# Check operator logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator

# Verify CRD is installed
kubectl get crd cdktsstacks.awscdk.dev

# Test the shortcut command
kubectl get cdk
```

## Configuration Options

### Environment Variables

The operator supports these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `DEBUG_MODE` | Enable debug logging | `false` |
| `DRIFT_CHECK_CRON` | Cron schedule for drift detection | `*/10 * * * *` |
| `GIT_SYNC_CHECK_CRON` | Cron schedule for Git sync checks | `*/5 * * * *` |
| `METRICS_PREFIX` | Prefix for Prometheus metrics | `cdktsstack_operator` |

### SSH Configuration

For private Git repositories, the operator supports SSH key authentication:

```yaml
# SSH key secret
apiVersion: v1
kind: Secret
metadata:
  name: awscdk-operator-ssh-key
  namespace: awscdk-operator-system
type: kubernetes.io/ssh-auth
data:
  ssh-privatekey: |
    LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0K...
```

## Upgrading

### Helm Upgrade

```bash
# Update Helm repository
helm repo update

# Upgrade the operator
helm upgrade awscdk-operator aws-cdk-operator/aws-cdk-operator \
  --namespace awscdk-operator-system
```

### ArgoCD Upgrade

Update the `targetRevision` in your ArgoCD Application and sync:

```bash
kubectl patch application awscdk-operator -n argocd --type='merge' \
  -p='{"spec":{"source":{"targetRevision":"1.1.0"}}}'
```

## Uninstallation

### Helm Uninstall

```bash
helm uninstall awscdk-operator --namespace awscdk-operator-system
kubectl delete namespace awscdk-operator-system
```

### Manual Uninstall

```bash
# Delete all CdkTsStack resources first
kubectl delete cdktsstacks --all --all-namespaces

# Delete the operator
kubectl delete namespace awscdk-operator-system

# Delete the CRD
kubectl delete crd cdktsstacks.awscdk.dev
```

## Next Steps

Once installed, proceed to the [Quick Start](quick-start.md) guide to deploy your first CDK stack.

## Technical Foundation

This operator is built on top of [Shell Operator](https://flant.github.io/shell-operator/) by Flant, which provides a robust foundation for creating Kubernetes operators with shell scripts. Shell Operator handles the Kubernetes API interactions while our operator focuses on the CDK-specific logic and workflow management. 