#!/usr/bin/env bash

# Lifecycle hooks functions for CDK Stack Operator

# Function to execute a lifecycle hook
# Usage: execute_lifecycle_hook <namespace> <name> <hook_type> <hook_command>
# Returns: 0 on success, 1 on failure (but operation continues regardless)
execute_lifecycle_hook() {
  local namespace="${1:-}"
  local name="${2:-}"
  local hook_type="${3:-}"
  local hook_command="${4:-}"
  
  # Skip if hook command is empty or null
  if [[ -z "$hook_command" ]] || [[ "$hook_command" == "null" ]]; then
    debug_log "No ${hook_type} hook configured for ${namespace}/${name}"
    return 0
  fi
  
  log "Executing ${hook_type} lifecycle hook for ${namespace}/${name}..."
  create_event "${namespace}" "${name}" "Normal" "LifecycleHookStart" "Executing ${hook_type} hook" || true
  
  # Create a temporary script file to properly handle multi-line commands
  local hook_script="/tmp/lifecycle-hook-${name:-unknown}-${hook_type:-unknown}-$$.sh"
  cat > "$hook_script" <<EOF
#!/bin/bash
set -euo pipefail

# Export useful environment variables for the hook
export CDK_STACK_NAME="${CDK_STACK_NAME:-}"
export CDK_STACK_NAMESPACE="${namespace:-}"
export CDK_STACK_RESOURCE_NAME="${name:-}"
export CDK_STACK_REGION="${AWS_DEFAULT_REGION:-}"
export CDK_OPERATION="${hook_type:-}"
export CDK_PROJECT_PATH="${CDK_PROJECT_PATH:-}"
export CDK_GIT_REPOSITORY="${CDK_GIT_REPOSITORY:-}"
export CDK_GIT_REF="${CDK_GIT_REF:-}"

# Log hook environment for debugging
echo "[HOOK] Executing ${hook_type:-unknown} hook..."
echo "[HOOK] Stack: \${CDK_STACK_NAME:-not set}"
echo "[HOOK] Namespace: \${CDK_STACK_NAMESPACE:-not set}"
echo "[HOOK] Region: \${CDK_STACK_REGION:-not set}"
echo "[HOOK] AWS Account: \${AWS_ACCOUNT_ID:-not set}"

# Execute the actual hook command
${hook_command}
EOF
  
  chmod +x "$hook_script"
  
  # Execute hook
  local hook_output
  local hook_exit_code
  
  log "=== ${hook_type} HOOK OUTPUT START ==="
  
  # Run hook command directly
  hook_output=$(bash "$hook_script" 2>&1)
  hook_exit_code=$?
  
  # Log the output
  echo "$hook_output"
  log "=== ${hook_type} HOOK OUTPUT END ==="
  
  # Clean up
  rm -f "$hook_script"
  
  # Handle exit code - always continue operation
  if [[ $hook_exit_code -eq 0 ]]; then
    log "${hook_type} hook executed successfully"
    create_event "${namespace}" "${name}" "Normal" "LifecycleHookSuccess" "${hook_type} hook completed successfully" || true
    return 0
  else
    log "WARNING: ${hook_type} hook failed with exit code: ${hook_exit_code}, but continuing operation"
    create_event "${namespace}" "${name}" "Warning" "LifecycleHookFailure" "${hook_type} hook failed with exit code ${hook_exit_code}" || true
    return 1
  fi
}

# Function to extract lifecycle hooks configuration from resource
# Usage: get_lifecycle_hooks <resource_json>
# Exports: HOOK_BEFORE_DEPLOY, HOOK_AFTER_DEPLOY, etc.
get_lifecycle_hooks() {
  local resource="$1"
  
  # Safety check
  if [[ -z "$resource" ]] || [[ "$resource" == "null" ]]; then
    debug_log "get_lifecycle_hooks: No resource provided, skipping"
    return 0
  fi
  
  debug_log "get_lifecycle_hooks: Starting extraction from resource"
  
  # Extract all lifecycle hooks with error handling
  export HOOK_BEFORE_DEPLOY=$(echo "$resource" | jq -r '.spec.lifecycleHooks.beforeDeploy // ""' 2>/dev/null || echo "")
  export HOOK_AFTER_DEPLOY=$(echo "$resource" | jq -r '.spec.lifecycleHooks.afterDeploy // ""' 2>/dev/null || echo "")
  export HOOK_BEFORE_DESTROY=$(echo "$resource" | jq -r '.spec.lifecycleHooks.beforeDestroy // ""' 2>/dev/null || echo "")
  export HOOK_AFTER_DESTROY=$(echo "$resource" | jq -r '.spec.lifecycleHooks.afterDestroy // ""' 2>/dev/null || echo "")
  export HOOK_BEFORE_DRIFT=$(echo "$resource" | jq -r '.spec.lifecycleHooks.beforeDriftDetection // ""' 2>/dev/null || echo "")
  export HOOK_AFTER_DRIFT=$(echo "$resource" | jq -r '.spec.lifecycleHooks.afterDriftDetection // ""' 2>/dev/null || echo "")
  export HOOK_BEFORE_GIT_SYNC=$(echo "$resource" | jq -r '.spec.lifecycleHooks.beforeGitSync // ""' 2>/dev/null || echo "")
  export HOOK_AFTER_GIT_SYNC=$(echo "$resource" | jq -r '.spec.lifecycleHooks.afterGitSync // ""' 2>/dev/null || echo "")
  
  debug_log "get_lifecycle_hooks: Extraction completed successfully"
  
  # Debug log
  debug_log "Lifecycle hooks configuration loaded:"
  debug_log "  beforeDeploy: ${HOOK_BEFORE_DEPLOY:-(not set)}"
  debug_log "  afterDeploy: ${HOOK_AFTER_DEPLOY:-(not set)}"
  debug_log "  beforeDestroy: ${HOOK_BEFORE_DESTROY:-(not set)}"
  debug_log "  afterDestroy: ${HOOK_AFTER_DESTROY:-(not set)}"
  debug_log "  beforeDriftDetection: ${HOOK_BEFORE_DRIFT:-(not set)}"
  debug_log "  afterDriftDetection: ${HOOK_AFTER_DRIFT:-(not set)}"
  debug_log "  beforeGitSync: ${HOOK_BEFORE_GIT_SYNC:-(not set)}"
  debug_log "  afterGitSync: ${HOOK_AFTER_GIT_SYNC:-(not set)}"
}

# Helper function to set CDK environment variables for hooks
# Usage: export_cdk_env_for_hooks <stack_name> <project_path> <git_repository> <git_ref>
export_cdk_env_for_hooks() {
  # Safety: provide defaults for empty parameters
  export CDK_STACK_NAME="${1:-}"
  export CDK_PROJECT_PATH="${2:-}"
  export CDK_GIT_REPOSITORY="${3:-}"
  export CDK_GIT_REF="${4:-}"
  
  debug_log "export_cdk_env_for_hooks: Set environment variables safely"
} 