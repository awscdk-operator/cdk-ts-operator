# 03 - With Context

**Level**: Intermediate  
**Purpose**: Pass context parameters to CDK stacks for environment-specific configurations

## Overview

This example demonstrates how to use CDK context parameters to create environment-specific configurations. You'll learn to pass configuration values from Kubernetes to your CDK stacks, enabling parameterized infrastructure deployments.

## What This Example Creates

- Development, Staging, and Production environments with different configurations
- S3 buckets with environment-specific settings
- Lambda functions with different memory allocations
- Different backup and monitoring settings per environment

## Prerequisites

1. Completed [01 - Basic Stack](01-basic-stack.md) and [02 - Multi Region](02-multi-region.md) examples
2. CDK project that accepts context parameters
3. Understanding of CDK context and how to use it in stack code

## CDK Context Usage

In your CDK code, you can access context parameters like this:

```typescript
// lib/environment-stack.ts
import { Stack, StackProps, Duration } from 'aws-cdk-lib';
import { Bucket } from 'aws-cdk-lib/aws-s3';
import { Function, Runtime, Code } from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

export class EnvironmentStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);
    
    // Read context values with defaults
    const env = this.node.tryGetContext('environment') || 'dev';
    const enableBackups = this.node.tryGetContext('enableBackups') === 'true';
    const logRetentionDays = parseInt(this.node.tryGetContext('logRetentionDays') || '7');
    const lambdaMemory = parseInt(this.node.tryGetContext('maxLambdaMemory') || '128');
    
    // Create environment-specific S3 bucket
    new Bucket(this, 'AppBucket', {
      bucketName: `my-app-${env}-${this.account}`,
      versioned: enableBackups,
      lifecycleRules: env === 'prod' ? [{ 
        expiration: Duration.days(365) 
      }] : []
    });
    
    // Create Lambda with environment-specific memory
    new Function(this, 'AppFunction', {
      runtime: Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: Code.fromInline('exports.handler = async () => ({ statusCode: 200 });'),
      memorySize: lambdaMemory,
      environment: {
        ENVIRONMENT: env,
        DEBUG_MODE: this.node.tryGetContext('debugMode') || 'false'
      }
    });
  }
}
```

## Environment Configurations

### Development Environment

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: app-development
  namespace: default
  labels:
    example: "03-with-context"
    level: "intermediate"
    environment: "development"
spec:
  stackName: MyApp-Development-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./context-aware                   # CDK project that uses context parameters
  
  # Context parameters for development environment
  cdkContext:
    - "environment=development"           # Environment identifier
    - "instanceType=t3.micro"            # Small instance for cost savings
    - "enableBackups=false"              # No backups needed in dev
    - "enableMonitoring=false"           # Minimal monitoring
    - "logRetentionDays=7"               # Short log retention
    - "bucketVersioning=false"           # No versioning in dev
    - "maxLambdaMemory=128"              # Minimal Lambda memory
    - "debugMode=true"                   # Enable debug logging
  
  actions:
    deploy: true
    destroy: true                        # Allow easy cleanup in dev
    driftDetection: false                # Skip drift detection in dev
    autoRedeploy: true                   # Auto-deploy changes for fast iteration
```

### Staging Environment

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: app-staging
  namespace: default
  labels:
    example: "03-with-context"
    level: "intermediate"
    environment: "staging"
spec:
  stackName: MyApp-Staging-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main                          # Use main branch for staging
  path: ./context-aware
  
  # Context parameters for staging environment
  cdkContext:
    - "environment=staging"
    - "instanceType=t3.small"            # Slightly larger for realistic testing
    - "enableBackups=true"               # Test backup functionality
    - "enableMonitoring=true"            # Full monitoring to test alerts
    - "logRetentionDays=30"              # Medium log retention
    - "bucketVersioning=true"            # Test versioning features
    - "maxLambdaMemory=256"              # Test with more memory
    - "debugMode=false"                  # Production-like logging
    - "testDataSize=small"               # Use smaller test datasets
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true                 # Test drift detection
    autoRedeploy: false                  # Manual deployment for staging
```

### Production Environment

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: app-production
  namespace: default
  labels:
    example: "03-with-context"
    level: "intermediate"
    environment: "production"
spec:
  stackName: MyApp-Production-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: v1.0.0                        # Use tagged release for production
  path: ./context-aware
  
  # Context parameters for production environment
  cdkContext:
    - "environment=production"
    - "instanceType=t3.medium"           # Adequate resources for production
    - "enableBackups=true"               # Essential for production data
    - "enableMonitoring=true"            # Full monitoring and alerting
    - "logRetentionDays=365"             # Long log retention for compliance
    - "bucketVersioning=true"            # Protect against accidental deletion
    - "maxLambdaMemory=512"              # Production-grade Lambda memory
    - "debugMode=false"                  # Clean production logs
    - "encryptionEnabled=true"           # Encrypt all data at rest
    - "crossRegionBackup=true"           # Cross-region backup strategy
    - "alertEmail=ops@company.com"       # Production alerts
  
  actions:
    deploy: true
    destroy: false                       # Protect production from accidental deletion
    driftDetection: true                 # Monitor for unauthorized changes
    autoRedeploy: false                  # Manual deployment only for production
```

## Context Parameters Reference

### Environment Configuration
- `environment`: dev|staging|prod (Environment identifier)
- `debugMode`: true|false (Enable debug logging)

### Resource Sizing
- `instanceType`: t3.micro|small|medium (EC2 instance sizes)
- `maxLambdaMemory`: 128|256|512 (Lambda memory allocation)
- `dbInstanceClass`: db.t3.micro (RDS instance class)

### Feature Flags
- `enableBackups`: true|false (Enable backup strategies)
- `enableMonitoring`: true|false (Enable CloudWatch monitoring)
- `bucketVersioning`: true|false (S3 bucket versioning)
- `encryptionEnabled`: true|false (Encrypt resources)

### Retention Policies
- `logRetentionDays`: 7|30|365 (CloudWatch logs retention)
- `backupRetentionDays`: 7|30|90 (Backup retention period)

### Networking
- `vpcCidr`: 10.0.0.0/16 (VPC CIDR block)
- `publicSubnets`: true|false (Create public subnets)

### Monitoring and Alerts
- `alertEmail`: email@company.com (Alert notification email)
- `slackWebhook`: https://hooks.slack... (Slack notification URL)

## How to Use Context in CDK Code

### 1. Read Context Values
```typescript
const env = this.node.tryGetContext('environment') || 'dev';
```

### 2. Use Context for Conditional Logic
```typescript
const retentionDays = parseInt(this.node.tryGetContext('logRetentionDays') || '7');
```

### 3. Convert String to Boolean
```typescript
const enableBackups = this.node.tryGetContext('enableBackups') === 'true';
```

### 4. Provide Defaults
```typescript
const instanceType = this.node.tryGetContext('instanceType') || 't3.micro';
```

## Monitoring Commands

### Check All Environments
```bash
kubectl get cdk -l example=03-with-context
```

### Check Specific Environment
```bash
kubectl get cdk -l environment=production
```

### Compare Context Across Environments
```bash
kubectl get cdk app-development -o yaml | grep -A 20 cdkContext
kubectl get cdk app-staging -o yaml | grep -A 20 cdkContext
kubectl get cdk app-production -o yaml | grep -A 20 cdkContext
```

## Deployment Strategy

1. **Deploy development first** for testing
2. **Deploy staging** to validate with production-like settings
3. **Deploy production** with stable tagged release

### Sequential Deployment

```bash
# Deploy development
kubectl apply -f dev-stack.yaml

# Wait for dev to succeed, then deploy staging
kubectl wait --for=condition=Ready cdk/app-development --timeout=300s
kubectl apply -f staging-stack.yaml

# Wait for staging to succeed, then deploy production
kubectl wait --for=condition=Ready cdk/app-staging --timeout=300s
kubectl apply -f prod-stack.yaml
```

## Best Practices

### Context Naming
- Use descriptive, lowercase names
- Follow consistent naming conventions
- Group related parameters logically

### Environment Differences
- **Development**: Minimal resources, fast iteration
- **Staging**: Production-like, comprehensive testing
- **Production**: Full features, maximum security

### Security Considerations
- Never pass secrets through context
- Use appropriate IAM policies per environment
- Enable encryption for production workloads

## Troubleshooting

### Context Not Being Applied
1. Check context parameter syntax in YAML
2. Verify CDK code is reading context correctly
3. Check operator logs for context parsing errors

### Environment-Specific Issues
1. **Development**: Check resource quotas for t3.micro instances
2. **Staging**: Verify monitoring and backup configurations
3. **Production**: Ensure compliance settings are applied

## Cleanup

```bash
kubectl delete cdk -l example=03-with-context
```

## Key Concepts Learned

- CDK context parameter usage
- Environment-specific configurations
- Feature flags and conditional deployments
- Resource sizing strategies
- Configuration management best practices

## Next Steps

- [04 - Lifecycle Hooks](04-lifecycle-hooks.md) - Add custom automation to your deployments
- [05 - Advanced Hooks](05-advanced-hooks.md) - Complex automation scenarios 