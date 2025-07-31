# 06 - Drift Detection

**Level**: Intermediate  
**Purpose**: Monitor infrastructure drift and implement proper drift management strategies

## Overview

This example demonstrates how to detect and monitor infrastructure drift. **Important**: Drift detection identifies manual changes to AWS resources but does **NOT** automatically fix them. This guide clarifies the differences between drift detection and Git-based autoRedeploy.

## What This Example Creates

- S3 bucket with drift monitoring
- Lambda function for drift notifications  
- Proper drift detection workflows
- Clear separation between drift detection and Git autoRedeploy

## Prerequisites

1. Completed examples [01-05](README.md#learning-path)
2. Understanding of CloudFormation drift detection
3. Basic knowledge of infrastructure compliance

## ⚠️ Critical Clarifications

**What is Infrastructure Drift?**
- Drift occurs when AWS resources are manually changed outside of CDK/CloudFormation
- Examples: Changing S3 bucket settings in AWS Console, modifying IAM policies via CLI
- **Drift detection identifies these changes but does NOT automatically fix them**
- Remediation requires manual intervention or operational procedures

**autoRedeploy vs Drift Detection:**
- **Drift Detection**: Monitors manual changes to deployed AWS resources
- **autoRedeploy**: Only responds to Git repository code changes (NOT drift)
- These are completely separate functionalities

**References:**
- [AWS CloudFormation Drift Detection](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html)

## Example Implementations

### 1. Drift Detection with Monitoring (Recommended)

This stack detects drift and provides proper remediation guidance:

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: s3-drift-monitoring
  namespace: default
  labels:
    example: "06-drift-detection"
    level: "intermediate"
    remediation: "manual"
spec:
  stackName: S3-DriftMonitoring-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./s3-example
  
  cdkContext:
    - "environment=development"
    - "bucketName=drift-monitor-bucket"
    - "enableVersioning=true"
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true    # ✅ Enable drift monitoring
    autoRedeploy: false     # ❌ autoRedeploy does NOT fix drift!
  
  lifecycleHooks:
    afterDriftDetection: |
      echo "🔍 Drift detection completed for $CDK_STACK_NAME"
      echo "📖 Reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html"
      
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "⚠️  DRIFT DETECTED - Manual changes found in AWS resources"
        echo "🔍 Resources have been modified outside of CDK/CloudFormation"
        echo ""
        echo "🛠️  MANUAL REMEDIATION REQUIRED:"
        echo "   1. Investigate what was changed manually"
        echo "   2. Either:"
        echo "      a) Revert manual changes in AWS Console/CLI, OR"
        echo "      b) Update CDK code to match the manual changes"
        echo "   3. Redeploy: kubectl annotate cdktsstack $CDK_STACK_RESOURCE_NAME kubectl.kubernetes.io/restartedAt=\"$(date)\""
        echo ""
        echo "❌ autoRedeploy does NOT fix drift (only works for Git changes)"
        
        # Get detailed drift information
        DRIFT_DETAILS=$(aws cloudformation describe-stack-resource-drifts \
          --stack-name "$CDK_STACK_NAME" \
          --region "$CDK_STACK_REGION" \
          --output json 2>/dev/null || echo '{"StackResourceDrifts":[]}')
        
        if [ "$DRIFT_DETAILS" != '{"StackResourceDrifts":[]}' ]; then
          echo "🔍 Analyzing drifted resources..."
          echo "$DRIFT_DETAILS" | jq -r '.StackResourceDrifts[] | select(.StackResourceDriftStatus != "IN_SYNC") | "  - \(.LogicalResourceId) (\(.ResourceType)): \(.StackResourceDriftStatus)"'
        fi
        
        # Send notification about required manual intervention
        if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
          curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"⚠️ Drift detected in $CDK_STACK_NAME - Manual remediation required\"}" \
            "$SLACK_WEBHOOK_URL" || echo "Failed to send notification"
        fi
        
      else
        echo "✅ No drift detected - infrastructure matches CDK template"
      fi
```

### 2. Git-based autoRedeploy (Separate from Drift)

This demonstrates what autoRedeploy actually does - responds to Git changes:

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: lambda-git-autoredeploy
  namespace: default
  labels:
    example: "06-drift-detection"
    level: "intermediate"
    feature: "git-autoredeploy"
spec:
  stackName: Lambda-GitAutoRedeploy-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: main
  path: ./lambda-example
  
  cdkContext:
    - "environment=development"
    - "functionName=auto-redeploy-demo"
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true    # Monitor for manual changes
    autoRedeploy: true      # Auto-deploy when GIT changes (not drift!)
  
  lifecycleHooks:
    afterGitSync: |
      echo "📂 Git sync check completed for: $CDK_STACK_NAME"
      echo "🔄 Git changes detected: $GIT_CHANGES_DETECTED"
      
      if [ "$GIT_CHANGES_DETECTED" = "true" ]; then
        echo "🚀 autoRedeploy ENABLED - new Git changes will be deployed automatically"
        echo "📝 This responds to source code changes in Git, NOT drift"
      else
        echo "✅ No Git changes detected - stack up to date with repository"
      fi
    
    afterDriftDetection: |
      if [ "$DRIFT_DETECTED" = "true" ]; then
        echo "⚠️  Drift detected, but autoRedeploy does NOT fix this!"
        echo "🔧 Manual remediation required for drift issues"
        echo "📖 See: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html"
      fi
```

### 3. Production Drift Monitoring with Security Focus

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: production-drift-monitoring
  namespace: production
  labels:
    example: "06-drift-detection"
    level: "intermediate"
    environment: "production"
spec:
  stackName: Production-DriftMonitoring-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: git@github.com:your-org/production-infrastructure.git
      ref: v1.2.3  # Use tagged releases for production
  path: ./critical-infrastructure
  
  actions:
    deploy: true
    destroy: false          # Protect production resources
    driftDetection: true    # Essential for compliance
    autoRedeploy: false     # Never auto-redeploy in production
  
  lifecycleHooks:
    afterDriftDetection: |
      echo "🏭 Production drift detection completed for $CDK_STACK_NAME"
      
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "🚨 PRODUCTION ALERT: Unauthorized changes detected!"
        echo "🛑 Manual intervention required immediately"
        
        # Analyze security implications
        DRIFT_DETAILS=$(aws cloudformation describe-stack-resource-drifts \
          --stack-name "$CDK_STACK_NAME" \
          --region "$CDK_STACK_REGION" \
          --output json 2>/dev/null || echo '{"StackResourceDrifts":[]}')
        
        # Check for critical security resources
        SECURITY_DRIFT=$(echo "$DRIFT_DETAILS" | jq -r '.StackResourceDrifts[] | select(.ResourceType | test(".*SecurityGroup.*|.*IAM.*|.*Policy.*|.*Role.*")) | .LogicalResourceId' || echo "")
        
        if [ -n "$SECURITY_DRIFT" ]; then
          echo "🔒 CRITICAL: Security-related resources have drift!"
          echo "🚨 SECURITY INCIDENT - Immediate review required"
          echo "$SECURITY_DRIFT"
          
          # Send critical security alert
          if [ -n "${SECURITY_ALERT_WEBHOOK_URL:-}" ]; then
            curl -X POST -H 'Content-type: application/json' \
              --data "{
                \"alert_level\": \"critical\",
                \"message\": \"SECURITY DRIFT in production stack $CDK_STACK_NAME\",
                \"affected_resources\": \"$SECURITY_DRIFT\",
                \"action_required\": \"immediate_investigation\"
              }" \
              "$SECURITY_ALERT_WEBHOOK_URL"
          fi
        fi
        
        echo ""
        echo "📋 PRODUCTION REMEDIATION PROCESS:"
        echo "   1. Immediately investigate the changes"
        echo "   2. Determine if changes were authorized"
        echo "   3. If unauthorized - revert changes immediately"
        echo "   4. If authorized - update CDK code and redeploy"
        echo "   5. Review access controls and change management"
        echo "   6. Update compliance documentation"
        
      else
        echo "✅ Production infrastructure is compliant - no drift detected"
      fi
```

## Drift Detection vs autoRedeploy - Key Differences

### 🔍 Drift Detection
- **Purpose**: Detect manual changes to AWS resources outside CDK
- **Mechanism**: Uses CloudFormation drift detection APIs
- **Examples**: Someone changes S3 bucket settings in AWS Console
- **Result**: Alerts and metrics, but **NO automatic fixing**
- **Remediation**: Manual process required

### 🔄 autoRedeploy (Git-based)
- **Purpose**: Respond to changes in Git repository source code
- **Mechanism**: Uses `cdk diff` to compare Git vs deployed version
- **Examples**: Developer pushes new CDK code to Git repository
- **Result**: Automatic redeployment of new code
- **Triggered by**: Source code changes, NOT infrastructure drift

## Drift Detection Configuration

### Drift Check Frequency

Configure how often drift detection runs in your Helm values:

```yaml
# values.yaml
operator:
  env:
    driftCheckCron: "*/30 * * * *"  # Every 30 minutes (default)
    # driftCheckCron: "0 */6 * * *" # Every 6 hours
    # driftCheckCron: "0 9 * * 1"   # Every Monday at 9 AM
```

### Manual Drift Detection

```bash
# Force immediate drift detection
kubectl annotate cdktsstack my-stack kubectl.kubernetes.io/restartedAt="$(date)"

# Check drift detection status
kubectl get cdktsstacks -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,LAST-DRIFT:.status.lastDriftCheck,DRIFT:.status.driftDetected
```

### AWS CLI Drift Detection

```bash
# Start drift detection
DRIFT_ID=$(aws cloudformation detect-stack-drift --stack-name MyStack --query 'StackDriftDetectionId' --output text)

# Check drift status  
aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id $DRIFT_ID

# Get detailed drift information
aws cloudformation describe-stack-resource-drifts --stack-name MyStack
```

## Monitoring and Alerting

### Drift Metrics

The operator exposes drift-related Prometheus metrics:

```bash
# Access metrics
kubectl port-forward deployment/awscdk-operator -n awscdk-operator-system 9115:9115
curl localhost:9115/metrics | grep drift

# Example metrics:
# cdktsstack_drift_checks_total - Number of drift checks performed
# cdktsstack_drift_status - Current drift status (0=no drift, 1=drift detected)
# cdktsstack_drifts_detected_total - Total number of drifts detected
```

### Alert Configuration

Set up webhook notifications:

```bash
# Configure webhook URLs in operator deployment
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
                "name": "SLACK_WEBHOOK_URL",
                "value": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
              },
              {
                "name": "SECURITY_ALERT_WEBHOOK_URL",
                "value": "https://your-security-system.com/webhook"
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

### 1. Environment-Based Strategy

```yaml
# Production: Always manual remediation
spec:
  actions:
    driftDetection: true
    autoRedeploy: false    # Never auto-redeploy

# Staging: Monitor with manual control
spec:
  actions:
    driftDetection: true
    autoRedeploy: false    # Evaluate each case

# Development: Monitor but allow flexibility
spec:
  actions:
    driftDetection: true
    autoRedeploy: false    # Still requires manual intervention for drift
```

### 2. Security-First Approach

```bash
# In drift detection hooks, categorize by security impact
case "$RESOURCE_TYPE" in
  *SecurityGroup*|*IAM*|*Policy*|*Role*)
    echo "🚨 CRITICAL: Security resource drift - immediate review required"
    ESCALATION_LEVEL="critical"
    ;;
  *S3*|*DynamoDB*|*RDS*)
    echo "⚠️  WARNING: Data resource drift - careful review needed"  
    ESCALATION_LEVEL="warning"
    ;;
  *)
    echo "ℹ️  INFO: General resource drift detected"
    ESCALATION_LEVEL="info"
    ;;
esac
```

### 3. Compliance Logging

```bash
# Create audit trail for all drift events
log_drift_event() {
  local stack_name=$1
  local drift_status=$2
  
  AUDIT_ENTRY=$(cat << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "event_type": "drift_detection",
  "stack_name": "$stack_name",
  "region": "$CDK_STACK_REGION", 
  "drift_detected": "$drift_status",
  "remediation_action": "manual_required",
  "aws_documentation": "https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html"
}
EOF
)
  
  echo "$AUDIT_ENTRY" >> /var/log/drift-audit.log
}
```

## Manual Remediation Process

When drift is detected, follow this process:

### 1. Investigation
```bash
# Get detailed drift information
aws cloudformation describe-stack-resource-drifts --stack-name MyStack

# Identify what changed
aws cloudformation describe-stack-events --stack-name MyStack
```

### 2. Decision Making
- **If changes were unauthorized**: Revert them in AWS Console/CLI
- **If changes were authorized**: Update CDK code to match changes

### 3. Remediation
```bash
# Option A: Revert manual changes, then redeploy
kubectl annotate cdktsstack my-stack kubectl.kubernetes.io/restartedAt="$(date)"

# Option B: Update CDK code, commit to Git, then redeploy
# (Update your CDK code first, then)
kubectl annotate cdktsstack my-stack kubectl.kubernetes.io/restartedAt="$(date)"
```

## Troubleshooting

### Common Issues

1. **Drift not detected**: Verify CloudFormation stack exists and is in supported state
2. **False positives**: Some AWS services have default values that appear as drift
3. **Permission errors**: Ensure `cloudformation:DetectStackDrift` permissions

### Debug Commands

```bash
# Check operator logs for drift detection
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -i drift

# View current drift status
kubectl get cdktsstacks -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.driftDetected}{"\t"}{.status.lastDriftCheck}{"\n"}{end}'

# Reset drift detection if stuck
kubectl patch cdktsstack my-stack --subresource=status --type='merge' \
  -p='{"status":{"phase":"","message":"Reset for drift recheck"}}'
```

## Security Considerations

- **IAM Permissions**: Ensure proper CloudFormation drift detection permissions
- **Change Control**: All drift remediations should follow change management process
- **Audit Trail**: Maintain comprehensive logs of drift detections and remediations
- **Access Reviews**: Regularly review who can make manual changes to AWS resources

## Next Steps

- [07 - Git Integration](07-git-integration.md) - Understand Git-based autoRedeploy
- [08 - Production Ready](08-production-ready.md) - Complete production setup
- [Troubleshooting Guide](../troubleshooting.md) - Debug drift detection issues 