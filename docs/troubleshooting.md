# Troubleshooting

This guide covers common issues with the AWS CDK Operator and how to resolve them.

## Manual Status Recovery

### Operator Stuck in Phase

If an operator gets stuck in a particular phase and won't progress, you can manually change the status by patching the resource:

```bash
kubectl patch cdk my-cdk-stack -n awscdk-operator-system \
  --subresource=status --type='merge' \
  -p='{"status":{"phase":"Succeeded","message":"Manual restart"}}'
```

Replace `my-cdk-stack` with your actual stack name and adjust the namespace as needed.

**Available phases:**
- `""` (empty) - Resource created, waiting to start
- `Cloning` - Downloading Git repository
- `Installing` - Installing CDK dependencies
- `Deploying` - Executing CDK deploy
- `Succeeded` - Deployment completed successfully
- `Failed` - Deployment failed
- `Deleting` - Executing CDK destroy
- `DriftChecking` - Performing drift detection
- `GitSyncChecking` - Checking Git synchronization

### Force Re-deployment

To force a stack to redeploy from the beginning:

```bash
kubectl patch cdk my-cdk-stack \
  --subresource=status --type='merge' \
  -p='{"status":{"phase":"","message":"Forced restart"}}'
```

## Stuck Resource Deletion

### Remove Finalizer for Stuck CRD Deletion

If a CdkTsStack resource gets stuck during deletion due to finalizer issues (operator logic failure, AWS cleanup problems, etc.), you can manually remove the finalizer to force deletion.

**Symptoms:**
- Resource shows `deletionTimestamp` but won't complete deletion
- Resource has finalizers preventing cleanup
- Operator fails to properly clean up AWS resources

**Check if resource is stuck:**
```bash
# Check for deletion timestamp and finalizers
kubectl get cdk <stack-name> -o yaml | grep -E "(deletionTimestamp|finalizers)" -A 5
```

**Force removal by patching finalizer:**
```bash
# Remove the finalizer to force deletion
kubectl patch cdk <stack-name> \
  --type='merge' \
  -p='{"metadata":{"finalizers":[]}}'
```

**Alternative method using JSON patch:**
```bash
# Remove specific finalizer
kubectl patch cdk <stack-name> \
  --type='json' \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

**⚠️ Warning:** Removing finalizers bypasses the operator's cleanup logic. This may leave AWS CloudFormation stacks and resources orphaned. After forcing deletion, manually verify and clean up AWS resources if needed:

```bash
# Check for orphaned CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Delete orphaned stack if found
aws cloudformation delete-stack --stack-name <stack-name>
```

## Common Issues and Solutions

### 1. Stack Stuck in "Cloning" Phase

**Symptoms:**
- Stack remains in "Cloning" phase for extended periods
- Logs show Git connectivity issues

**Causes:**
- Git repository is inaccessible
- Network connectivity issues
- SSH key problems for private repositories
- Incorrect repository URL

**Solutions:**

```bash
# Check operator logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -i clone

# Verify repository accessibility
git clone <repository-url> /tmp/test-clone

# For SSH issues, check SSH key secret
kubectl get secret awscdk-operator-ssh-key -n awscdk-operator-system -o yaml

# Test SSH connectivity
kubectl run debug-pod --image=alpine/git --rm -it -- sh
# Inside pod: ssh -T git@github.com
```

**Fix SSH key issues:**
```bash
# Recreate SSH key secret
kubectl delete secret awscdk-operator-ssh-key -n awscdk-operator-system
kubectl create secret generic awscdk-operator-ssh-key \
  --from-file=ssh-privatekey=/path/to/correct/private/key \
  --namespace=awscdk-operator-system
```

### 2. "Failed to Assume Role" Errors

**Symptoms:**
- Stack fails during deployment
- AWS authentication errors in logs

**Causes:**
- Invalid AWS credentials
- Insufficient IAM permissions
- Credentials secret in wrong namespace
- Incorrect AWS region configuration

**Solutions:**

```bash
# Check AWS credentials secret
kubectl get secret aws-credentials -n awscdk-operator-system -o yaml

# Verify credentials work
kubectl run aws-test --image=amazon/aws-cli --rm -it -- \
  aws sts get-caller-identity \
  --aws-access-key-id=<key> \
  --aws-secret-access-key=<secret>

# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
  --action-names cloudformation:CreateStack cloudformation:UpdateStack \
  --resource-arns "*"
```

**Recreate credentials:**
```bash
kubectl delete secret aws-credentials -n awscdk-operator-system
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=your-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-secret-key \
  --namespace=awscdk-operator-system
```

### 3. CDK Deployment Failures

**Symptoms:**
- Stack fails in "Deploying" phase
- CloudFormation errors in logs

**Causes:**
- Invalid CDK project structure
- Missing dependencies in package.json
- CDK context issues
- AWS resource limit exceeded
- CloudFormation template errors

**Solutions:**

```bash
# Check operator logs for CDK errors
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -A 10 -B 10 "cdk deploy"

# Validate CDK project locally
git clone <repository-url>
cd <project-path>
npm install
npm run build
cdk synth
cdk diff

# Check CloudFormation events in AWS Console
aws cloudformation describe-stack-events --stack-name <stack-name>
```

**Fix common CDK issues:**
- Ensure `package.json` has all required dependencies
- Verify `cdk.json` configuration
- Check for CDK version compatibility
- Review CloudFormation limits in target region

### 4. Drift Detection Not Working

**Symptoms:**
- Drift detection never runs
- No drift detection logs
- Stack status doesn't update with drift information

**Causes:**
- Drift detection disabled in actions
- CloudFormation stack doesn't support drift detection
- AWS permissions missing for drift detection
- Stack in unsupported state

**Solutions:**

```bash
# Verify drift detection is enabled
kubectl get cdk <stack-name> -o yaml | grep -A 5 actions

# Check drift detection permissions
aws cloudformation detect-stack-drift --stack-name <stack-name>

# Enable drift detection
kubectl patch cdk <stack-name> --type='merge' \
  -p='{"spec":{"actions":{"driftDetection":true}}}'
```

### 5. Lifecycle Hooks Failing

**Symptoms:**
- Deployment fails during hook execution
- Hook scripts don't execute as expected

**Causes:**
- Syntax errors in hook scripts
- Missing environment variables
- Missing dependencies in hook environment
- Permission issues

**Solutions:**

```bash
# Check hook execution logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -i hook

# Test hook script locally
#!/bin/bash
export CDK_STACK_NAME="test-stack"
export AWS_REGION="us-east-1"
# Paste your hook script here
```

**Debug hook scripts:**
```yaml
spec:
  lifecycleHooks:
    beforeDeploy: |
      set -x  # Enable debug output
      echo "DEBUG: CDK_STACK_NAME=$CDK_STACK_NAME"
      echo "DEBUG: AWS_REGION=$AWS_REGION"
      # Your original script here
```

### 6. Resource Quotas and Limits

**Symptoms:**
- Pods not starting
- Resource allocation errors
- OOM (Out of Memory) kills

**Causes:**
- Kubernetes resource quotas exceeded
- Insufficient cluster resources
- Memory limits too low for CDK operations

**Solutions:**

```bash
# Check resource quotas
kubectl describe quota -n awscdk-operator-system

# Check node resources
kubectl describe nodes

# Increase memory limits
kubectl patch deployment awscdk-operator -n awscdk-operator-system --patch '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "operator",
            "resources": {
              "limits": {
                "memory": "2Gi"
              },
              "requests": {
                "memory": "512Mi"
              }
            }
          }
        ]
      }
    }
  }
}'
```

## Debugging Techniques

### Enable Debug Mode

Enable detailed logging in the operator:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: awscdk-operator
  namespace: awscdk-operator-system
spec:
  template:
    spec:
      containers:
      - name: operator
        env:
        - name: DEBUG_MODE
          value: "true"
```

Or with Helm:
```bash
helm upgrade awscdk-operator aws-cdk-operator/aws-cdk-operator \
  --namespace awscdk-operator-system \
  --set operator.env.debugMode=true
```

### Useful Debug Commands

```bash
# Check all CDK stacks across namespaces
kubectl get cdk -A

# Get detailed stack information
kubectl describe cdk <stack-name>

# Check operator logs with timestamps
kubectl logs -n awscdk-operator-system deployment/awscdk-operator --timestamps

# Follow logs in real-time
kubectl logs -n awscdk-operator-system deployment/awscdk-operator -f

# Check events related to CDK stacks
kubectl get events --field-selector reason=CdkTsStackEvent

# Get stack status in JSON format
kubectl get cdk <stack-name> -o json | jq '.status'

# Check operator resource usage
kubectl top pod -n awscdk-operator-system
```

### Access Operator Pod for Debugging

```bash
# Get operator pod name
POD_NAME=$(kubectl get pods -n awscdk-operator-system -l app=awscdk-operator -o jsonpath='{.items[0].metadata.name}')

# Execute shell in operator pod
kubectl exec -it $POD_NAME -n awscdk-operator-system -- /bin/bash

# Inside pod, check Git clone directory
ls -la /tmp/
```

## Log Analysis

### Common Log Patterns

**Successful deployment:**
```
INFO: Starting deployment for stack: my-stack
INFO: Cloning repository: https://github.com/company/infrastructure.git
INFO: Installing CDK dependencies...
INFO: Running cdk deploy...
INFO: Deployment completed successfully
```

**Git clone failure:**
```
ERROR: Failed to clone repository: https://github.com/company/infrastructure.git
ERROR: fatal: could not read Username for 'https://github.com': No such device or address
```

**AWS credentials issue:**
```
ERROR: Unable to locate credentials. You can configure credentials by...
ERROR: cdk deploy failed with exit code 1
```

**CDK deployment failure:**
```
ERROR: Stack Deployments Failed: Error: The stack named MyStack failed creation
ERROR: Resource creation Cancelled due to rollback
```

### Log Filtering

```bash
# Filter logs by stack name
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep "my-stack"

# Filter deployment-related logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -E "(deploy|cdk)"

# Filter error logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep ERROR

# Get recent logs (last hour)
kubectl logs -n awscdk-operator-system deployment/awscdk-operator --since=1h
```

## Recovery Procedures

### Complete Stack Reset

If a stack is completely corrupted:

```bash
# 1. Delete the Kubernetes resource
kubectl delete cdk <stack-name>

# 2. Manually clean up AWS CloudFormation stack if needed
aws cloudformation delete-stack --stack-name <stack-name>

# 3. Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name <stack-name>

# 4. Recreate the resource
kubectl apply -f <stack-definition>.yaml
```

### Operator Restart

If the operator itself is misbehaving:

```bash
# Restart operator deployment
kubectl rollout restart deployment/awscdk-operator -n awscdk-operator-system

# Check restart status
kubectl rollout status deployment/awscdk-operator -n awscdk-operator-system
```

### Clean Reinstall

For complete operator reinstall:

```bash
# 1. Delete all CDK stacks first
kubectl delete cdk --all --all-namespaces

# 2. Uninstall operator
helm uninstall awscdk-operator -n awscdk-operator-system

# 3. Clean up namespace
kubectl delete namespace awscdk-operator-system

# 4. Reinstall operator
helm install awscdk-operator aws-cdk-operator/aws-cdk-operator \
  --namespace awscdk-operator-system \
  --create-namespace
```

## Getting Help

If you're still experiencing issues:

1. **Check the logs** using the commands above
2. **Enable debug mode** for more detailed output
3. **Test individual components** (Git access, AWS credentials, CDK project)
4. **Create a GitHub issue** with:
   - Stack definition YAML
   - Operator logs
   - Error messages
   - Environment details
   - Steps to reproduce

## Performance Optimization

### Reduce Resource Usage

```yaml
# Optimize operator resources
resources:
  limits:
    cpu: 200m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 256Mi
```

### Adjust Cron Schedules

```yaml
# Reduce frequency for large environments
operator:
  env:
    driftCheckCron: "0 */6 * * *"    # Every 6 hours instead of 10 minutes
    gitSyncCheckCron: "*/15 * * * *"  # Every 15 minutes instead of 5
```

### CDK Performance

```yaml
# CDK Node.js options
operator:
  env:
    nodeOptions: "--max-old-space-size=4096 --stack-size=65536"
```