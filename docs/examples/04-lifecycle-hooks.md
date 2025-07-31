# 04 - Lifecycle Hooks

**Level**: Intermediate  
**Purpose**: Demonstrate basic lifecycle hooks for notifications, logging, and simple automation

## Overview

This example demonstrates how to use lifecycle hooks to add custom automation at key deployment stages. You'll learn to implement notifications, logging, health checks, and basic validation procedures.

## What This Example Creates

- Lambda function with automated testing
- Notification system using lifecycle hooks  
- Basic health checks and validation
- Simple backup procedures

## Prerequisites

1. Completed examples [01-03](README.md#learning-path)
2. Understanding of shell scripting basics
3. Optional: Slack webhook URL for notifications

## Lifecycle Hooks Available

The AWS CDK Operator provides 8 lifecycle hooks for different stages:

| Hook | When Executed | Use Cases |
|------|---------------|-----------|
| `beforeDeploy` | Before CDK deploy starts | Validation, preparation, notifications |
| `afterDeploy` | After successful CDK deploy | Testing, health checks, notifications |
| `beforeDestroy` | Before CDK destroy starts | Backups, safety checks, approvals |
| `afterDestroy` | After successful CDK destroy | Cleanup, notifications, logging |
| `beforeDriftDetection` | Before drift check | Preparation, logging |
| `afterDriftDetection` | After drift check | Alerts, remediation decisions |
| `beforeGitSync` | Before Git sync check | Validation, preparation |
| `afterGitSync` | After Git sync check | Notifications, status updates |

## Environment Variables in Hooks

Hooks have access to these environment variables:

| Variable | Description | Available In |
|----------|-------------|--------------|
| `CDK_STACK_NAME` | CloudFormation stack name | All hooks |
| `CDK_STACK_REGION` | AWS region | All hooks |
| `AWS_ACCOUNT_ID` | AWS account ID | All hooks |
| `DRIFT_DETECTED` | `true`/`false` | Drift detection hooks |
| `GIT_CHANGES_DETECTED` | `true`/`false` | Git sync hooks |

## Example Implementation

### Basic Stack with Lifecycle Hooks

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: lambda-with-hooks
  namespace: default
  labels:
    example: "04-lifecycle-hooks"
    level: "intermediate"
spec:
  stackName: MyLambda-With-Hooks-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./lambda-example               # CDK project that creates a Lambda function
  
  cdkContext:
    - "environment=development"
    - "functionName=my-demo-function"
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
  
  lifecycleHooks:
    # Pre-deployment validation and notifications
    beforeDeploy: |
      echo "🚀 Starting deployment of stack: $CDK_STACK_NAME"
      echo "📍 Region: $CDK_STACK_REGION"
      echo "🔍 AWS Account: $AWS_ACCOUNT_ID"
      echo "📅 Timestamp: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"
      
      # Basic environment validation
      echo "🔧 Validating deployment environment..."
      
      # Check AWS CLI configuration
      if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo "❌ ERROR: AWS credentials not properly configured"
        exit 1
      fi
      
      echo "✅ AWS credentials validated"
      echo "✅ Pre-deployment checks completed successfully"
    
    # Post-deployment testing and verification
    afterDeploy: |
      echo "🎉 Successfully deployed stack: $CDK_STACK_NAME"
      
      # Get stack outputs for validation
      echo "📋 Retrieving stack outputs..."
      STACK_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name $CDK_STACK_NAME \
        --region $CDK_STACK_REGION \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo "[]")
      
      # Extract Lambda function name if available
      FUNCTION_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="FunctionName") | .OutputValue' 2>/dev/null || echo "")
      
      if [ -n "$FUNCTION_NAME" ] && [ "$FUNCTION_NAME" != "null" ]; then
        echo "🔍 Testing Lambda function: $FUNCTION_NAME"
        
        # Simple health check - invoke the function
        echo "🧪 Running post-deployment health check..."
        
        INVOKE_RESULT=$(aws lambda invoke \
          --function-name $FUNCTION_NAME \
          --payload '{"test": true, "source": "cdk-operator-healthcheck"}' \
          --region $CDK_STACK_REGION \
          /tmp/lambda-response.json 2>&1)
        
        if [ $? -eq 0 ]; then
          echo "✅ Lambda function health check passed"
        else
          echo "⚠️  Lambda function health check failed: $INVOKE_RESULT"
        fi
      fi
      
      echo "✅ Post-deployment validation completed"
    
    # Pre-destruction backup and safety checks
    beforeDestroy: |
      echo "⚠️  Preparing to destroy stack: $CDK_STACK_NAME"
      
      # Create backup of important data if needed
      echo "💾 Creating backup before destruction..."
      
      # Log destruction for audit trail
      echo "📝 Logging destruction event for compliance"
      
      echo "✅ Pre-destruction preparations completed"
    
    # Post-destruction cleanup and notifications
    afterDestroy: |
      echo "🗑️  Successfully destroyed stack: $CDK_STACK_NAME"
      echo "🧹 Performing post-destruction cleanup..."
      echo "✅ Destruction completed at $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"
    
    # Drift detection notifications
    afterDriftDetection: |
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "🚨 DRIFT DETECTED in stack: $CDK_STACK_NAME"
        echo "📍 Region: $CDK_STACK_REGION"
        echo "⚠️  Manual changes detected - review required"
        
        # Optional: Send alert to Slack/Teams
        # curl -X POST -H 'Content-type: application/json' \
        #   --data "{\"text\":\"🚨 Drift detected in $CDK_STACK_NAME\"}" \
        #   $SLACK_WEBHOOK_URL
      else
        echo "✅ No drift detected in stack: $CDK_STACK_NAME"
      fi
```

## Common Hook Patterns

### 1. Slack Notifications

```bash
beforeDeploy: |
  if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"🚀 Starting deployment: $CDK_STACK_NAME\"}" \
      $SLACK_WEBHOOK_URL
  fi
```

### 2. Health Check with Retries

```bash
afterDeploy: |
  # Health check with retries
  MAX_RETRIES=3
  RETRY_COUNT=0
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f $HEALTH_CHECK_URL; then
      echo "✅ Health check passed"
      break
    else
      echo "⚠️  Health check failed, retrying in 10s..."
      sleep 10
      RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
  done
```

### 3. Backup Before Destruction

```bash
beforeDestroy: |
  # Backup RDS databases
  DB_IDENTIFIER=$(aws rds describe-db-instances \
    --query 'DBInstances[0].DBInstanceIdentifier' \
    --output text)
  
  if [ "$DB_IDENTIFIER" != "None" ]; then
    aws rds create-db-snapshot \
      --db-instance-identifier $DB_IDENTIFIER \
      --db-snapshot-identifier backup-$(date +%Y%m%d-%H%M%S)
  fi
```

### 4. Environment-Specific Logic

```bash
beforeDeploy: |
  # Get environment from context or labels
  ENVIRONMENT=$(kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.metadata.labels.environment}')
  
  if [ "$ENVIRONMENT" = "production" ]; then
    echo "🔒 Production deployment - extra validations..."
    # Add production-specific checks
  else
    echo "🔧 Development deployment - standard checks..."
  fi
```

## Monitoring Commands

### Check Hook Execution

```bash
# View recent hook executions in operator logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator --since=10m | grep -i hook

# Check specific stack events
kubectl describe cdk lambda-with-hooks
```

### Debug Hook Failures

```bash
# Enable debug mode for detailed hook logging
kubectl patch deployment awscdk-operator -n awscdk-operator-system --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "operator",
            "env": [
              {
                "name": "DEBUG_MODE",
                "value": "true"
              }
            ]
          }
        ]
      }
    }
  }
}'
```

## Best Practices

### Hook Development

1. **Keep hooks simple**: Complex logic should be in external scripts
2. **Use proper error handling**: Always check command exit codes
3. **Add logging**: Include timestamps and context information
4. **Test thoroughly**: Test hooks in development before production

### Security Considerations

1. **No secrets in hooks**: Use Kubernetes secrets for sensitive data
2. **Limit permissions**: Hooks run with operator privileges
3. **Validate inputs**: Always validate environment variables
4. **Audit trail**: Log all significant actions

### Performance

1. **Avoid long-running operations**: Keep hooks under 5 minutes
2. **Use background jobs**: For long operations, start background processes
3. **Parallel execution**: Multiple hooks can run in parallel
4. **Resource limits**: Be mindful of operator resource constraints

## Troubleshooting

### Common Issues

1. **Hook timeout**: Hooks have a default 10-minute timeout
2. **Missing tools**: Ensure required tools (jq, curl) are available
3. **Permission errors**: Verify AWS credentials and Kubernetes RBAC
4. **Network issues**: Check connectivity for external API calls

### Debugging

```bash
# Test hook logic locally
export CDK_STACK_NAME="test-stack"
export CDK_STACK_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"

# Run your hook script
bash -x your-hook-script.sh
```

## Example CDK Project Structure

Your CDK project should include Lambda function code:

```
lambda-example/
├── package.json
├── tsconfig.json
├── cdk.json
├── lib/
│   └── lambda-stack.ts
└── lambda/
    └── index.js
```

Sample CDK stack:

```typescript
// lib/lambda-stack.ts
import { Stack, StackProps, CfnOutput } from 'aws-cdk-lib';
import { Function, Runtime, Code } from 'aws-cdk-lib/aws-lambda';
import { Construct } from 'constructs';

export class LambdaStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);
    
    const functionName = this.node.tryGetContext('functionName') || 'demo-function';
    
    const lambdaFunction = new Function(this, 'DemoFunction', {
      runtime: Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: Code.fromAsset('lambda'),
      functionName: functionName
    });
    
    new CfnOutput(this, 'FunctionName', {
      value: lambdaFunction.functionName,
      description: 'Lambda function name'
    });
  }
}
```

## Next Steps

- [05 - Advanced Hooks](05-advanced-hooks.md) - Complex automation scenarios
- [06 - Drift Detection](06-drift-detection.md) - Monitor infrastructure changes
- [08 - Production Ready](08-production-ready.md) - Complete production setup 