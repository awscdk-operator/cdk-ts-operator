# Quick Start

This guide will help you deploy your first AWS CDK stack using the AWS CDK Operator in just a few minutes.

## Prerequisites

Before starting, ensure you have:

- [Installed the AWS CDK Operator](installation.md)
- AWS credentials configured as a Kubernetes secret
- A CDK project in a Git repository

## Step 1: Verify Installation

First, verify that the operator is running:

```bash
kubectl get deployment -n awscdk-operator-system
kubectl get crd cdktsstacks.awscdk.dev
```

You should see the operator deployment running and the CRD installed.

## Step 2: Verify Required Secrets

Before deploying stacks, verify that you have the required secrets:

### Check AWS Credentials Secret

```bash
# Verify AWS credentials secret exists
kubectl get secret aws-credentials -n awscdk-operator-system

# Check the secret contains the required keys
kubectl get secret aws-credentials -n awscdk-operator-system -o jsonpath='{.data}' | jq 'keys'
```

You should see `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in the output.

### Check SSH Key Secret (for private repositories)

If you plan to use private Git repositories, verify the SSH key secret:

```bash
# Check if SSH key secret exists (optional)
kubectl get secret awscdk-operator-ssh-key -n awscdk-operator-system

# Verify it contains the SSH private key
kubectl get secret awscdk-operator-ssh-key -n awscdk-operator-system -o jsonpath='{.data.ssh-privatekey}' | base64 -d | head -1
```

You should see `-----BEGIN OPENSSH PRIVATE KEY-----` or similar.

## Step 3: Create Your First CDK Stack

Create a simple CDK stack resource that deploys an S3 bucket:

```yaml
# my-first-stack.yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: my-first-stack
  namespace: default
spec:
  stackName: MyFirstStack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  source:
    git:
      repository: https://github.com/awscdk-operator/examples.git
      ref: main
  path: basic-s3-bucket
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
```

## Step 4: Apply the Resource

Deploy the stack:

```bash
kubectl apply -f my-first-stack.yaml
```

## Step 5: Monitor the Deployment

Watch the stack deployment progress:

```bash
# Check stack status (using shortcut)
kubectl get cdk

# Get detailed information
kubectl describe cdk my-first-stack

# Watch operator logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator -f
```

The stack will go through several phases:
1. **Cloning** - Downloading the Git repository
2. **Installing** - Installing CDK dependencies
3. **Deploying** - Executing CDK deploy
4. **Succeeded** - Deployment completed successfully

## Step 6: Verify in AWS

Once the stack reaches `Succeeded` status, verify the resources in AWS:

```bash
# Using AWS CLI
aws cloudformation describe-stacks --stack-name MyFirstStack --region us-east-1

# Or check in AWS Console
# Navigate to CloudFormation > Stacks > MyFirstStack
```

## Understanding the Stack Resource

Let's break down the key fields in the CDK stack resource:

### Basic Configuration

```yaml
spec:
  stackName: MyFirstStack              # CloudFormation stack name
  credentialsSecretName: aws-credentials  # Kubernetes secret with AWS credentials
  awsRegion: us-east-1                # Target AWS region
```

### Git Source

```yaml
  source:
    git:
      repository: https://github.com/awscdk-operator/examples.git  # Git repository URL
      ref: main                        # Branch, tag, or commit hash
  path: basic-s3-bucket               # Path to CDK project within repository
```

### Actions

```yaml
  actions:
    deploy: true          # Allow stack deployment
    destroy: true         # Allow stack destruction
    driftDetection: true  # Enable drift monitoring
    autoRedeploy: false   # Auto-deploy Git changes, but not remediate drifts https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html
```

## Common Stack Operations

### View Stack Status

```bash
# List all stacks (using shortcut)
kubectl get cdk

# Get detailed status
kubectl describe cdk my-first-stack

# Get stack status information
kubectl get cdk my-first-stack -o jsonpath='{.status}'
```

### Update Stack

To update the stack, modify the resource and apply:

```bash
# Edit the resource
kubectl edit cdk my-first-stack

# Or apply updated YAML
kubectl apply -f my-updated-stack.yaml
```

### Delete Stack

To destroy the AWS resources and delete the stack:

```bash
kubectl delete cdk my-first-stack
```

This will:
1. Run `cdk destroy` to remove AWS resources
2. Delete the Kubernetes resource

## Troubleshooting

### Stack Stuck in a Phase

If a stack gets stuck, check the logs:

```bash
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep my-first-stack
```

### Manual Phase Reset

If needed, you can manually reset the stack phase:

```bash
kubectl patch cdk my-first-stack --subresource=status --type='merge' \
  -p='{"status":{"phase":"Succeeded","message":"Manual restart"}}'
```

### Common Issues

1. **"Cloning" phase stuck**
   - Check Git repository accessibility
   - Verify network connectivity

2. **"Installing" phase fails**
   - Check CDK project has valid `package.json`
   - Verify Node.js/npm setup in repository

3. **"Deploying" phase fails**
   - Check AWS credentials and permissions
   - Verify CDK project validity
   - Review CloudFormation events in AWS Console

## Next Steps

Now that you've deployed your first stack, explore more advanced features:

- [Configuration Guide](configuration.md) - Learn about all configuration options
- [Examples](examples/) - Explore comprehensive examples
- [Lifecycle Hooks](examples/04-lifecycle-hooks.md) - Add custom automation
- [Drift Detection](examples/06-drift-detection.md) - Monitor infrastructure changes
- [Production Setup](examples/08-production-ready.md) - Production best practices

## Example CDK Project Structure

For reference, here's what a basic CDK project structure looks like:

```
basic-s3-bucket/
├── package.json
├── tsconfig.json
├── cdk.json
├── lib/
│   └── s3-stack.ts
└── bin/
    └── app.ts
```

The operator will:
1. Clone the repository
2. Navigate to the `path` directory
3. Run `npm install`
4. Execute `cdk deploy --require-approval never`

Your CDK project should be ready to deploy without manual intervention. 