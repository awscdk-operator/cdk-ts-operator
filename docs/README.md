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
- **Secure Credential Management**: Uses Kubernetes secrets for AWS credentials
- **Debug Mode**: Comprehensive logging for troubleshooting

## 📋 Prerequisites

- Kubernetes cluster (1.20+)
- CDK projects in Git repositories
- Node.js and npm (for CDK projects)
- AWS credentials with appropriate IAM permissions

## 🏗️ Architecture

The AWS CDK Operator consists of:

- **Custom Resource Definition (CRD)**: `CdkTsStack` resource type
- **Operator Controller**: Manages lifecycle of CDK stacks
- **Shell-based Hooks**: Extensible lifecycle automation
- **Git Synchronization**: Automatic repository synchronization
- **Drift Detection**: Continuous monitoring of infrastructure state

## 🔧 How It Works

1. **Resource Creation**: Define CDK stacks as Kubernetes resources
2. **Git Synchronization**: Operator clones/pulls from specified Git repositories
3. **CDK Execution**: Runs CDK commands (deploy, destroy, diff) in isolated environments
4. **Lifecycle Hooks**: Executes custom scripts at various stages
5. **Status Reporting**: Updates resource status with deployment information
6. **Drift Monitoring**: Periodically checks for infrastructure drift

## 🎯 Use Cases

- **GitOps Infrastructure**: Declarative infrastructure management
- **Multi-Environment Deployments**: Consistent deployments across environments
- **Infrastructure Automation**: Automated deployment pipelines
- **Drift Management**: Continuous compliance monitoring
- **Development Workflows**: Simplified infrastructure development and testing

## 🚀 Getting Started

Ready to get started? Check out our [Installation Guide](installation.md) and [Quick Start](quick-start.md) to deploy your first CDK stack with the operator.

For comprehensive examples, explore our [Examples](examples/) section which covers everything from basic deployments to advanced production setups.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](contributing.md) for details on how to contribute to the project.

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](https://github.com/awscdk-operator/cdk-ts-operator/blob/main/LICENSE) file for details.

## 🙏 Acknowledgments

- Built on [Shell Operator](https://flant.github.io/shell-operator/) by Flant
- Inspired by the AWS CDK community
- Thanks to all contributors and users
