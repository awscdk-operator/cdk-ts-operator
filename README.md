# AWS CDK Operator for Kubernetes

A Kubernetes operator that enables declarative management of AWS CDK (Cloud Development Kit) stacks using Custom Resource Definitions (CRDs). Deploy, update, and manage your AWS infrastructure directly from Kubernetes manifests with full lifecycle support.

Built on top of [Shell Operator](https://flant.github.io/shell-operator/) by Flant, this operator provides a robust foundation for managing AWS infrastructure through GitOps workflows.

## 🚀 Features

- **Declarative Infrastructure**: Manage AWS CDK stacks as Kubernetes resources
- **Full Lifecycle Management**: Deploy, update, destroy, and drift detection
- **Git Integration**: Automatically sync and deploy from Git repositories
- **Lifecycle Hooks**: Execute custom scripts at various stages of stack lifecycle
- **Multi-Region Support**: Deploy stacks across different AWS regions
- **Drift Detection**: Monitor and optionally auto-remediate infrastructure drift
- **ArgoCD Integration**: Seamless GitOps workflows with ArgoCD

## 📖 Documentation

📚 **[Complete Documentation](https://awscdk.dev/)**

## 🛠 Quick Installation

Install via Helm (recommended):

```bash
helm repo add aws-cdk-operator https://awscdk.dev/charts
helm install awscdk-operator aws-cdk-operator/aws-cdk-operator \
  --namespace awscdk-operator-system \
  --create-namespace
```

For detailed installation options, see the [Installation Guide](docs/installation.md).

## 🚀 Quick Start

1. Create AWS credentials secret:
   ```bash
   kubectl create secret generic aws-credentials \
     --from-literal=AWS_ACCESS_KEY_ID=your-access-key \
     --from-literal=AWS_SECRET_ACCESS_KEY=your-secret-key \
     --namespace=awscdk-operator-system
   ```

2. Deploy your first CDK stack:
   ```yaml
   apiVersion: awscdk.dev/v1alpha1
   kind: CdkTsStack
   metadata:
     name: my-s3-bucket
   spec:
     stackName: MyS3BucketStack
     credentialsSecretName: aws-credentials
     awsRegion: us-east-1
     source:
       git:
         repository: https://github.com/your-org/cdk-infrastructure.git
         ref: main
     path: s3-bucket
     actions:
       deploy: true
       destroy: true
       driftDetection: true
   ```

3. Apply and monitor:
   ```bash
   kubectl apply -f my-stack.yaml
   kubectl get cdk
   ```

For a complete walkthrough, see the [Quick Start Guide](docs/quick-start.md).

## 📚 Examples

- [Basic Stack](docs/examples/01-basic-stack.md) - Simple S3 bucket deployment
- [Multi-Region](docs/examples/02-multi-region.md) - Deploy across multiple regions
- [With Context](docs/examples/03-with-context.md) - Environment-specific configurations
- [Lifecycle Hooks](docs/examples/04-lifecycle-hooks.md) - Custom automation
- [Production Ready](docs/examples/08-production-ready.md) - Complete production setup
- [ArgoCD Integration](docs/examples/09-argocd-integration.md) - GitOps workflows

See all [examples](docs/examples/) for comprehensive usage patterns.

## 🐛 Troubleshooting

If your operator gets stuck in a phase, you can manually reset the status:

```bash
kubectl patch cdk my-stack --subresource=status --type='merge' \
  -p='{"status":{"phase":"Succeeded","message":"Manual restart"}}'
```

For detailed troubleshooting, see the [Troubleshooting Guide](docs/troubleshooting.md).

## 🏗️ Technical Foundation

This operator is built on [Shell Operator](https://flant.github.io/shell-operator/) by Flant, which provides a robust foundation for creating Kubernetes operators with shell scripts.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](docs/contributing.md) for details.

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Documentation**: https://awscdk.dev/
- **GitHub**: https://github.com/awscdk-operator/cdk-ts-operator
- **Shell Operator**: https://flant.github.io/shell-operator/
