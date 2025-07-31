# 01 - Basic Stack

**Level**: Beginner  
**Purpose**: Deploy a simple S3 bucket using the AWS CDK Operator with minimal configuration

## Overview

This example demonstrates your first CDK stack deployment with the AWS CDK Operator. It covers the essential required fields and creates a simple S3 bucket in AWS.

## What This Example Creates

- A simple S3 bucket in AWS
- CloudFormation stack managed by CDK
- Kubernetes resource representing the CDK stack

## Prerequisites

1. AWS CDK Operator installed in your cluster
2. AWS credentials secret created (see [Installation Guide](../installation.md))
3. A Git repository with a simple CDK project that creates an S3 bucket

## Expected CDK Project Structure

Your Git repository should have this structure:

```
/
├── package.json          # CDK project dependencies
├── tsconfig.json         # TypeScript configuration
├── cdk.json              # CDK configuration
└── lib/
    └── my-stack.ts       # Stack definition with S3 bucket
```

## Sample CDK Code

Here's what your CDK stack should look like:

```typescript
// lib/my-stack.ts
import { Stack, StackProps } from 'aws-cdk-lib';
import { Bucket } from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export class MyStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);
    new Bucket(this, 'MyBucket');
  }
}
```

## Resource Definition

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: my-first-stack                    # Kubernetes resource name
  namespace: default                      # Deploy in default namespace
  labels:
    example: "01-basic"
    level: "beginner"
spec:
  # REQUIRED: Name of the CDK stack that will be created in AWS CloudFormation
  stackName: MyFirstS3Stack
  
  # REQUIRED: Reference to Kubernetes secret containing AWS credentials
  # The secret should have AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
  credentialsSecretName: aws-credentials
  
  # OPTIONAL: AWS region for deployment (defaults to us-east-1 if not specified)
  awsRegion: us-east-1
  
  # REQUIRED: Source code location - Git repository containing your CDK project
  source:
    git:
      # Replace with your actual Git repository URL
      repository: https://github.com/your-org/cdk-examples.git
      ref: main                           # Git branch or tag (defaults to main)
  
  # OPTIONAL: Path within the repository to your CDK project (defaults to root)
  path: ./
  
  # REQUIRED: Control which actions the operator can perform on this stack
  # All four fields are required to be explicit about operator permissions
  actions:
    deploy: true                          # Allow the operator to deploy this stack
    destroy: true                         # Allow the operator to destroy this stack when resource is deleted
    driftDetection: true                  # Enable monitoring for configuration drift
    autoRedeploy: false                   # Disable automatic redeployment (manual control)
```

## How to Use

1. **Update the repository URL**: Replace `https://github.com/your-org/cdk-examples.git` with your actual Git repository
2. **Ensure your repository has a CDK project** in the root or update the `path` field
3. **Apply the manifest**:
   ```bash
   kubectl apply -f docs/examples/01-basic-stack.yaml
   ```
4. **Monitor deployment**:
   ```bash
   kubectl get cdktsstacks
   ```
5. **Check details**:
   ```bash
   kubectl describe cdktsstack my-first-stack
   ```

## Monitoring and Debugging

### Check Stack Status

```bash
# View all CDK stacks
kubectl get cdk

# Get detailed information
kubectl describe cdk my-first-stack

# Watch deployment progress
kubectl get cdk -w
```

### Check Operator Logs

```bash
kubectl logs -n awscdk-operator-system deployment/awscdk-operator -f
```

### Verify in AWS

```bash
# Using AWS CLI
aws cloudformation describe-stacks --stack-name MyFirstS3Stack --region us-east-1

# Or check in AWS Console
# Navigate to CloudFormation > Stacks > MyFirstS3Stack
```

## Expected Status Progression

The stack will go through these phases:

1. **Pending** → Initial state
2. **Cloning** → Downloading Git repository
3. **Installing** → Installing CDK dependencies (npm install)
4. **Deploying** → Running CDK deploy
5. **Succeeded** → Stack successfully deployed

## Troubleshooting

- **Stuck in "Cloning"**: Check repository URL and accessibility
- **Stuck in "Installing"**: Check package.json and dependencies in your CDK project
- **Stuck in "Deploying"**: Check AWS credentials and permissions
- **Status "Failed"**: Check operator logs and stack description for error details

## Cleanup

To delete the stack and all AWS resources:

```bash
kubectl delete cdk my-first-stack
```

This will trigger the CDK destroy process and clean up all AWS resources.

## Key Concepts Learned

- Basic `CdkTsStack` resource structure
- Required vs optional fields
- Git integration with CDK projects
- Monitoring stack deployment status
- Basic troubleshooting techniques

## Next Steps

Once you've successfully deployed this basic stack, proceed to:
- [02 - Multi Region](02-multi-region.md) - Deploy stacks across multiple AWS regions
- [03 - With Context](03-with-context.md) - Pass parameters to your CDK stacks 