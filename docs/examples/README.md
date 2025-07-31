# Examples

This directory contains a comprehensive set of examples demonstrating the AWS CDK Operator capabilities, organized from simple to advanced usage. Each example includes detailed documentation to serve as both learning material and reference documentation.

## 🎯 Learning Path

Follow these examples in order to learn the AWS CDK Operator from basic concepts to advanced production usage:

| Example | Level | Description | Key Features |
|---------|-------|-------------|--------------|
| [01 - Basic Stack](01-basic-stack.md) | Beginner | Simple S3 bucket deployment | Basic configuration, minimal setup |
| [02 - Multi Region](02-multi-region.md) | Beginner | Deploy stacks across regions | Multiple regions, basic scaling |
| [03 - With Context](03-with-context.md) | Intermediate | Using CDK context parameters | Environment variables, context passing |
| [04 - Lifecycle Hooks](04-lifecycle-hooks.md) | Intermediate | Basic lifecycle hooks | Simple notifications, logging |
| [05 - Advanced Hooks](05-advanced-hooks.md) | Intermediate | Complex lifecycle automation | Validations, testing, backups |
| [06 - Drift Detection](06-drift-detection.md) | Intermediate | Drift monitoring & alerting | Monitoring, manual remediation |
| [07 - Git Integration](07-git-integration.md) | Advanced | Private repositories & SSH | SSH keys, private Git repos |
| [08 - Production Ready](08-production-ready.md) | Advanced | Complete production setup | All features, best practices |

## 📋 Prerequisites

Before running these examples, ensure you have:

### 1. Kubernetes Cluster
- Kubernetes 1.20+ cluster with kubectl access
- Sufficient RBAC permissions to create CRDs and operators

### 2. AWS CDK Operator Installation
- Follow the [Installation Guide](../installation.md) to install the operator
- Verify installation with `kubectl get crd cdktsstacks.awscdk.dev`
- Test the shortcut: `kubectl get cdk`

### 3. AWS Credentials
Create a Kubernetes secret with your AWS credentials:

```bash
# ⚠️  SECURITY WARNING: Never commit real AWS credentials to version control!
# Replace the placeholder values below with your actual credentials.

kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_HERE \
  --from-literal=AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY_HERE \
  --namespace=awscdk-operator-system
```

### 4. CDK Project Repository
You'll need a Git repository containing CDK projects. For testing, you can use our sample repository:
- **Public repo**: `https://github.com/your-org/cdk-examples` (for basic examples)
- **Private repo**: `git@github.com:your-org/private-cdk.git` (for advanced examples)

### 5. Optional: SSH Key for Private Repositories
For examples using private repositories:

```bash
# Create SSH key secret for private repositories (if needed)
kubectl create secret generic awscdk-operator-ssh-key \
  --from-file=ssh-privatekey=/path/to/your/private/key \
  --namespace=awscdk-operator-system
```

## 🚀 Quick Start

1. **Start with the basic example**:
   ```bash
   kubectl apply -f examples/01-basic-stack.yaml
   ```

2. **Monitor the deployment**:
   ```bash
kubectl get cdk
kubectl describe cdk my-first-stack
```

3. **Check operator logs**:
   ```bash
   kubectl logs -n awscdk-operator-system deployment/awscdk-operator -f
   ```

## 📖 Example Descriptions

### [01 - Basic Stack](01-basic-stack.md)
**Level**: Beginner  
**Purpose**: Your first CDK stack deployment with minimal configuration.

Demonstrates:
- Basic CdkTsStack resource creation
- S3 bucket deployment
- Essential required fields
- Simple monitoring

### [02 - Multi Region](02-multi-region.md)
**Level**: Beginner  
**Purpose**: Deploy identical stacks across multiple AWS regions.

Demonstrates:
- Multi-region deployment patterns
- Region-specific configurations
- Resource naming strategies
- Cross-region management

### [03 - With Context](03-with-context.md)
**Level**: Intermediate  
**Purpose**: Pass environment variables and context to CDK stacks.

Demonstrates:
- CDK context parameters
- Environment-specific configurations
- Variable interpolation
- Configuration management

### [04 - Lifecycle Hooks](04-lifecycle-hooks.md)
**Level**: Intermediate  
**Purpose**: Add custom automation at different stages of stack lifecycle.

Demonstrates:
- Basic lifecycle hooks
- Notification integration
- Simple validations
- Event-driven automation

### [05 - Advanced Hooks](05-advanced-hooks.md)
**Level**: Intermediate  
**Purpose**: Complex automation with validations, testing, and backup strategies.

Demonstrates:
- Advanced hook scripting
- Pre-deployment validations
- Post-deployment testing
- Backup and recovery procedures
- Error handling patterns

### [06 - Drift Detection](06-drift-detection.md)
**Level**: Intermediate  
**Purpose**: Monitor infrastructure drift and implement proper drift management.

Demonstrates:
- Drift detection configuration
- Manual remediation workflows  
- Monitoring and alerting
- Difference between drift detection and Git autoRedeploy

### [07 - Git Integration](07-git-integration.md)
**Level**: Advanced  
**Purpose**: Work with private repositories and advanced Git features.

Demonstrates:
- SSH key management
- Private repository access
- Git branch strategies
- Security best practices

### [08 - Production Ready](08-production-ready.md)
**Level**: Advanced  
**Purpose**: Complete production-ready setup with all features enabled.

Demonstrates:
- Production best practices
- Security configurations
- Monitoring and observability
- High availability patterns
- Comprehensive lifecycle management

## 🔧 Common Configuration Patterns

### Basic Stack Configuration
```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: example-stack
spec:
  stackName: MyStack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  source:
    git:
      repository: https://github.com/your-org/cdk-project.git
      ref: main
  path: ./
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
```

### Actions Configuration
| Action | Description | Default | Use Case |
|--------|-------------|---------|----------|
| `deploy` | Allow stack deployment | `true` | Enable/disable deployments |
| `destroy` | Allow stack destruction | `true` | Protect critical resources |
| `driftDetection` | Enable drift monitoring | `true` | Monitor configuration changes |
| `autoRedeploy` | Auto-deploy Git changes | `false` | Respond to source code updates |

### Lifecycle Hooks Available
- `beforeDeploy`: Execute before CDK deploy
- `afterDeploy`: Execute after successful deploy
- `beforeDestroy`: Execute before CDK destroy
- `afterDestroy`: Execute after successful destroy
- `beforeDriftDetection`: Execute before drift check
- `afterDriftDetection`: Execute after drift check
- `beforeGitSync`: Execute before Git sync check
- `afterGitSync`: Execute after Git sync check

## 🐛 Troubleshooting

### Common Issues

1. **Stack stuck in "Cloning" phase**
   - Check Git repository accessibility
   - Verify SSH keys for private repos
   - Check network connectivity

2. **"Failed to assume role" errors**
   - Verify AWS credentials in secret
   - Check IAM permissions
   - Ensure correct AWS region

3. **CDK deployment failures**
   - Check CDK project validity
   - Verify Node.js/npm setup in repository
   - Review CDK context parameters

4. **Drift detection not working**
   - Ensure `driftDetection: true` in actions
   - Check CloudFormation stack status
   - Verify AWS permissions for drift detection

### Debug Mode
Enable detailed logging by setting environment variable in the operator deployment:
```yaml
env:
- name: DEBUG_MODE
  value: "true"
```

### Useful Commands
```bash
# Check all CDK stacks
kubectl get cdk -A

# Get detailed stack information
kubectl describe cdk <stack-name>

# Check operator logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator

# Check events
kubectl get events --field-selector reason=CdkTsStackEvent
```

## 🔒 Security Best Practices

1. **Never commit AWS credentials to Git**
2. **Use IAM roles when possible instead of access keys**
3. **Limit IAM permissions to minimum required**
4. **Use separate AWS accounts for different environments**
5. **Rotate AWS credentials regularly**
6. **Review lifecycle hooks for security implications**
7. **Use private Git repositories for sensitive infrastructure code**

## 🤝 Contributing

Found an issue with these examples or want to add new ones? Please see our [Contributing Guide](../contributing.md) for details on how to contribute.

> **Tip**: Use the shortcut `kubectl get cdk` instead of the full `kubectl get cdktsstacks` for faster access to your CDK stacks!

## 📄 License

These examples are provided under the same license as the AWS CDK Operator project. 