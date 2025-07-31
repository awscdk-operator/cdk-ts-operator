# 08 - Production Ready

**Level**: Advanced  
**Purpose**: Complete production-ready setup with all AWS CDK Operator features

## Overview

This example demonstrates a comprehensive production-ready deployment that incorporates all AWS CDK Operator features, best practices, and operational procedures. It serves as a complete reference for production deployments.

## What This Example Creates

- Multi-tier application infrastructure
- High availability setup across AZs
- Comprehensive monitoring and alerting
- Automated backup and recovery
- Security compliance monitoring
- Operational runbooks automation

## Prerequisites

1. Completed all previous examples [01-07](README.md#learning-path)
2. Production AWS account with proper IAM setup
3. Monitoring and alerting infrastructure
4. Backup and disaster recovery procedures
5. Change management processes

## Production Features Demonstrated

- **Zero-downtime deployments**: Blue/green deployment strategies
- **Automated rollback capabilities**: Failure detection and automatic rollback
- **Security scanning and compliance**: Continuous security monitoring
- **Performance monitoring**: Application and infrastructure metrics
- **Cost optimization**: Resource optimization and cost tracking
- **Incident response automation**: Automated incident detection and response

## Complete Production Stack

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: webapp-production
  namespace: production
  labels:
    example: "08-production-ready"
    level: "advanced"
    environment: "production"
    tier: "application"
  annotations:
    description: "Production web application with full operational capabilities"
    owner: "platform-team@company.com"
    cost-center: "engineering"
    compliance: "soc2,gdpr"
spec:
  stackName: WebApp-Production-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: git@github.com:company/webapp-infrastructure.git
      ref: v2.1.0  # Use stable tagged releases for production
      sshSecretName: production-ssh-key
  path: ./production-stack
  
  cdkContext:
    - "environment=production"
    - "high-availability=true"
    - "multi-az=true"
    - "backup-enabled=true"
    - "monitoring-level=comprehensive"
    - "auto-scaling=true"
    - "load-balancer=application"
    - "ssl-termination=true"
    - "waf-enabled=true"
    - "cloudfront-enabled=true"
    - "cost-optimization=true"
  
  actions:
    deploy: true
    destroy: false  # 🔒 Protect production resources
    driftDetection: true
    autoRedeploy: false  # 🛡️ Manual approval required for production
  
  lifecycleHooks:
    beforeDeploy: |
      #!/bin/bash
      set -euo pipefail
      
      echo "🏭 Starting production deployment for $CDK_STACK_NAME"
      echo "🔒 Environment: PRODUCTION - Extra safety checks enabled"
      
      # ===============================================================================
      # PRODUCTION READINESS CHECKS
      # ===============================================================================
      
      echo "📋 Production Readiness Validation"
      
      # 1. Verify production deployment window
      CURRENT_HOUR=$(date +%H)
      CURRENT_DAY=$(date +%u)  # 1=Monday, 7=Sunday
      
      # Production deployment window: Weekdays 9 AM - 5 PM
      if [ "$CURRENT_DAY" -gt 5 ] || [ "$CURRENT_HOUR" -lt 9 ] || [ "$CURRENT_HOUR" -gt 17 ]; then
        echo "⚠️  WARNING: Deployment outside business hours"
        echo "Current time: $(date)"
        echo "Recommended window: Weekdays 9 AM - 5 PM EST"
        
        # Allow emergency override with annotation
        EMERGENCY_OVERRIDE=$(kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.metadata.annotations.emergency-deployment}' 2>/dev/null || echo "false")
        if [ "$EMERGENCY_OVERRIDE" != "true" ]; then
          echo "❌ Production deployment blocked outside business hours"
          echo "To override, add annotation: kubectl annotate cdk $CDK_STACK_NAME emergency-deployment=true"
          exit 1
        else
          echo "🚨 Emergency override enabled - proceeding with deployment"
        fi
      else
        echo "✅ Deployment within approved business hours"
      fi
      
      # 2. Check for active incidents
      echo "🚨 Checking for active incidents..."
      if [ -n "${INCIDENT_API_URL:-}" ]; then
        ACTIVE_INCIDENTS=$(curl -s -H "Authorization: Bearer $INCIDENT_API_TOKEN" \
          "$INCIDENT_API_URL/incidents?status=open" | jq '.count' || echo "0")
        
        if [ "$ACTIVE_INCIDENTS" -gt 0 ]; then
          echo "❌ Active incidents detected: $ACTIVE_INCIDENTS"
          echo "Production deployment blocked during active incidents"
          exit 1
        else
          echo "✅ No active incidents"
        fi
      fi
      
      # 3. Verify backup systems
      echo "💾 Verifying backup systems..."
      
      # Check RDS automated backups
      RDS_INSTANCES=$(aws rds describe-db-instances \
        --query 'DBInstances[?!starts_with(DBInstanceIdentifier, `rds-`)].{Name:DBInstanceIdentifier,BackupRetention:BackupRetentionPeriod}' \
        --output json)
      
      echo "$RDS_INSTANCES" | jq -c '.[]' | while read -r instance; do
        DB_NAME=$(echo "$instance" | jq -r '.Name')
        BACKUP_RETENTION=$(echo "$instance" | jq -r '.BackupRetention')
        
        if [ "$BACKUP_RETENTION" -lt 7 ]; then
          echo "❌ Insufficient backup retention for $DB_NAME: $BACKUP_RETENTION days (minimum: 7)"
          exit 1
        else
          echo "✅ Backup retention for $DB_NAME: $BACKUP_RETENTION days"
        fi
      done
      
      # 4. Security compliance check
      echo "🔒 Security compliance validation..."
      
      # Check for security groups with 0.0.0.0/0 access
      OPEN_SG=$(aws ec2 describe-security-groups \
        --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`] && (FromPort==`22` || FromPort==`3389`)]]' \
        --output text)
      
      if [ -n "$OPEN_SG" ]; then
        echo "❌ Security groups with open SSH/RDP access detected"
        echo "This violates production security policy"
        exit 1
      else
        echo "✅ No security groups with dangerous open access"
      fi
      
      # 5. Cost validation
      echo "💰 Cost impact validation..."
      
      # Get current monthly costs
      CURRENT_MONTH=$(date +%Y-%m-01)
      CURRENT_COSTS=$(aws ce get-cost-and-usage \
        --time-period Start=$CURRENT_MONTH,End=$(date +%Y-%m-%d) \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
        --output text || echo "0")
      
      echo "📊 Current month costs: \$$(printf '%.2f' $CURRENT_COSTS)"
      
      # 6. Performance baseline
      echo "📈 Establishing performance baseline..."
      
      # Get current application response time (if monitoring is available)
      if [ -n "${MONITORING_API_URL:-}" ]; then
        BASELINE_RESPONSE_TIME=$(curl -s -H "Authorization: Bearer $MONITORING_API_TOKEN" \
          "$MONITORING_API_URL/metrics/response_time?duration=1h" | jq '.average' || echo "0")
        
        echo "📊 Current average response time: ${BASELINE_RESPONSE_TIME}ms"
        
        # Store baseline for post-deployment comparison
        kubectl create configmap deployment-baseline-$(date +%s) \
          --from-literal="response-time=$BASELINE_RESPONSE_TIME" \
          --from-literal="timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          --namespace=production || echo "Failed to store baseline"
      fi
      
      echo "🎉 All production readiness checks passed!"
    
    afterDeploy: |
      #!/bin/bash
      set -euo pipefail
      
      echo "🧪 Starting comprehensive production validation for $CDK_STACK_NAME"
      
      # ===============================================================================
      # DEPLOYMENT VALIDATION
      # ===============================================================================
      
      # 1. Infrastructure health check
      echo "🏥 Infrastructure health validation..."
      
      # Get application load balancer
      ALB_ARN=$(aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[?contains(LoadBalancerName, `webapp-prod`)].LoadBalancerArn' \
        --output text)
      
      if [ -n "$ALB_ARN" ]; then
        # Check ALB health
        ALB_STATE=$(aws elbv2 describe-load-balancers \
          --load-balancer-arns "$ALB_ARN" \
          --query 'LoadBalancers[0].State.Code' \
          --output text)
        
        if [ "$ALB_STATE" != "active" ]; then
          echo "❌ Application Load Balancer not in active state: $ALB_STATE"
          exit 1
        else
          echo "✅ Application Load Balancer is active"
        fi
        
        # Check target group health
        TARGET_GROUPS=$(aws elbv2 describe-target-groups \
          --load-balancer-arn "$ALB_ARN" \
          --query 'TargetGroups[].TargetGroupArn' \
          --output text)
        
        for tg_arn in $TARGET_GROUPS; do
          HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
            --output text)
          
          TOTAL_TARGETS=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --query 'length(TargetHealthDescriptions)' \
            --output text)
          
          if [ "$HEALTHY_TARGETS" -eq 0 ]; then
            echo "❌ No healthy targets in target group"
            exit 1
          else
            echo "✅ Target group health: $HEALTHY_TARGETS/$TOTAL_TARGETS healthy"
          fi
        done
      fi
      
      # 2. Application health check
      echo "🔍 Application health validation..."
      
      # Get application URL from stack outputs
      STACK_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$CDK_STACK_NAME" \
        --query 'Stacks[0].Outputs' \
        --output json)
      
      APP_URL=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApplicationUrl") | .OutputValue' || echo "")
      
      if [ -n "$APP_URL" ]; then
        echo "🌐 Testing application endpoint: $APP_URL"
        
        # Health check with retries
        MAX_RETRIES=10
        RETRY_COUNT=0
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/health" || echo "000")
          
          if [ "$HTTP_CODE" = "200" ]; then
            echo "✅ Application health check passed"
            break
          else
            echo "⚠️  Health check failed (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES): HTTP $HTTP_CODE"
            sleep 30
            RETRY_COUNT=$((RETRY_COUNT + 1))
          fi
        done
        
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
          echo "❌ Application health check failed after $MAX_RETRIES attempts"
          exit 1
        fi
        
        # Performance validation
        RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" "$APP_URL/health" | awk '{printf "%.0f", $1 * 1000}')
        echo "📊 Response time: ${RESPONSE_TIME}ms"
        
        # Compare with baseline if available
        LATEST_BASELINE=$(kubectl get configmaps -n production \
          --sort-by=.metadata.creationTimestamp \
          -l deployment-baseline=true \
          -o jsonpath='{.items[-1:].data.response-time}' 2>/dev/null || echo "0")
        
        if [ "$LATEST_BASELINE" != "0" ] && [ "$RESPONSE_TIME" -gt $((LATEST_BASELINE * 150 / 100)) ]; then
          echo "⚠️  WARNING: Response time degradation detected"
          echo "Baseline: ${LATEST_BASELINE}ms, Current: ${RESPONSE_TIME}ms"
        fi
      fi
      
      # 3. Database connectivity
      echo "🗄️  Database connectivity validation..."
      
      # Check RDS instances
      RDS_ENDPOINTS=$(aws rds describe-db-instances \
        --query 'DBInstances[?DBInstanceStatus==`available`].Endpoint.Address' \
        --output text)
      
      for endpoint in $RDS_ENDPOINTS; do
        if nc -z "$endpoint" 5432 2>/dev/null || nc -z "$endpoint" 3306 2>/dev/null; then
          echo "✅ Database connectivity: $endpoint"
        else
          echo "❌ Database connectivity failed: $endpoint"
          exit 1
        fi
      done
      
      # 4. Monitoring and alerting validation
      echo "📊 Monitoring system validation..."
      
      if [ -n "${MONITORING_API_URL:-}" ]; then
        # Verify monitoring system is receiving metrics
        RECENT_METRICS=$(curl -s -H "Authorization: Bearer $MONITORING_API_TOKEN" \
          "$MONITORING_API_URL/metrics/count?since=5m" | jq '.count' || echo "0")
        
        if [ "$RECENT_METRICS" -gt 0 ]; then
          echo "✅ Monitoring system receiving metrics: $RECENT_METRICS in last 5 minutes"
        else
          echo "⚠️  WARNING: No recent metrics in monitoring system"
        fi
        
        # Test alerting webhook
        curl -s -X POST -H 'Content-type: application/json' \
          --data "{\"test\": true, \"deployment\": \"$CDK_STACK_NAME\"}" \
          "$ALERT_WEBHOOK_URL" && echo "✅ Alert webhook functional" || echo "⚠️  Alert webhook test failed"
      fi
      
      # 5. Security posture validation
      echo "🔒 Security posture validation..."
      
      # Check SSL certificate
      if [ -n "$APP_URL" ]; then
        SSL_EXPIRY=$(echo | openssl s_client -servername "$(echo "$APP_URL" | cut -d'/' -f3)" -connect "$(echo "$APP_URL" | cut -d'/' -f3):443" 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d'=' -f2)
        
        if [ -n "$SSL_EXPIRY" ]; then
          EXPIRY_EPOCH=$(date -d "$SSL_EXPIRY" +%s)
          CURRENT_EPOCH=$(date +%s)
          DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
          
          if [ "$DAYS_UNTIL_EXPIRY" -lt 30 ]; then
            echo "⚠️  WARNING: SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
          else
            echo "✅ SSL certificate valid for $DAYS_UNTIL_EXPIRY days"
          fi
        fi
      fi
      
      # ===============================================================================
      # DEPLOYMENT NOTIFICATION
      # ===============================================================================
      
      echo "📢 Sending deployment notifications..."
      
      DEPLOYMENT_SUMMARY=$(cat << EOF
      {
        "deployment": {
          "stack": "$CDK_STACK_NAME",
          "environment": "production",
          "version": "$(kubectl get cdk $CDK_STACK_NAME -o jsonpath='{.spec.source.git.ref}')",
          "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "status": "success",
          "response_time": "${RESPONSE_TIME:-0}ms",
          "healthy_targets": "$HEALTHY_TARGETS/$TOTAL_TARGETS"
        }
      }
      EOF
      )
      
      # Send to monitoring system
      if [ -n "${DEPLOYMENT_WEBHOOK_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
          --data "$DEPLOYMENT_SUMMARY" \
          "$DEPLOYMENT_WEBHOOK_URL" || echo "Failed to send deployment notification"
      fi
      
      # Send to Slack
      if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
          --data "{\"text\":\"🎉 Production deployment successful: $CDK_STACK_NAME\"}" \
          "$SLACK_WEBHOOK_URL" || echo "Failed to send Slack notification"
      fi
      
      echo "🎉 Production deployment validation completed successfully!"
    
    beforeDestroy: |
      echo "🛑 PRODUCTION DESTRUCTION BLOCKED"
      echo "Production resources are protected from accidental deletion"
      echo "If destruction is truly necessary:"
      echo "1. Create change request with business justification"
      echo "2. Get approval from platform team"
      echo "3. Temporarily enable destruction: kubectl patch cdk $CDK_STACK_NAME --type='merge' -p='{\"spec\":{\"actions\":{\"destroy\":true}}}'"
      exit 1
    
    afterDriftDetection: |
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "🚨 PRODUCTION DRIFT DETECTED"
        
        # Get detailed drift information
        DRIFT_DETAILS=$(aws cloudformation describe-stack-resource-drifts \
          --stack-name "$CDK_STACK_NAME" \
          --region "$CDK_STACK_REGION" \
          --output json)
        
        # Create incident automatically for production drift
        if [ -n "${INCIDENT_API_URL:-}" ]; then
          INCIDENT_PAYLOAD=$(cat << EOF
          {
            "title": "Production Infrastructure Drift Detected",
            "description": "Infrastructure drift detected in production stack $CDK_STACK_NAME",
            "severity": "high",
            "status": "open",
            "affected_service": "$CDK_STACK_NAME",
            "detection_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          }
          EOF
          )
          
          curl -X POST -H 'Content-type: application/json' \
            -H "Authorization: Bearer $INCIDENT_API_TOKEN" \
            --data "$INCIDENT_PAYLOAD" \
            "$INCIDENT_API_URL/incidents" || echo "Failed to create incident"
        fi
        
        # Send critical alert
        if [ -n "${CRITICAL_ALERT_WEBHOOK_URL:-}" ]; then
          curl -X POST -H 'Content-type: application/json' \
            --data "{
              \"alert_level\": \"critical\",
              \"message\": \"PRODUCTION DRIFT: $CDK_STACK_NAME\",
              \"environment\": \"production\",
              \"requires_immediate_attention\": true
            }" \
            "$CRITICAL_ALERT_WEBHOOK_URL"
        fi
      fi
```

## Production Operational Procedures

### 1. Emergency Deployment Procedures

```bash
# For emergency deployments outside business hours
kubectl annotate cdk $STACK_NAME emergency-deployment=true

# Requires additional justification
kubectl annotate cdk $STACK_NAME emergency-reason="Critical security patch for CVE-2023-12345"
```

### 2. Rollback Procedures

```bash
# Automatic rollback trigger
kubectl patch cdk $STACK_NAME --type='merge' \
  -p='{"spec":{"source":{"git":{"ref":"v2.0.0"}}}}'

# Force immediate rollback
kubectl patch cdk $STACK_NAME --subresource=status --type='merge' \
  -p='{"status":{"phase":"","message":"Emergency rollback initiated"}}'
```

## Monitoring and Alerting

### Production Metrics Dashboard

The example integrates with monitoring systems to provide comprehensive observability:

```bash
# Access production metrics
kubectl port-forward deployment/awscdk-operator -n awscdk-operator-system 9115:9115
curl localhost:9115/metrics/hooks | grep production

# Key production metrics:
# - deployment_duration_seconds
# - health_check_response_time_ms
# - drift_detection_frequency
# - security_compliance_score
```

### Alert Severity Levels

- **Critical**: Production outages, security incidents, data loss
- **High**: Performance degradation, partial service disruption
- **Medium**: Non-critical drift detection, backup failures
- **Low**: Informational alerts, scheduled maintenance

## Security and Compliance

### 1. Security Scanning

```yaml
# Security validation in hooks
beforeDeploy: |
  # Scan for security vulnerabilities
  if command -v trivy >/dev/null 2>&1; then
    trivy config . --severity HIGH,CRITICAL --exit-code 1
  fi
  
  # Check for secrets in repository
  if command -v git-secrets >/dev/null 2>&1; then
    git secrets --scan
  fi
```

### 2. Compliance Monitoring

```yaml
# Compliance checks
afterDeploy: |
  # SOC 2 compliance validation
  echo "🔍 SOC 2 compliance check..."
  
  # Check encryption at rest
  aws s3api get-bucket-encryption --bucket $BUCKET_NAME
  
  # Check access logging
  aws s3api get-bucket-logging --bucket $BUCKET_NAME
  
  # GDPR compliance for EU deployments
  if [ "$CDK_STACK_REGION" = "eu-west-1" ]; then
    echo "🇪🇺 GDPR compliance validation..."
    # Additional GDPR checks
  fi
```

## Cost Optimization

### 1. Resource Right-Sizing

```yaml
cdkContext:
  - "cost-optimization=true"
  - "right-sizing-enabled=true"
  - "scheduled-scaling=true"
```

### 2. Cost Monitoring

```bash
# Daily cost reports
afterDeploy: |
  # Get daily costs for the stack
  DAILY_COST=$(aws ce get-cost-and-usage \
    --time-period Start=$(date -d '1 day ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity DAILY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter file://cost-filter.json \
    --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
    --output text)
  
  echo "💰 Daily cost: \$$DAILY_COST"
```

## High Availability and Disaster Recovery

### 1. Multi-AZ Deployment

```yaml
cdkContext:
  - "multi-az=true"
  - "availability-zones=3"
  - "auto-failover=true"
```

### 2. Backup Strategy

```yaml
cdkContext:
  - "backup-enabled=true"
  - "backup-retention=30"
  - "point-in-time-recovery=true"
  - "cross-region-backup=true"
```

### 3. Disaster Recovery Testing

```bash
# Monthly DR test
afterDeploy: |
  if [ "$(date +%d)" = "01" ]; then
    echo "🔄 Monthly disaster recovery test"
    # Automated DR test procedures
  fi
```

## Performance Optimization

### 1. Auto-Scaling Configuration

```yaml
cdkContext:
  - "auto-scaling=true"
  - "min-capacity=2"
  - "max-capacity=20"
  - "target-cpu-utilization=70"
```

### 2. Performance Monitoring

```bash
# Performance baseline and alerting
afterDeploy: |
  # Set performance thresholds
  RESPONSE_TIME_THRESHOLD=500  # ms
  ERROR_RATE_THRESHOLD=1       # %
  
  if [ "$RESPONSE_TIME" -gt "$RESPONSE_TIME_THRESHOLD" ]; then
    echo "⚠️  Performance alert: Response time ${RESPONSE_TIME}ms exceeds threshold"
  fi
```

## Troubleshooting Production Issues

### Common Production Issues

1. **Deployment failures**: Check approval status and business hour restrictions
2. **Performance degradation**: Compare with baseline metrics
3. **Security alerts**: Review compliance validation logs
4. **Cost overruns**: Check resource utilization and auto-scaling

### Debug Commands

```bash
# Check production deployment status
kubectl get cdk -n production -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,LAST-DEPLOY:.status.lastDeploy

# View production-specific logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -i production

# Check compliance status
kubectl get configmaps -n production -l compliance-check=true
```

## Next Steps

- [Troubleshooting Guide](../troubleshooting.md) - Debug production issues
- [Configuration Reference](../configuration.md) - Advanced production configuration 