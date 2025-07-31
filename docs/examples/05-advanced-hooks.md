# 05 - Advanced Hooks

**Level**: Intermediate  
**Purpose**: Complex automation with validations, testing, and backup strategies

## Overview

This example demonstrates advanced lifecycle hook patterns including complex automation, multi-step validations, external integrations, and sophisticated error handling. You'll learn to build production-grade automation workflows.

## What This Example Creates

- VPC with comprehensive validation and testing
- Automated security compliance checking
- Complete backup and recovery procedures
- Integration with monitoring and alerting systems

## Prerequisites

1. Completed examples [01-04](README.md#learning-path)
2. Advanced shell scripting knowledge
3. Understanding of AWS CLI and CloudFormation
4. Optional: External monitoring/notification systems

## Advanced Features Demonstrated

- **Multi-step validation processes**: Comprehensive pre-deployment checks
- **External API integrations**: Integration with monitoring and notification systems
- **Conditional execution**: Environment-based logic and decision making
- **Automated testing**: Post-deployment verification and testing
- **Error handling**: Robust error recovery and rollback procedures

## Complete Advanced Example

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: vpc-production-grade
  namespace: default
  labels:
    example: "05-advanced-hooks"
    level: "intermediate"
    environment: "production"
spec:
  stackName: MyVPC-Production-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/cdk-examples.git
      ref: v1.2.0  # Use tagged releases for production
  path: ./vpc-example
  
  cdkContext:
    - "environment=production"
    - "vpcCidr=10.0.0.0/16"
    - "enableNatGateway=true"
    - "enableFlowLogs=true"
  
  actions:
    deploy: true
    destroy: false  # Protect production VPC
    driftDetection: true
    autoRedeploy: false
  
  lifecycleHooks:
    beforeDeploy: |
      #!/bin/bash
      set -euo pipefail  # Strict error handling
      
      echo "🔍 Starting advanced pre-deployment validation for $CDK_STACK_NAME"
      
      # ===============================================================================
      # STEP 1: Environment Validation
      # ===============================================================================
      echo "📋 Step 1: Environment Validation"
      
      # Validate AWS credentials and permissions
      echo "🔐 Validating AWS credentials..."
      CALLER_IDENTITY=$(aws sts get-caller-identity --output json)
      ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
      USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
      
      echo "✅ Authenticated as: $USER_ARN"
      echo "✅ Account ID: $ACCOUNT_ID"
      
      # Check required IAM permissions
      echo "🔑 Validating IAM permissions..."
      REQUIRED_PERMISSIONS=(
        "ec2:CreateVpc"
        "ec2:CreateSubnet"
        "ec2:CreateRouteTable"
        "ec2:CreateInternetGateway"
        "ec2:CreateNatGateway"
      )
      
      for permission in "${REQUIRED_PERMISSIONS[@]}"; do
        if aws iam simulate-principal-policy \
          --policy-source-arn "$USER_ARN" \
          --action-names "$permission" \
          --resource-arns "*" \
          --query 'EvaluationResults[0].EvalDecision' \
          --output text | grep -q "allowed"; then
          echo "✅ Permission: $permission"
        else
          echo "❌ Missing permission: $permission"
          exit 1
        fi
      done
      
      # ===============================================================================
      # STEP 2: Resource Availability Check
      # ===============================================================================
      echo "📋 Step 2: Resource Availability Check"
      
      # Check VPC limits
      VPC_LIMIT=$(aws ec2 describe-account-attributes \
        --attribute-names max-vpcs \
        --query 'AccountAttributes[0].AttributeValues[0].AttributeValue' \
        --output text)
      
      VPC_COUNT=$(aws ec2 describe-vpcs \
        --query 'length(Vpcs[])' \
        --output text)
      
      echo "📊 VPC Usage: $VPC_COUNT / $VPC_LIMIT"
      
      if [ "$VPC_COUNT" -ge "$VPC_LIMIT" ]; then
        echo "❌ VPC limit exceeded. Current: $VPC_COUNT, Limit: $VPC_LIMIT"
        exit 1
      fi
      
      # ===============================================================================
      # STEP 3: Network Validation
      # ===============================================================================
      echo "📋 Step 3: Network Validation"
      
      # Extract VPC CIDR from context
      VPC_CIDR=$(kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.spec.cdkContext}' | \
        grep -o 'vpcCidr=[^"]*' | cut -d'=' -f2 || echo "10.0.0.0/16")
      
      echo "🌐 Planned VPC CIDR: $VPC_CIDR"
      
      # Check for CIDR conflicts with existing VPCs
      EXISTING_CIDRS=$(aws ec2 describe-vpcs \
        --query 'Vpcs[].CidrBlock' \
        --output text)
      
      echo "🔍 Checking for CIDR conflicts..."
      for existing_cidr in $EXISTING_CIDRS; do
        if [ "$existing_cidr" = "$VPC_CIDR" ]; then
          echo "❌ CIDR conflict detected: $VPC_CIDR already in use"
          exit 1
        fi
      done
      
      echo "✅ No CIDR conflicts detected"
      
      # ===============================================================================
      # STEP 4: Security Compliance Check
      # ===============================================================================
      echo "📋 Step 4: Security Compliance Check"
      
      # Validate security requirements
      echo "🔒 Validating security compliance..."
      
      # Check if this is a production environment
      ENVIRONMENT=$(kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.metadata.labels.environment}' || echo "unknown")
      
      if [ "$ENVIRONMENT" = "production" ]; then
        echo "🏭 Production environment detected - enforcing strict security"
        
        # Ensure flow logs are enabled
        if ! kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.spec.cdkContext}' | grep -q "enableFlowLogs=true"; then
          echo "❌ Flow logs must be enabled for production VPCs"
          exit 1
        fi
        
        # Ensure NAT gateways for private subnets
        if ! kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.spec.cdkContext}' | grep -q "enableNatGateway=true"; then
          echo "❌ NAT gateways must be enabled for production VPCs"
          exit 1
        fi
        
        echo "✅ Security compliance checks passed"
      fi
      
      # ===============================================================================
      # STEP 5: External System Integration
      # ===============================================================================
      echo "📋 Step 5: External System Integration"
      
      # Optional: Notify monitoring system
      if [ -n "${MONITORING_WEBHOOK_URL:-}" ]; then
        echo "📡 Notifying monitoring system..."
        curl -X POST -H 'Content-type: application/json' \
          --data "{
            \"event\": \"deployment_start\",
            \"stack\": \"$CDK_STACK_NAME\",
            \"environment\": \"$ENVIRONMENT\",
            \"region\": \"$CDK_STACK_REGION\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
          }" \
          "$MONITORING_WEBHOOK_URL" || echo "⚠️  Failed to notify monitoring system"
      fi
      
      # ===============================================================================
      # COMPLETION
      # ===============================================================================
      echo "🎉 All pre-deployment validations completed successfully!"
      echo "📅 Validation completed at: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"
    
    afterDeploy: |
      #!/bin/bash
      set -euo pipefail
      
      echo "🧪 Starting comprehensive post-deployment testing for $CDK_STACK_NAME"
      
      # ===============================================================================
      # STEP 1: Stack Output Validation
      # ===============================================================================
      echo "📋 Step 1: Stack Output Validation"
      
      # Get all stack outputs
      STACK_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$CDK_STACK_NAME" \
        --region "$CDK_STACK_REGION" \
        --query 'Stacks[0].Outputs' \
        --output json)
      
      echo "📊 Stack Outputs:"
      echo "$STACK_OUTPUTS" | jq '.'
      
      # Extract key infrastructure components
      VPC_ID=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="VpcId") | .OutputValue' || echo "")
      INTERNET_GATEWAY_ID=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="InternetGatewayId") | .OutputValue' || echo "")
      
      if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "null" ]; then
        echo "❌ VPC ID not found in stack outputs"
        exit 1
      fi
      
      echo "✅ VPC ID: $VPC_ID"
      
      # ===============================================================================
      # STEP 2: Network Connectivity Tests
      # ===============================================================================
      echo "📋 Step 2: Network Connectivity Tests"
      
      # Test VPC configuration
      echo "🌐 Testing VPC configuration..."
      
      VPC_INFO=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json)
      VPC_STATE=$(echo "$VPC_INFO" | jq -r '.Vpcs[0].State')
      VPC_CIDR=$(echo "$VPC_INFO" | jq -r '.Vpcs[0].CidrBlock')
      
      if [ "$VPC_STATE" != "available" ]; then
        echo "❌ VPC is not in available state: $VPC_STATE"
        exit 1
      fi
      
      echo "✅ VPC State: $VPC_STATE"
      echo "✅ VPC CIDR: $VPC_CIDR"
      
      # Test subnet configuration
      echo "🏠 Testing subnet configuration..."
      
      SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,CidrBlock:CidrBlock,State:State}' \
        --output json)
      
      SUBNET_COUNT=$(echo "$SUBNETS" | jq 'length')
      echo "📊 Found $SUBNET_COUNT subnets"
      
      if [ "$SUBNET_COUNT" -eq 0 ]; then
        echo "❌ No subnets found in VPC"
        exit 1
      fi
      
      # Validate each subnet
      echo "$SUBNETS" | jq -c '.[]' | while read -r subnet; do
        SUBNET_ID=$(echo "$subnet" | jq -r '.SubnetId')
        SUBNET_STATE=$(echo "$subnet" | jq -r '.State')
        SUBNET_AZ=$(echo "$subnet" | jq -r '.AvailabilityZone')
        
        if [ "$SUBNET_STATE" != "available" ]; then
          echo "❌ Subnet $SUBNET_ID in $SUBNET_AZ is not available: $SUBNET_STATE"
          exit 1
        fi
        
        echo "✅ Subnet $SUBNET_ID in $SUBNET_AZ: $SUBNET_STATE"
      done
      
      # ===============================================================================
      # STEP 3: Security Group Validation
      # ===============================================================================
      echo "📋 Step 3: Security Group Validation"
      
      # Check default security group rules
      DEFAULT_SG=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
      
      if [ -n "$DEFAULT_SG" ] && [ "$DEFAULT_SG" != "None" ]; then
        echo "🔒 Validating default security group: $DEFAULT_SG"
        
        # Check for overly permissive rules
        INGRESS_RULES=$(aws ec2 describe-security-groups \
          --group-ids "$DEFAULT_SG" \
          --query 'SecurityGroups[0].IpPermissions' \
          --output json)
        
        # Check for 0.0.0.0/0 rules
        if echo "$INGRESS_RULES" | jq -e '.[] | select(.IpRanges[]?.CidrIp == "0.0.0.0/0")' > /dev/null; then
          echo "⚠️  Warning: Default security group has 0.0.0.0/0 ingress rules"
        else
          echo "✅ Default security group rules are restrictive"
        fi
      fi
      
      # ===============================================================================
      # STEP 4: Flow Logs Validation (if enabled)
      # ===============================================================================
      if kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.spec.cdkContext}' | grep -q "enableFlowLogs=true"; then
        echo "📋 Step 4: Flow Logs Validation"
        
        # Check if flow logs are configured
        FLOW_LOGS=$(aws ec2 describe-flow-logs \
          --filter "Name=resource-id,Values=$VPC_ID" \
          --query 'FlowLogs[].FlowLogStatus' \
          --output text)
        
        if [ -n "$FLOW_LOGS" ]; then
          echo "✅ VPC Flow Logs are configured: $FLOW_LOGS"
        else
          echo "⚠️  Warning: VPC Flow Logs not found (may still be creating)"
        fi
      fi
      
      # ===============================================================================
      # STEP 5: Performance and Health Metrics
      # ===============================================================================
      echo "📋 Step 5: Performance and Health Metrics"
      
      # Record deployment metrics
      DEPLOYMENT_END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      echo "📊 Deployment completed at: $DEPLOYMENT_END_TIME"
      
      # Optional: Send metrics to monitoring system
      if [ -n "${MONITORING_WEBHOOK_URL:-}" ]; then
        echo "📡 Sending deployment metrics..."
        curl -X POST -H 'Content-type: application/json' \
          --data "{
            \"event\": \"deployment_success\",
            \"stack\": \"$CDK_STACK_NAME\",
            \"vpc_id\": \"$VPC_ID\",
            \"subnet_count\": $SUBNET_COUNT,
            \"region\": \"$CDK_STACK_REGION\",
            \"timestamp\": \"$DEPLOYMENT_END_TIME\",
            \"vpc_cidr\": \"$VPC_CIDR\"
          }" \
          "$MONITORING_WEBHOOK_URL" || echo "⚠️  Failed to send metrics"
      fi
      
      echo "🎉 All post-deployment tests completed successfully!"
    
    beforeDestroy: |
      #!/bin/bash
      set -euo pipefail
      
      echo "🛡️  Starting advanced pre-destruction safety checks for $CDK_STACK_NAME"
      
      # ===============================================================================
      # STEP 1: Dependency Check
      # ===============================================================================
      echo "📋 Step 1: Dependency Check"
      
      # Get VPC ID from stack
      VPC_ID=$(aws cloudformation describe-stacks \
        --stack-name "$CDK_STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
        --output text)
      
      if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        echo "🏠 Checking VPC dependencies for: $VPC_ID"
        
        # Check for EC2 instances
        INSTANCES=$(aws ec2 describe-instances \
          --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped" \
          --query 'Reservations[].Instances[].InstanceId' \
          --output text)
        
        if [ -n "$INSTANCES" ]; then
          echo "❌ Cannot destroy VPC - EC2 instances still exist: $INSTANCES"
          exit 1
        fi
        
        # Check for RDS instances
        RDS_INSTANCES=$(aws rds describe-db-instances \
          --query "DBInstances[?DBSubnetGroup.VpcId=='$VPC_ID'].DBInstanceIdentifier" \
          --output text)
        
        if [ -n "$RDS_INSTANCES" ]; then
          echo "❌ Cannot destroy VPC - RDS instances still exist: $RDS_INSTANCES"
          exit 1
        fi
        
        echo "✅ No blocking dependencies found"
      fi
      
      # ===============================================================================
      # STEP 2: Backup Critical Data
      # ===============================================================================
      echo "📋 Step 2: Backup Critical Data"
      
      # Create backup of VPC configuration
      BACKUP_DIR="/tmp/vpc-backup-$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$BACKUP_DIR"
      
      if [ -n "$VPC_ID" ]; then
        # Backup VPC configuration
        aws ec2 describe-vpcs --vpc-ids "$VPC_ID" > "$BACKUP_DIR/vpc-config.json"
        
        # Backup route tables
        aws ec2 describe-route-tables \
          --filters "Name=vpc-id,Values=$VPC_ID" > "$BACKUP_DIR/route-tables.json"
        
        # Backup security groups
        aws ec2 describe-security-groups \
          --filters "Name=vpc-id,Values=$VPC_ID" > "$BACKUP_DIR/security-groups.json"
        
        echo "✅ VPC configuration backed up to: $BACKUP_DIR"
      fi
      
      echo "🛡️  Pre-destruction safety checks completed"
    
    afterDriftDetection: |
      #!/bin/bash
      set -euo pipefail
      
      echo "🔍 Processing drift detection results for $CDK_STACK_NAME"
      
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "🚨 DRIFT DETECTED - Taking automated response actions"
        
        # Get detailed drift information
        DRIFT_INFO=$(aws cloudformation describe-stack-resource-drifts \
          --stack-name "$CDK_STACK_NAME" \
          --region "$CDK_STACK_REGION" \
          --output json)
        
        echo "📊 Drift Details:"
        echo "$DRIFT_INFO" | jq '.StackResourceDrifts[] | {ResourceType: .ResourceType, LogicalResourceId: .LogicalResourceId, ResourceStatusReason: .ResourceStatusReason}'
        
        # Categorize drift severity
        CRITICAL_DRIFTS=$(echo "$DRIFT_INFO" | jq -r '.StackResourceDrifts[] | select(.ResourceType | contains("SecurityGroup") or contains("IAM")) | .LogicalResourceId')
        
        if [ -n "$CRITICAL_DRIFTS" ]; then
          echo "🚨 CRITICAL DRIFT DETECTED in security-related resources:"
          echo "$CRITICAL_DRIFTS"
          
          # Send high-priority alert
          if [ -n "${CRITICAL_ALERT_WEBHOOK_URL:-}" ]; then
            curl -X POST -H 'Content-type: application/json' \
              --data "{
                \"alert_level\": \"critical\",
                \"message\": \"Critical drift detected in $CDK_STACK_NAME\",
                \"drifted_resources\": \"$CRITICAL_DRIFTS\",
                \"region\": \"$CDK_STACK_REGION\",
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
              }" \
              "$CRITICAL_ALERT_WEBHOOK_URL"
          fi
        else
          echo "ℹ️  Non-critical drift detected - standard alerting"
        fi
        
        # Log drift for compliance
        echo "📝 Logging drift event for compliance audit"
        
      else
        echo "✅ No drift detected - infrastructure is compliant"
      fi
```

## Advanced Patterns Explained

### 1. Multi-Step Validation Framework

The example demonstrates a structured approach to validation:

```bash
# Template for validation steps
echo "📋 Step X: Validation Name"
# Validation logic here
if [ validation_failed ]; then
  echo "❌ Validation failed: reason"
  exit 1
fi
echo "✅ Validation passed"
```

### 2. External API Integration

```bash
# Robust API calls with error handling
if [ -n "${API_ENDPOINT:-}" ]; then
  RESPONSE=$(curl -s -w "%{http_code}" -X POST \
    -H 'Content-type: application/json' \
    --data "$PAYLOAD" \
    "$API_ENDPOINT" || echo "000")
  
  HTTP_CODE="${RESPONSE: -3}"
  BODY="${RESPONSE%???}"
  
  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "✅ API call successful"
  else
    echo "⚠️  API call failed: HTTP $HTTP_CODE"
  fi
fi
```

### 3. Resource Dependency Checking

```bash
# Check for blocking dependencies before destruction
check_dependencies() {
  local vpc_id=$1
  local blocking_resources=()
  
  # Check EC2 instances
  local instances=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$vpc_id" \
    --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' \
    --output text)
  
  if [ -n "$instances" ]; then
    blocking_resources+=("EC2 instances: $instances")
  fi
  
  # Return result
  if [ ${#blocking_resources[@]} -gt 0 ]; then
    printf '%s\n' "${blocking_resources[@]}"
    return 1
  fi
  
  return 0
}
```

## Environment-Specific Configuration

Create environment-specific versions by varying the labels and context:

```yaml
# Production
metadata:
  labels:
    environment: "production"
spec:
  cdkContext:
    - "environment=production"
    - "enableFlowLogs=true"
    - "enableNatGateway=true"

# Development
metadata:
  labels:
    environment: "development"
spec:
  cdkContext:
    - "environment=development"
    - "enableFlowLogs=false"
    - "enableNatGateway=false"
```

## Monitoring and Alerting

### Hook Execution Metrics

```bash
# Track hook execution time
HOOK_START=$(date +%s)
# ... hook logic ...
HOOK_END=$(date +%s)
HOOK_DURATION=$((HOOK_END - HOOK_START))

echo "⏱️  Hook execution time: ${HOOK_DURATION}s"
```

### Alert Severity Levels

```bash
send_alert() {
  local level=$1
  local message=$2
  local webhook_var="ALERT_${level^^}_WEBHOOK_URL"
  local webhook_url="${!webhook_var:-}"
  
  if [ -n "$webhook_url" ]; then
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"level\":\"$level\", \"message\":\"$message\"}" \
      "$webhook_url"
  fi
}

# Usage
send_alert "critical" "Security drift detected"
send_alert "warning" "Performance degradation detected"
```

## Testing Hooks

### Local Testing

```bash
# Create test environment
export CDK_STACK_NAME="test-vpc-stack"
export CDK_STACK_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"

# Test individual hook sections
bash -x hook-script.sh
```

### Integration Testing

```bash
# Deploy test stack with hooks
kubectl apply -f test-stack-with-hooks.yaml

# Monitor execution
kubectl logs -n awscdk-operator-system deployment/awscdk-operator -f | grep hook
```

## Next Steps

- [06 - Drift Detection](06-drift-detection.md) - Advanced drift monitoring
- [08 - Production Ready](08-production-ready.md) - Complete production setup
- [Troubleshooting Guide](../troubleshooting.md) - Debug hook issues 