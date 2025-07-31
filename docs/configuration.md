# Configuration

This guide covers all configuration options available for the AWS CDK Operator and CDK stack resources.

## CdkTsStack Resource Specification

The `CdkTsStack` custom resource is the primary way to configure CDK deployments.

### Complete Example

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: example-stack
  namespace: default
  labels:
    environment: production
    team: platform
  annotations:
    description: "Production S3 bucket with encryption"
spec:
  stackName: ExampleProductionStack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  source:
    git:
      repository: https://github.com/company/infrastructure.git
      ref: v1.2.3
      sshSecretName: git-ssh-key
  path: services/storage
  cdkContext:
    - name: environment
      value: production
    - name: bucketName
      value: my-company-data
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
  lifecycleHooks:
    beforeDeploy: |
      echo "Starting deployment of $CDK_STACK_NAME"
      # Validate prerequisites
    afterDeploy: |
      echo "Deployment completed successfully"
      # Send notifications
    beforeDestroy: |
      # Backup data before destruction
      echo "Backing up data..."
    afterDestroy: |
      echo "Stack destroyed, cleanup completed"
    beforeDriftDetection: |
      echo "Checking for drift in $CDK_STACK_NAME"
    afterDriftDetection: |
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        echo "Drift detected! Sending alert..."
      fi
```

## Required Fields

### stackName
The name of the CloudFormation stack to create/manage.

```yaml
spec:
  stackName: MyApplicationStack
```

### credentialsSecretName
Name of the Kubernetes secret containing AWS credentials.

```yaml
spec:
  credentialsSecretName: aws-credentials
```

**Secret Format:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aws-credentials
  namespace: awscdk-operator-system
type: Opaque
data:
  AWS_ACCESS_KEY_ID: <base64-encoded-access-key>
  AWS_SECRET_ACCESS_KEY: <base64-encoded-secret-key>
  # Optional: AWS_SESSION_TOKEN for temporary credentials
```

### source.git.repository
Git repository URL containing the CDK project.

```yaml
spec:
  source:
    git:
      repository: https://github.com/company/infrastructure.git
```

## Optional Fields

### awsRegion
Target AWS region for deployment.

- **Default**: `us-east-1`
- **Example**: `eu-west-1`, `ap-southeast-2`

```yaml
spec:
  awsRegion: eu-west-1
```

### source.git.ref
Git reference (branch, tag, or commit hash).

- **Default**: `main`
- **Examples**: `main`, `v1.0.0`, `feature/new-storage`

```yaml
spec:
  source:
    git:
      ref: v1.0.0
```

### source.git.sshSecretName
Name of the SSH key secret for private repositories.

```yaml
spec:
  source:
    git:
      sshSecretName: git-ssh-key
```

**SSH Secret Format:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-ssh-key
  namespace: awscdk-operator-system
type: kubernetes.io/ssh-auth
data:
  ssh-privatekey: <base64-encoded-private-key>
```

### path
Path to the CDK project within the repository.

- **Default**: `.` (repository root)
- **Example**: `services/api`, `infrastructure/networking`

```yaml
spec:
  path: services/storage
```

### cdkContext
Additional context parameters passed to CDK.

```yaml
spec:
  cdkContext:
    - name: environment
      value: production
    - name: vpc-id
      value: vpc-12345678
    - name: enable-encryption
      value: "true"
```

These become available in CDK as:
```typescript
// In your CDK code
const environment = this.node.tryGetContext('environment');
const vpcId = this.node.tryGetContext('vpc-id');
const enableEncryption = this.node.tryGetContext('enable-encryption') === 'true';
```

## Actions Configuration

Control what operations are allowed on the stack.

### deploy
Allow stack deployment and updates.

- **Default**: `true`
- **Use case**: Disable for read-only environments

```yaml
spec:
  actions:
    deploy: false  # Prevents deployment
```

### destroy
Allow stack destruction.

- **Default**: `true`
- **Use case**: Protect critical resources

```yaml
spec:
  actions:
    destroy: false  # Prevents destruction
```

### driftDetection
Enable drift monitoring.

- **Default**: `true`
- **Use case**: Disable for frequently changing stacks

```yaml
spec:
  actions:
    driftDetection: false  # Disables drift checks
```

### autoRedeploy
Automatically redeploy stack when Git repository changes are detected.

- **Default**: `false`
- **Use case**: Enable for automatic deployment of Git changes

```yaml
spec:
  actions:
    autoRedeploy: true  # Enables auto-deploy of Git changes
```

## Lifecycle Hooks

Execute custom scripts at various stages of the stack lifecycle.

### Available Hooks

| Hook | When Executed | Environment Variables |
|------|---------------|----------------------|
| `beforeDeploy` | Before CDK deploy | `CDK_STACK_NAME`, `AWS_REGION` |
| `afterDeploy` | After successful deploy | `CDK_STACK_NAME`, `AWS_REGION`, `CDK_OUTPUTS` |
| `beforeDestroy` | Before CDK destroy | `CDK_STACK_NAME`, `AWS_REGION` |
| `afterDestroy` | After successful destroy | `CDK_STACK_NAME`, `AWS_REGION` |
| `beforeDriftDetection` | Before drift check | `CDK_STACK_NAME`, `AWS_REGION` |
| `afterDriftDetection` | After drift check | `CDK_STACK_NAME`, `AWS_REGION`, `DRIFT_DETECTED` |
| `beforeGitSync` | Before Git sync check | `GIT_REPOSITORY`, `GIT_REF` |
| `afterGitSync` | After Git sync check | `GIT_REPOSITORY`, `GIT_REF`, `GIT_CHANGED` |

### Hook Examples

**Notification Hook:**
```yaml
spec:
  lifecycleHooks:
    afterDeploy: |
      curl -X POST https://hooks.slack.com/... \
        -d "{\"text\":\"Stack $CDK_STACK_NAME deployed successfully\"}"
```

**Validation Hook:**
```yaml
spec:
  lifecycleHooks:
    beforeDeploy: |
      # Validate environment
      if [[ -z "$CDK_STACK_NAME" ]]; then
        echo "Stack name not set"
        exit 1
      fi
      
      # Check prerequisites
      aws sts get-caller-identity > /dev/null || exit 1
```

**Backup Hook:**
```yaml
spec:
  lifecycleHooks:
    beforeDestroy: |
      # Backup RDS snapshots
      aws rds create-db-snapshot \
        --db-instance-identifier $DB_INSTANCE \
        --db-snapshot-identifier backup-$(date +%Y%m%d-%H%M%S)
```

**Drift Alert Hook:**
```yaml
spec:
  lifecycleHooks:
    afterDriftDetection: |
      if [[ "$DRIFT_DETECTED" == "true" ]]; then
        # Send alert to monitoring system
        curl -X POST $WEBHOOK_URL \
          -H "Content-Type: application/json" \
          -d "{
            \"alert\": \"Infrastructure Drift Detected\",
            \"stack\": \"$CDK_STACK_NAME\",
            \"region\": \"$AWS_REGION\",
            \"timestamp\": \"$(date -Iseconds)\"
          }"
      fi
```

## Environment Variables

Hooks have access to these environment variables:

| Variable | Description | Available In |
|----------|-------------|--------------|
| `CDK_STACK_NAME` | CloudFormation stack name | All hooks |
| `AWS_REGION` | Target AWS region | All hooks |
| `CDK_OUTPUTS` | Stack outputs (JSON) | `afterDeploy` |
| `DRIFT_DETECTED` | `true` if drift detected | `afterDriftDetection` |
| `GIT_REPOSITORY` | Git repository URL | Git sync hooks |
| `GIT_REF` | Git reference | Git sync hooks |
| `GIT_CHANGED` | `true` if Git changed | `afterGitSync` |

## Status and Monitoring

The operator updates the resource status with deployment information:

```yaml
status:
  phase: Succeeded
  message: "Stack deployed successfully"
  lastDeployment: "2024-01-15T10:30:00Z"
  stackId: "arn:aws:cloudformation:us-east-1:123456789012:stack/MyStack/uuid"
  outputs:
    BucketName: "my-bucket-12345"
    BucketArn: "arn:aws:s3:::my-bucket-12345"
  conditions:
    - type: Ready
      status: "True"
      lastTransitionTime: "2024-01-15T10:30:00Z"
```

### Phase Values

| Phase | Description |
|-------|-------------|
| `""` (empty) | Resource created, waiting to start |
| `Cloning` | Downloading Git repository |
| `Installing` | Installing CDK dependencies |
| `Deploying` | Executing CDK deploy |
| `Succeeded` | Deployment completed successfully |
| `Failed` | Deployment failed |
| `Deleting` | Executing CDK destroy |
| `DriftChecking` | Performing drift detection |
| `GitSyncChecking` | Checking Git synchronization |

## Operator Configuration

Configure the operator itself through environment variables in the deployment.

### Available Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `DEBUG_MODE` | Enable debug logging | `false` |
| `DRIFT_CHECK_CRON` | Cron schedule for drift detection | `*/10 * * * *` |
| `GIT_SYNC_CHECK_CRON` | Cron schedule for Git sync checks | `*/5 * * * *` |
| `METRICS_PREFIX` | Prefix for Prometheus metrics | `cdktsstack_operator` |
| `CDK_DEFAULT_ACCOUNT` | Default AWS account ID | - |
| `CDK_DEFAULT_REGION` | Default AWS region | `us-east-1` |
| `NODE_OPTIONS` | Node.js options for CDK | - |

### Example Operator Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: awscdk-operator
spec:
  template:
    spec:
      containers:
      - name: operator
        env:
        - name: DEBUG_MODE
          value: "true"
        - name: DRIFT_CHECK_CRON
          value: "*/5 * * * *"
        - name: NODE_OPTIONS
          value: "--max-old-space-size=4096"
```

## Operator Metrics

The AWS CDK Operator exposes Prometheus metrics on port 9115 at the `/metrics/hooks` endpoint.

### Accessing Metrics

```bash
# Port forward to access metrics locally
kubectl port-forward deployment/awscdk-operator -n awscdk-operator-system 9115:9115

# Query metrics
curl localhost:9115/metrics/hooks
```

### Available Metrics

| Metric | Type | Description | Labels |
|--------|------|-------------|--------|
| `cdktsstack_drift_checks_total` | counter | Total number of drift checks performed | `aws_region`, `hook`, `namespace`, `resource_name`, `stack_name` |
| `cdktsstack_drift_status` | gauge | Current drift status (0=no drift, 1=drift detected) | `aws_region`, `hook`, `namespace`, `resource_name`, `stack_name` |
| `cdktsstack_git_sync_pending` | gauge | Git sync pending status (0=synced, 1=pending) | `aws_region`, `hook`, `namespace`, `resource_name`, `stack_name` |

### Example Metrics Output

```
# HELP cdktsstack_drift_checks_total cdktsstack_drift_checks_total
# TYPE cdktsstack_drift_checks_total counter
cdktsstack_drift_checks_total{aws_region="us-east-1",hook="10-drift-checker.sh",namespace="awscdk-operator-system",resource_name="argocd-cdk-test",stack_name=""} 110

# HELP cdktsstack_drift_status cdktsstack_drift_status
# TYPE cdktsstack_drift_status gauge
cdktsstack_drift_status{aws_region="us-east-1",hook="10-drift-checker.sh",namespace="awscdk-operator-system",resource_name="argocd-cdk-test",stack_name=""} 0

# HELP cdktsstack_git_sync_pending cdktsstack_git_sync_pending
# TYPE cdktsstack_git_sync_pending gauge
cdktsstack_git_sync_pending{aws_region="us-east-1",hook="10-drift-checker.sh",namespace="awscdk-operator-system",resource_name="argocd-cdk-test",stack_name=""} 0
```

### Monitoring Integration

These metrics can be scraped by Prometheus and used in Grafana dashboards for monitoring:

- **Drift Detection**: Monitor infrastructure drift across all stacks
- **Git Synchronization**: Track when stacks are out of sync with Git
- **Operational Health**: Monitor the frequency of drift checks and sync operations

## Best Practices

### Naming Conventions

- Use descriptive stack names: `frontend-api-prod` vs `stack1`
- Include environment in names: `storage-staging`, `database-prod`
- Use consistent naming across resources

### Resource Organization

- Group related stacks in the same namespace
- Use labels for categorization:
  ```yaml
  metadata:
    labels:
      environment: production
      component: storage
      team: platform
  ```

### Security

- Store credentials in dedicated namespace
- Use separate AWS accounts per environment
- Rotate credentials regularly
- Review lifecycle hooks for security implications

### Git Repository Structure

Organize CDK projects clearly:
```
infrastructure/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
├── services/
│   ├── api/
│   ├── database/
│   └── storage/
└── shared/
    ├── networking/
    └── security/
```

### Monitoring

- Enable drift detection for critical stacks
- Set up alerts for failed deployments
- Monitor operator logs
- Use meaningful lifecycle hooks for notifications 