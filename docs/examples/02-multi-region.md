# 02 - Multi Region

**Level**: Beginner  
**Purpose**: Deploy identical CDK stacks across multiple AWS regions

## Overview

This example demonstrates how to deploy the same CDK stack to multiple AWS regions simultaneously. This is useful for disaster recovery, global applications, and compliance requirements.

## What This Example Creates

- S3 buckets in us-east-1, us-west-2, and eu-west-1
- Three separate CloudFormation stacks (one per region)
- Three Kubernetes resources tracking each stack

## Use Cases

- Multi-region disaster recovery
- Global application deployment
- Regional compliance requirements (e.g., GDPR)
- Geographic distribution of resources

## Prerequisites

1. Completed [01 - Basic Stack](01-basic-stack.md) example
2. AWS credentials with permissions in multiple regions
3. CDK project that supports multi-region deployment

## Sample CDK Code

Your CDK project should handle region-specific naming to avoid conflicts:

```typescript
// lib/multi-region-stack.ts
import { Stack, StackProps } from 'aws-cdk-lib';
import { Bucket } from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export class MultiRegionStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);
    
    // Create region-specific bucket name to avoid conflicts
    const region = this.region;
    new Bucket(this, 'RegionalBucket', {
      bucketName: `my-app-bucket-${region}-${this.account}`
    });
  }
}
```

## Resource Definitions

### US East 1 (Primary Region)

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: app-stack-us-east-1              # Region-specific resource name
  namespace: default
  labels:
    example: "02-multi-region"
    level: "beginner"
    region: "us-east-1"
    role: "primary"                      # This is our primary region
spec:
  stackName: MyApp-USEast1-Stack         # Region-specific CloudFormation stack name
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1                   # Primary region
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./multi-region                   # Separate project for multi-region deployment
  
  # CDK context parameters to identify the region and deployment type
  cdkContext:
    - "region=us-east-1"
    - "isPrimary=true"
    - "environment=production"
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false                  # Conservative approach for production
```

### US West 2 (Secondary Region)

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: app-stack-us-west-2
  namespace: default
  labels:
    example: "02-multi-region"
    level: "beginner"
    region: "us-west-2"
    role: "secondary"
spec:
  stackName: MyApp-USWest2-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-west-2                   # West Coast region for disaster recovery
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./multi-region
  
  cdkContext:
    - "region=us-west-2"
    - "isPrimary=false"
    - "environment=production"
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
```

### EU West 1 (European Region)

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: app-stack-eu-west-1
  namespace: default
  labels:
    example: "02-multi-region"
    level: "beginner"
    region: "eu-west-1"
    role: "european"                     # For GDPR compliance
spec:
  stackName: MyApp-EUWest1-Stack
  credentialsSecretName: aws-credentials
  awsRegion: eu-west-1                   # European region for GDPR compliance
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./multi-region
  
  cdkContext:
    - "region=eu-west-1"
    - "isPrimary=false"
    - "environment=production"
    - "gdprCompliant=true"               # Additional context for European deployment
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
```

## Deployment Strategy

1. **Deploy primary region first** (us-east-1)
2. **Verify primary deployment** is successful
3. **Deploy secondary regions** in parallel
4. **Validate cross-region functionality**

## Monitoring Multi-Region Deployments

### Monitor All Regional Deployments

```bash
# Check all stacks across regions
kubectl get cdk -l example=02-multi-region

# View regional deployment status
kubectl get cdk -l region=us-east-1
kubectl get cdk -l region=us-west-2
kubectl get cdk -l region=eu-west-1

# Watch all regional deployments
kubectl get cdk -l example=02-multi-region -w
```

### Check Specific Regional Stack

```bash
kubectl describe cdk app-stack-us-east-1
```

### Verify AWS Resources in Each Region

```bash
# Check S3 buckets in each region
aws s3 ls --region us-east-1
aws s3 ls --region us-west-2
aws s3 ls --region eu-west-1

# Check CloudFormation stacks
aws cloudformation list-stacks --region us-east-1
aws cloudformation list-stacks --region us-west-2
aws cloudformation list-stacks --region eu-west-1
```

## Best Practices for Multi-Region

### Resource Naming
- Use region-specific resource names to avoid conflicts
- Include account ID in globally unique names
- Follow consistent naming conventions across regions

### Deployment Order
- Deploy primary region first, then secondary regions
- Validate each region before proceeding to the next
- Consider dependencies between regions

### Configuration Management
- Use CDK context to handle region-specific configurations
- Implement region-aware logic in your CDK code
- Plan for different compliance requirements per region

### Monitoring and Alerts
- Set up region-specific monitoring
- Implement cross-region health checks
- Plan for region failover scenarios

## Troubleshooting

### Common Issues

1. **Resource naming conflicts**: Ensure bucket names and other global resources are unique
2. **Permission issues**: Verify AWS credentials have access to all target regions
3. **Region-specific limits**: Check AWS service quotas in each region
4. **Network connectivity**: Ensure proper VPC setup for cross-region communication

### Debugging Commands

```bash
# Check deployment status across all regions
kubectl get cdk -l example=02-multi-region -o wide

# Check operator logs for specific regions
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -E "(us-east-1|us-west-2|eu-west-1)"
```

## Cleanup

To clean up resources in all regions:

```bash
kubectl delete cdk -l example=02-multi-region
```

This will clean up resources in all three regions simultaneously.

## Key Concepts Learned

- Multi-region deployment patterns
- Region-specific resource naming strategies
- Using labels for regional organization
- CDK context for region-aware configurations
- Monitoring cross-region deployments

## Next Steps

- [03 - With Context](03-with-context.md) - Learn to pass environment-specific parameters
- [06 - Drift Detection](06-drift-detection.md) - Monitor infrastructure changes across regions 