# 07 - Git Integration

**Level**: Advanced  
**Purpose**: Advanced Git features including private repositories, SSH keys, and branch strategies

## Overview

This example demonstrates advanced Git integration patterns including private repository access, SSH key management, tag-based deployments, and sophisticated branching strategies for different environments.

## What This Example Creates

- Multiple stacks using different Git strategies
- SSH key-based authentication for private repositories
- Tag-based release deployments
- Branch-specific environment deployments

## Prerequisites

1. Completed examples [01-06](README.md#learning-path)
2. SSH key pair for Git repository access
3. Private Git repository (GitHub, GitLab, Bitbucket, etc.)
4. Understanding of Git workflows and SSH key management

## SSH Key Setup

Before using private repositories, you need to set up SSH key authentication:

### 1. Generate SSH Key Pair

```bash
# Generate a dedicated SSH key for the CDK operator
ssh-keygen -t rsa -b 4096 -f ~/.ssh/cdk-operator -C "cdk-operator@your-domain.com"

# This creates:
# ~/.ssh/cdk-operator (private key)
# ~/.ssh/cdk-operator.pub (public key)
```

### 2. Add Public Key to Git Provider

**GitHub:**
1. Go to repository → Settings → Deploy keys
2. Add the public key content from `~/.ssh/cdk-operator.pub`
3. Enable "Allow write access" if the operator needs to push

**GitLab:**
1. Go to repository → Settings → Repository → Deploy Keys
2. Add the public key

**Bitbucket:**
1. Go to repository → Repository settings → Access keys
2. Add the public key

### 3. Create Kubernetes Secret

```bash
# Create SSH secret from private key
kubectl create secret generic awscdk-operator-ssh-key \
  --from-file=ssh-privatekey=~/.ssh/cdk-operator \
  --namespace=awscdk-operator-system

# Verify secret was created
kubectl get secret awscdk-operator-ssh-key -n awscdk-operator-system -o yaml
```

## Example Implementations

### 1. Private Repository with SSH Key

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: private-repo-ssh
  namespace: default
  labels:
    example: "07-git-integration"
    level: "advanced"
    git-type: "ssh-private"
spec:
  stackName: PrivateRepo-SSH-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: git@github.com:your-org/private-infrastructure.git
      ref: main
      sshSecretName: awscdk-operator-ssh-key  # Reference to SSH secret
  path: ./private-stack
  
  cdkContext:
    - "environment=secure"
    - "repository=private"
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false
  
  lifecycleHooks:
    beforeDeploy: |
      echo "🔐 Deploying from private repository with SSH authentication"
      echo "📂 Repository: git@github.com:your-org/private-infrastructure.git"
      echo "🔑 Using SSH key authentication"
      
      # Verify SSH key is available
      if [ -f /root/.ssh/ssh-privatekey ]; then
        echo "✅ SSH private key found"
        # Set proper permissions
        chmod 600 /root/.ssh/ssh-privatekey
      else
        echo "❌ SSH private key not found"
        exit 1
      fi
    
    afterDeploy: |
      echo "✅ Successfully deployed from private repository"
      echo "🔒 Infrastructure deployed securely using SSH authentication"
```

### 2. Tag-Based Release Strategy

Deploy specific releases using Git tags:

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: release-tagged-deployment
  namespace: production
  labels:
    example: "07-git-integration"
    level: "advanced"
    deployment-type: "release"
spec:
  stackName: Production-Release-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/infrastructure-releases.git
      ref: v2.1.0  # 🏷️ Specific release tag
  path: ./production
  
  cdkContext:
    - "environment=production"
    - "release=v2.1.0"
    - "stability=stable"
  
  actions:
    deploy: true
    destroy: false  # Protect production
    driftDetection: true
    autoRedeploy: false
  
  lifecycleHooks:
    beforeDeploy: |
      echo "🏷️  Deploying tagged release: v2.1.0"
      echo "🏭 Environment: Production"
      
      # Validate this is a stable release tag
      RELEASE_TAG="v2.1.0"
      
      # Check if tag follows semantic versioning
      if [[ ! "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid release tag format: $RELEASE_TAG"
        echo "Expected format: vX.Y.Z (semantic versioning)"
        exit 1
      fi
      
      echo "✅ Valid release tag format"
      
      # Additional production validations
      echo "🔍 Running production deployment validations..."
      
      # Verify we're not deploying a pre-release
      if [[ "$RELEASE_TAG" =~ (alpha|beta|rc) ]]; then
        echo "❌ Pre-release tags not allowed in production: $RELEASE_TAG"
        exit 1
      fi
      
      echo "✅ Production release validation passed"
    
    afterDeploy: |
      echo "🎉 Production deployment completed successfully"
      echo "🏷️  Release: v2.1.0"
      echo "📅 Deployed at: $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)"
      
      # Tag deployment in monitoring system
      if [ -n "${DEPLOYMENT_TRACKER_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
          --data "{
            \"environment\": \"production\",
            \"release\": \"v2.1.0\",
            \"stack\": \"$CDK_STACK_NAME\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
            \"status\": \"deployed\"
          }" \
          "$DEPLOYMENT_TRACKER_URL"
      fi
```

### 3. Branch-Based Environment Strategy

Different branches for different environments:

```yaml
# Development Environment (feature branches)
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: feature-branch-dev
  namespace: development
  labels:
    example: "07-git-integration"
    environment: "development"
    branch-strategy: "feature"
spec:
  stackName: Feature-Development-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-west-2
  
  source:
    git:
      repository: https://github.com/your-org/infrastructure-dev.git
      ref: feature/new-api-gateway  # 🌿 Feature branch
  path: ./development
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: true  # Fast iteration for development
  
---
# Staging Environment (main branch)
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: main-branch-staging
  namespace: staging
  labels:
    example: "07-git-integration"
    environment: "staging"
    branch-strategy: "main"
spec:
  stackName: Main-Staging-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/infrastructure-dev.git
      ref: main  # 🌿 Main branch
  path: ./staging
  
  actions:
    deploy: true
    destroy: true
    driftDetection: true
    autoRedeploy: false  # Manual approval for staging
  
---
# Production Environment (release branches)
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: release-branch-prod
  namespace: production
  labels:
    example: "07-git-integration"
    environment: "production"
    branch-strategy: "release"
spec:
  stackName: Release-Production-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: https://github.com/your-org/infrastructure-releases.git
      ref: release/2.1.x  # 🌿 Release branch
  path: ./production
  
  actions:
    deploy: true
    destroy: false
    driftDetection: true
    autoRedeploy: false  # Strict manual control
```

### 4. Multi-Repository Strategy

Using different repositories for different components:

```yaml
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: networking-repo
  namespace: infrastructure
  labels:
    example: "07-git-integration"
    component: "networking"
spec:
  stackName: Networking-Infrastructure-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: git@github.com:your-org/networking-infrastructure.git
      ref: main
      sshSecretName: awscdk-operator-ssh-key
  path: ./vpc-setup
  
  lifecycleHooks:
    afterDeploy: |
      echo "🌐 Networking infrastructure deployed"
      
      # Get VPC outputs for other stacks
      VPC_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$CDK_STACK_NAME" \
        --query 'Stacks[0].Outputs' \
        --output json)
      
      # Store outputs in ConfigMap for other stacks
      kubectl create configmap vpc-outputs \
        --from-literal="vpc-id=$(echo "$VPC_OUTPUTS" | jq -r '.[] | select(.OutputKey=="VpcId") | .OutputValue')" \
        --from-literal="private-subnet-ids=$(echo "$VPC_OUTPUTS" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue')" \
        --dry-run=client -o yaml | kubectl apply -f -

---
apiVersion: awscdk.dev/v1alpha1
kind: CdkTsStack
metadata:
  name: application-repo
  namespace: infrastructure
  labels:
    example: "07-git-integration"
    component: "application"
spec:
  stackName: Application-Infrastructure-Stack
  credentialsSecretName: aws-credentials
  awsRegion: us-east-1
  
  source:
    git:
      repository: git@github.com:your-org/application-infrastructure.git
      ref: main
      sshSecretName: awscdk-operator-ssh-key
  path: ./app-stack
  
  lifecycleHooks:
    beforeDeploy: |
      echo "🏗️  Deploying application infrastructure"
      
      # Get VPC information from previous stack
      VPC_ID=$(kubectl get configmap vpc-outputs -o jsonpath='{.data.vpc-id}' 2>/dev/null || echo "")
      
      if [ -z "$VPC_ID" ]; then
        echo "❌ VPC infrastructure not found. Deploy networking stack first."
        exit 1
      fi
      
      echo "✅ Using VPC: $VPC_ID"
      
      # Pass VPC info as context to CDK
      kubectl patch cdk application-repo --type='merge' \
        -p="{\"spec\":{\"cdkContext\":[\"vpcId=$VPC_ID\"]}}"
```

## Git Workflow Patterns

### 1. GitOps Pull-Based Updates

Monitor Git changes and auto-update:

```yaml
spec:
  actions:
    autoRedeploy: true  # Enable auto-updates from Git
  
  lifecycleHooks:
    afterGitSync: |
      if [[ "$GIT_CHANGES_DETECTED" == "true" ]]; then
        echo "📥 Git changes detected - triggering deployment"
        echo "🔄 Auto-redeploy enabled - deployment will start automatically"
      else
        echo "✅ No Git changes - infrastructure is up to date"
      fi
```

### 2. Approval-Based Deployments

Require manual approval for sensitive environments:

```yaml
spec:
  actions:
    autoRedeploy: false  # Manual approval required
  
  lifecycleHooks:
    afterGitSync: |
      if [[ "$GIT_CHANGES_DETECTED" == "true" ]]; then
        echo "📥 Git changes detected in production branch"
        echo "⏸️  Manual approval required for production deployment"
        
        # Send approval request
        if [ -n "${APPROVAL_WEBHOOK_URL:-}" ]; then
          curl -X POST -H 'Content-type: application/json' \
            --data "{
              \"text\": \"🔄 Production deployment approval required for $CDK_STACK_NAME\",
              \"actions\": [
                {\"text\": \"Approve\", \"url\": \"$APPROVAL_URL\"},
                {\"text\": \"Reject\", \"url\": \"$REJECTION_URL\"}
              ]
            }" \
            "$APPROVAL_WEBHOOK_URL"
        fi
      fi
```

## SSH Configuration Best Practices

### 1. SSH Key Rotation

```bash
# Generate new SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/cdk-operator-new

# Update secret with new key
kubectl create secret generic awscdk-operator-ssh-key-new \
  --from-file=ssh-privatekey=~/.ssh/cdk-operator-new \
  --namespace=awscdk-operator-system

# Update stacks to use new secret
kubectl patch cdk my-stack --type='merge' \
  -p='{"spec":{"source":{"git":{"sshSecretName":"awscdk-operator-ssh-key-new"}}}}'

# Remove old secret after verification
kubectl delete secret awscdk-operator-ssh-key -n awscdk-operator-system
```

### 2. Multiple SSH Keys for Different Repositories

```yaml
# GitHub private repo
spec:
  source:
    git:
      repository: git@github.com:company/repo1.git
      sshSecretName: github-ssh-key

---
# GitLab private repo
spec:
  source:
    git:
      repository: git@gitlab.com:company/repo2.git
      sshSecretName: gitlab-ssh-key
```

## Monitoring Git Integration

### Track Git Synchronization

```bash
# Check Git sync status across all stacks
kubectl get cdk -o custom-columns=NAME:.metadata.name,REPOSITORY:.spec.source.git.repository,REF:.spec.source.git.ref,LAST-SYNC:.status.lastGitSync

# Monitor Git sync metrics
kubectl port-forward deployment/awscdk-operator -n awscdk-operator-system 9115:9115
curl localhost:9115/metrics/hooks | grep git_sync
```

### Git Sync Webhooks

Set up webhooks to notify on Git changes:

```bash
# Configure Git sync webhook
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
                "name": "GIT_SYNC_WEBHOOK_URL",
                "value": "https://your-webhook-endpoint.com/git-sync"
              }
            ]
          }
        ]
      }
    }
  }
}'
```

## Troubleshooting Git Integration

### Common SSH Issues

1. **Permission denied (publickey)**
   ```bash
   # Test SSH connection
   ssh -T git@github.com
   
   # Check SSH key format
   kubectl get secret awscdk-operator-ssh-key -n awscdk-operator-system -o jsonpath='{.data.ssh-privatekey}' | base64 -d | head -1
   ```

2. **Repository not found**
   ```bash
   # Verify repository URL
   git ls-remote git@github.com:your-org/repo.git
   ```

3. **SSH key not loading**
   ```bash
   # Check secret exists and has correct key
   kubectl describe secret awscdk-operator-ssh-key -n awscdk-operator-system
   ```

### Debug Git Operations

```bash
# Enable Git debug logging
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
                "name": "GIT_DEBUG",
                "value": "true"
              }
            ]
          }
        ]
      }
    }
  }
}'

# View Git operation logs
kubectl logs -n awscdk-operator-system deployment/awscdk-operator | grep -i git
```

## Security Considerations

### SSH Key Security

1. **Use dedicated keys**: Don't reuse personal SSH keys
2. **Minimal permissions**: Use deploy keys with read-only access when possible
3. **Key rotation**: Regularly rotate SSH keys
4. **Audit access**: Monitor who has access to SSH keys

### Repository Security

1. **Private repositories**: Use private repos for sensitive infrastructure
2. **Branch protection**: Protect production branches with required reviews
3. **Signed commits**: Require signed commits for production deployments
4. **Access control**: Limit repository access to authorized personnel

## Next Steps

- [08 - Production Ready](08-production-ready.md) - Complete production setup
- [Troubleshooting Guide](../troubleshooting.md) - Debug Git issues 