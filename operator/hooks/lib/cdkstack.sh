#!/usr/bin/env bash

# CDK Stack specific functions

# Function to run drift check for a specific resource
run_drift_check() {
  local namespace="$1"
  local name="$2"
  
  log "Starting drift check for ${namespace}/${name}"
  
  # Check if resource still exists before processing
  if ! kubectl -n "${namespace}" get cdktsstack "${name}" &>/dev/null; then
    log "Resource '${name}' no longer exists, skipping drift check"
    return 0
  fi
  
  # Load credentials for this resource
  local resource credentialsSecretName currentPhase
  resource=$(kubectl -n "${namespace}" get cdktsstack "${name}" -o json)
  currentPhase=$(echo "$resource" | jq -r '.status.phase // ""')
  
  # Only run drift check on resources in Succeeded phase
  if [[ "$currentPhase" != "$PHASE_SUCCEEDED" ]]; then
    log "Resource '${name}' is not in Succeeded phase (current: ${currentPhase}), skipping drift check"
    return 0
  fi
  
  # Update status to show drift check is in progress
  update_status "${namespace}" "${name}" "$PHASE_DRIFT_CHECKING" "Running CDK drift check..."
  create_event "${namespace}" "${name}" "Normal" "DriftCheckStart" "Starting scheduled drift check" || true
  
  credentialsSecretName=$(echo "$resource" | jq -r '.spec.credentialsSecretName')
  
  if ! load_aws_credentials "${namespace}" "${credentialsSecretName}"; then
    log "Failed to load AWS credentials for drift check"
    update_status "${namespace}" "${name}" "$PHASE_FAILED" "Failed to load AWS credentials for drift check"
    return 1
  fi
  
  # Get resource details for CDK operations
  local repository git_ref project_path stack_name aws_region
  repository=$(echo "$resource" | jq -r '.spec.source.git.repository')
  git_ref=$(echo "$resource" | jq -r '.spec.source.git.ref // "main"')
  project_path=$(echo "$resource" | jq -r '.spec.path // "."')
  stack_name=$(echo "$resource" | jq -r '.spec.stackName')
  aws_region=$(echo "$resource" | jq -r '.spec.awsRegion // "us-east-1"')
  
  # Set AWS region for CDK operations
  setup_aws_region "$aws_region"

  get_lifecycle_hooks "$resource"

  # Set CDK environment variables for hooks
  export_cdk_env_for_hooks "${stack_name}" "${project_path}" "${repository}" "${git_ref}"

  # Execute beforeDriftDetection hook if configured
  if [[ -n "${HOOK_BEFORE_DRIFT}" ]] && [[ "${HOOK_BEFORE_DRIFT}" != "null" ]]; then
    execute_lifecycle_hook "${namespace}" "${name}" "beforeDriftDetection" "${HOOK_BEFORE_DRIFT}"
    # Continue with drift check regardless of hook result
  fi

  local target_dir="/tmp/cdk-drift-${name}-$$"
  local drift_detected=false
  local drift_target_dir="${target_dir}/${project_path}"
  
  # Remove target directory if it exists
  rm -rf "$target_dir"
  
  # Set Git configuration
  setup_git_config
  
  # Clone repository for drift check
  log "Attempting to clone repository: $repository (branch: $git_ref) to $target_dir"
  if git clone --depth 1 --branch "$git_ref" "$repository" "$target_dir" 2>&1 | tee /tmp/git-clone-drift.log; then
    log "Repository cloned successfully for drift check"
    
    # Validate project path exists
    
    if [[ ! -d "${drift_target_dir}" ]]; then
      log "Project path '${project_path}' does not exist in cloned repository"
      log "Available directories in repository root:"
      find "$target_dir" -maxdepth 2 -type d | head -20
      update_status "${namespace}" "${name}" "$PHASE_FAILED" "Project path '${project_path}' not found in repository"
      rm -rf "$target_dir"
      return 1
    fi
    
    if ! cd "${drift_target_dir}"; then
      log "Failed to change to directory ${drift_target_dir}"
      rm -rf "$target_dir"
      return 1
    fi
    
    # Install dependencies if package.json exists
    if [[ -f "package.json" ]]; then
      log "Installing dependencies for drift check..."
      if ! npm ci --no-audit --no-fund; then
        log "Failed to install dependencies for drift check"
        rm -rf "$target_dir"
        return 1
      fi
    fi
    
    # Run CDK drift check
    # Note: 'cdk drift' detects changes made outside of CDK (e.g., manual changes in AWS Console)
    # The --fail flag causes exit code 1 if drift is detected
    local drift_cmd="npx cdk drift --fail"
    
    # Add stack name if specified
    if [[ -n "${stack_name}" && "${stack_name}" != "null" ]]; then
      drift_cmd="${drift_cmd} ${stack_name}"
      log "Running CDK drift check for stack: ${stack_name}"
    else
      drift_cmd="${drift_cmd} --all"
      log "Running CDK drift check for all stacks"
    fi
    
    log "Executing: ${drift_cmd}"
    local drift_output drift_exit_code
    drift_output=$(${drift_cmd} 2>&1)
    drift_exit_code=$?
    
    # With --fail flag:
    # Exit code 0 = no drift detected
    # Exit code 1 = drift detected (or command failed)
    if [[ $drift_exit_code -eq 0 ]]; then
      drift_detected=false
      log "No drift detected in ${name}"
      if [[ -n "$drift_output" ]]; then
        log "CDK drift output (last 50 lines):"
        log "$(echo "$drift_output" | tail -50)"
      fi
    else
      # Check if it's actual drift or command failure
      if echo "$drift_output" | grep -q "drift"; then
        drift_detected=true
        log "Drift detected in ${name}!"
        log "CDK drift output (first 50 lines):"
        log "$(echo "$drift_output" | head -50)"
        create_event "${namespace}" "${name}" "Warning" "DriftDetected" "Configuration drift detected in CDK stack" || true
      else
        # Command failed for other reasons
        drift_detected=false
        log "CDK drift command failed with exit code: $drift_exit_code"
        log "Error output (last 50 lines):"
        log "$(echo "$drift_output" | tail -50)"
      fi
    fi
    
    # Don't cleanup here - we might need it for remediation
  else
    log "Failed to clone repository for drift check. Error details:"
    cat /tmp/git-clone-drift.log || true
    log "Current directory: $(pwd)"
    log "Target directory was: $target_dir"
    update_status "${namespace}" "${name}" "$PHASE_FAILED" "Failed to clone repository for drift check"
    rm -rf "$target_dir"
    return 1
  fi
  
  # Update status with drift check results
  local timestamp phase message
  timestamp=$(current_timestamp)
  
  if [[ "$drift_detected" == "true" ]]; then
    phase="$PHASE_SUCCEEDED"  # Keep the main phase, but mark drift
    message="Drift detected - manual changes in AWS"
    log "Drift detected: AWS resources were modified outside of CDK"
    create_event "${namespace}" "${name}" "Warning" "DriftDetected" "Manual changes detected in AWS resources" || true
  else
    phase="$PHASE_SUCCEEDED"
    message="No drift detected"
  fi
  
  # Update status with drift check timestamp and results
  local status_json
  status_json=$(jq -n \
    --arg p "$phase" \
    --arg m "$message" \
    --arg t "$timestamp" \
    --argjson d "$drift_detected" \
    '{phase: $p, message: $m, lastDriftCheck: $t, driftDetected: $d}')
  
  kubectl -n "${namespace}" patch cdktsstack "${name}" --subresource=status --type=merge --patch "{\"status\":${status_json}}"
  
  log "Drift check completed for ${namespace}/${name}: drift_detected=${drift_detected}"
  
  # Get environment info for metrics
  local aws_region stack_name
  aws_region=$(echo "$resource" | jq -r '.spec.awsRegion // "us-east-1"')
  stack_name=$(echo "$resource" | jq -r '.spec.stackName')
  
  # Create labels for metrics
  local labels_json=$(jq -n \
    --arg ns "$namespace" \
    --arg n "$name" \
    --arg r "$aws_region" \
    --arg s "$stack_name" \
    '{namespace: $ns, resource_name: $n, aws_region: $r, stack_name: $s}')
  
  # Write drift status gauge metric (1 for drift detected, 0 for no drift)
  # Using group ensures old values are expired when new ones are written
  local drift_value
  if [[ "$drift_detected" == "true" ]]; then
    drift_value="1"
    # Also increment counter for total drifts detected
    echo "{\"name\":\"cdktsstack_drifts_detected_total\",\"action\":\"add\",\"value\":1,\"labels\":${labels_json}}" >> "${METRICS_PATH:-/metrics.txt}"
  else
    drift_value="0"
  fi
  
  # Set gauge metric for current drift status
  echo "{\"group\":\"drift-status\",\"name\":\"cdktsstack_drift_status\",\"action\":\"set\",\"value\":${drift_value},\"labels\":${labels_json}}" >> "${METRICS_PATH:-/metrics.txt}"
  
  # Pass additional env var to indicate whether drift was detected
  export DRIFT_DETECTED="${drift_detected}"
  if [[ -n "${HOOK_AFTER_DRIFT}" ]] && [[ "${HOOK_AFTER_DRIFT}" != "null" ]]; then
    execute_lifecycle_hook "${namespace}" "${name}" "afterDriftDetection" "${HOOK_AFTER_DRIFT}"
  fi
  
  # Unset credentials for safety
  cleanup_credentials
  
  # Cleanup
  rm -rf "$target_dir"
  
  # Return success
  return 0
}

# Function to check for Git changes and sync if needed
check_git_sync() {
  local namespace="$1"
  local name="$2"
  
  log "Starting Git sync check for ${namespace}/${name}"
  
  # Check if resource still exists before processing
  if ! kubectl -n "${namespace}" get cdktsstack "${name}" &>/dev/null; then
    log "Resource '${name}' no longer exists, skipping Git sync check"
    return 0
  fi
  
  # Load resource details
  local resource credentialsSecretName currentPhase
  resource=$(kubectl -n "${namespace}" get cdktsstack "${name}" -o json)
  currentPhase=$(echo "$resource" | jq -r '.status.phase // ""')
  
  # Only run Git sync check on resources in Succeeded phase
  if [[ "$currentPhase" != "$PHASE_SUCCEEDED" ]]; then
    log "Resource '${name}' is not in Succeeded phase (current: ${currentPhase}), skipping Git sync check"
    return 0
  fi
  
  # Update status to show Git sync check is in progress
  update_status "${namespace}" "${name}" "$PHASE_GIT_SYNC_CHECKING" "Checking for Git changes..."
  create_event "${namespace}" "${name}" "Normal" "GitSyncCheckStart" "Starting Git sync check" || true
  
  credentialsSecretName=$(echo "$resource" | jq -r '.spec.credentialsSecretName')
  
  if ! load_aws_credentials "${namespace}" "${credentialsSecretName}"; then
    log "Failed to load AWS credentials for Git sync check"
    update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "Git sync check failed - credential error"
    return 1
  fi
  
  # Get resource details for CDK operations
  local repository git_ref project_path stack_name aws_region
  repository=$(echo "$resource" | jq -r '.spec.source.git.repository')
  git_ref=$(echo "$resource" | jq -r '.spec.source.git.ref // "main"')
  project_path=$(echo "$resource" | jq -r '.spec.path // "."')
  stack_name=$(echo "$resource" | jq -r '.spec.stackName')
  aws_region=$(echo "$resource" | jq -r '.spec.awsRegion // "us-east-1"')
  
  # Set AWS region for CDK operations
  setup_aws_region "$aws_region"
  
  get_lifecycle_hooks "$resource"

  # Set CDK environment variables for hooks
  export_cdk_env_for_hooks "${stack_name}" "${project_path}" "${repository}" "${git_ref}"

  # Execute beforeGitSync hook if configured
  if [[ -n "${HOOK_BEFORE_GIT_SYNC}" ]] && [[ "${HOOK_BEFORE_GIT_SYNC}" != "null" ]]; then
    execute_lifecycle_hook "${namespace}" "${name}" "beforeGitSync" "${HOOK_BEFORE_GIT_SYNC}"
  fi

  local target_dir="/tmp/cdk-gitsync-${name}-$$"
  local has_changes=false
  
  # Remove target directory if it exists
  rm -rf "$target_dir"
  
  # Clone repository
  log "Cloning repository: $repository (branch: $git_ref)"
  if git clone --depth 1 --branch "$git_ref" "$repository" "$target_dir" 2>&1 | tee /tmp/git-clone-sync.log; then
    log "Repository cloned successfully for Git sync check"
    
    local sync_target_dir="${target_dir}/${project_path}"
    if [[ ! -d "${sync_target_dir}" ]]; then
      log "Project path '${project_path}' does not exist in cloned repository"
      rm -rf "$target_dir"
      return 1
    fi
    
    if ! cd "${sync_target_dir}"; then
      log "Failed to change to directory ${sync_target_dir}"
      rm -rf "$target_dir"
      return 1
    fi
    
    # Install dependencies if package.json exists
    if [[ -f "package.json" ]]; then
      log "Installing dependencies..."
      if ! npm ci --no-audit --no-fund; then
        log "Failed to install dependencies"
        rm -rf "$target_dir"
        return 1
      fi
    fi
    
    # Export CDK environment variables
    export CDK_DEFAULT_ACCOUNT="${CDK_DEFAULT_ACCOUNT:-}"
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-${CDK_DEFAULT_ACCOUNT}}"
    export AWS_ACCOUNT="${AWS_ACCOUNT:-${CDK_DEFAULT_ACCOUNT}}"
    
    # Run CDK diff to check for changes (with --fail flag)
    # CDK diff --fail returns exit code 1 if there are differences
    local diff_cmd="npx cdk diff --fail"
    if [[ -n "${stack_name}" && "${stack_name}" != "null" ]]; then
      diff_cmd="${diff_cmd} ${stack_name}"
    else
      diff_cmd="${diff_cmd} --all"
    fi
    
    log "Checking for changes: ${diff_cmd}"
    local diff_output diff_exit_code
    diff_output=$(${diff_cmd} 2>&1)
    diff_exit_code=$?
    
    # CDK diff --fail returns 0 if no changes, 1 if there are differences
    if [[ $diff_exit_code -eq 1 ]]; then
      has_changes=true
      log "Git changes detected - new changes need to be deployed"
      log "Diff output (first 30 lines):"
      echo "$diff_output" | head -30
      
      # Create event for changes detected
      create_event "${namespace}" "${name}" "Normal" "GitChangesDetected" "New changes detected in Git repository" || true
    else
      log "No Git changes detected"
    fi
    
    # Create labels for metrics
    local labels_json=$(jq -n \
      --arg ns "$namespace" \
      --arg n "$name" \
      --arg r "$aws_region" \
      --arg s "$stack_name" \
      '{namespace: $ns, resource_name: $n, aws_region: $r, stack_name: $s}')
    
    # Write Git sync status metric
    local changes_value
    if [[ "$has_changes" == "true" ]]; then
      changes_value="1"
      # Also increment counter for total changes detected
      echo "{\"name\":\"cdktsstack_git_changes_detected_total\",\"action\":\"add\",\"value\":1,\"labels\":${labels_json}}" >> "${METRICS_PATH:-/metrics.txt}"
    else
      changes_value="0"
    fi
    
    # Set gauge metric for current Git sync status
    echo "{\"group\":\"git-sync-status\",\"name\":\"cdktsstack_git_sync_pending\",\"action\":\"set\",\"value\":${changes_value},\"labels\":${labels_json}}" >> "${METRICS_PATH:-/metrics.txt}"
    
    # Check if auto redeploy is enabled and deploy if changes detected
    local autoRedeployAllowed deployAllowed
    autoRedeployAllowed=$(echo "$resource" | jq -r '.spec.actions.autoRedeploy // "false"')
    deployAllowed=$(echo "$resource" | jq -r '.spec.actions.deploy')
    
    if [[ "$has_changes" == "true" && "$autoRedeployAllowed" == "true" && "$deployAllowed" == "true" ]]; then
      log "Auto redeploy is enabled, deploying changes from Git..."
      update_status "${namespace}" "${name}" "$PHASE_DEPLOYING" "Auto-deploying changes from Git..."
      create_event "${namespace}" "${name}" "Normal" "AutoRedeployStart" "Starting auto deployment of Git changes" || true
      
      # Deploy changes
      local deploy_cmd="npx cdk deploy"
      if [[ -n "${stack_name}" && "${stack_name}" != "null" ]]; then
        deploy_cmd="${deploy_cmd} ${stack_name}"
      else
        deploy_cmd="${deploy_cmd} --all"
      fi
      deploy_cmd="${deploy_cmd} --require-approval never"
      
      log "Executing auto redeploy: ${deploy_cmd}"
      local deploy_output deploy_exit_code
      log "=== AUTO REDEPLOY CDK OUTPUT START ==="
      deploy_output=$(${deploy_cmd} 2>&1)
      deploy_exit_code=$?
      log "$deploy_output"
      log "=== AUTO REDEPLOY CDK OUTPUT END ==="
      
      if [[ $deploy_exit_code -eq 0 ]]; then
        log "Auto redeploy completed successfully"
        update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "Auto deployment from Git completed"
        create_event "${namespace}" "${name}" "Normal" "AutoRedeploySuccess" "Git changes deployed successfully" || true
      else
        log "Auto redeploy failed with exit code: $deploy_exit_code"
        # Don't set to Failed - let it stay in Succeeded with pending changes
        # This prevents infinite retry loops from main hook
        update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "Auto deployment failed - Git changes pending manual deployment"
        create_event "${namespace}" "${name}" "Warning" "AutoRedeployFailure" "Auto-deploy failed, manual deployment may be required" || true
      fi
    elif [[ "$has_changes" == "true" ]]; then
      if [[ "$autoRedeployAllowed" == "true" && "$deployAllowed" == "false" ]]; then
        log "Git changes detected but deploy is disabled"
        update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "Git changes pending - deploy disabled"
      else
        log "Git changes detected but autoRedeploy is disabled"
        update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "Git changes pending - manual deployment required"
      fi
    else
      # No changes detected, restore Succeeded phase
      update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "No Git changes detected"
    fi
    
  else
    log "Failed to clone repository for Git sync check"
    cat /tmp/git-clone-sync.log || true
    update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "Git sync check failed - clone error"
    rm -rf "$target_dir"
    return 1
  fi
  
  # Pass additional env var to indicate whether changes were detected
  export GIT_CHANGES_DETECTED="${has_changes}"
  if [[ -n "${HOOK_AFTER_GIT_SYNC}" ]] && [[ "${HOOK_AFTER_GIT_SYNC}" != "null" ]]; then
    execute_lifecycle_hook "${namespace}" "${name}" "afterGitSync" "${HOOK_AFTER_GIT_SYNC}"
  fi
  
  # Unset credentials for safety
  cleanup_credentials
  
  # Cleanup
  rm -rf "$target_dir"
  
  return 0
}

# Function to deploy CDK stack
deploy_cdk_stack() {
  local namespace="$1"
  local name="$2"
  local current_phase="$3"
  
  log "AWS credentials loaded successfully. Starting reconciliation state machine..."
  
  # Debug: Show initial environment state
  debug_log "Initial CDK environment state:"
  debug_log "  CDK_DEFAULT_ACCOUNT=${CDK_DEFAULT_ACCOUNT:-NOT_SET_INITIALLY}"
  debug_log "  AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-NOT_SET_INITIALLY}"
  debug_log "  AWS_ACCOUNT=${AWS_ACCOUNT:-NOT_SET_INITIALLY}"
  
  # Get resource spec for Git information (with retry to avoid race conditions)
  local resource repository git_ref project_path aws_region
  for i in {1..3}; do
    resource=$(kubectl -n "${namespace}" get cdktsstack "${name}" -o json 2>/dev/null)
    if [[ -n "$resource" ]]; then
      break
    fi
    log "Retry $i: Failed to get resource, waiting 1 second..."
    sleep 1
  done
  
  if [[ -z "$resource" ]]; then
    log "Failed to get resource after retries, aborting"
    return 1
  fi
  
  repository=$(echo "$resource" | jq -r '.spec.source.git.repository')
  git_ref=$(echo "$resource" | jq -r '.spec.source.git.ref // "main"')
  project_path=$(echo "$resource" | jq -r '.spec.path // "."')
  aws_region=$(echo "$resource" | jq -r '.spec.awsRegion // "us-east-1"')
  
  # Set AWS region for CDK operations
  setup_aws_region "$aws_region"
  
  # Log current phase for debugging race conditions
  debug_log "Starting state machine with current_phase='${current_phase}'"
  
  # Simplified State Machine for Reconciliation
  case ${current_phase} in
    "" | "$PHASE_FAILED")
      log "Phase: Starting new reconciliation, moving to Cloning."
      # Clean up any existing temporary directories to ensure fresh start
      rm -rf "/tmp/cdk-project-${name}" "/tmp/cdk-gitsync-${name}"* "/tmp/cdk-drift-${name}"* 2>/dev/null || true
      update_status "${namespace}" "${name}" "$PHASE_CLONING" "Cloning repository..."
      ;;
    "$PHASE_CLONING")
      log "Phase: Cloning repository ${repository} (ref: ${git_ref})"
      local target_dir="/tmp/cdk-project-${name}"
      
      # Remove target directory if it exists (ensure clean state)
      rm -rf "$target_dir"
      
      # Set Git configuration for container environment
      setup_git_config
      
      # Clone repository
      if git clone --depth 1 --branch "$git_ref" "$repository" "$target_dir"; then
        log "Repository cloned successfully"
        update_status "${namespace}" "${name}" "$PHASE_INSTALLING" "Installing dependencies..."
      else
        log "Failed to clone repository"
        update_status "${namespace}" "${name}" "$PHASE_FAILED" "Failed to clone repository ${repository}"
        return 1
      fi
      ;;
    "$PHASE_INSTALLING")
      log "Phase: Installing dependencies in /tmp/cdk-project-${name}/${project_path}"
      local target_dir="/tmp/cdk-project-${name}/${project_path}"
      
      # Check if target directory exists
      if [[ ! -d "${target_dir}" ]]; then
        log "Error: Project path '${project_path}' does not exist in cloned repository"
        log "Available directories in repository root:"
        find "/tmp/cdk-project-${name}" -maxdepth 2 -type d 2>/dev/null | head -10 || true
        log "This is likely a configuration error in the CdkTsStack spec.path field"
        update_status "${namespace}" "${name}" "$PHASE_FAILED" "Project path '${project_path}' not found in repository. Check spec.path field."
        return 1
      fi

      cd "${target_dir}"

      # Check if package.json exists
      if [[ -f "package.json" ]]; then
        log "Found package.json, running npm ci..."
        
        # Install dependencies
        if npm ci --no-audit --no-fund; then
          log "Dependencies installed successfully"
          update_status "${namespace}" "${name}" "$PHASE_DEPLOYING" "Dependencies installed, preparing deployment..."
        else
          log "Failed to install dependencies"
          update_status "${namespace}" "${name}" "$PHASE_FAILED" "Failed to install dependencies"
          return 1
        fi
      else
        log "No package.json found, skipping npm ci"
        update_status "${namespace}" "${name}" "$PHASE_DEPLOYING" "No dependencies to install, preparing deployment..."
      fi
      ;;
    "$PHASE_DEPLOYING")
      log "Phase: Running CDK deploy..."
      local target_dir="/tmp/cdk-project-${name}/${project_path}"
      local stack_name
      stack_name=$(echo "$resource" | jq -r '.spec.stackName')
      
      # Check if target directory exists
      if [[ ! -d "${target_dir}" ]]; then
        log "Error: Project path '${project_path}' does not exist in cloned repository"
        log "Available directories in repository root:"
        find "/tmp/cdk-project-${name}" -maxdepth 2 -type d 2>/dev/null | head -10 || true
        log "This is likely a configuration error in the CdkTsStack spec.path field"
        update_status "${namespace}" "${name}" "$PHASE_FAILED" "Project path '${project_path}' not found in repository. Check spec.path field."
        return 1
      fi

      cd "${target_dir}"
      
      # Get additional CDK parameters
      local cdk_context cdk_params
      cdk_context=$(echo "$resource" | jq -r '.spec.cdkContext // []')
      cdk_params="--require-approval never"
      
      # Add context parameters if specified
      if [[ "$cdk_context" != "null" && "$cdk_context" != "[]" ]]; then
        local context_items
        context_items=$(echo "$cdk_context" | jq -r '.[]' 2>/dev/null || true)
        while IFS= read -r context_item; do
          if [[ -n "$context_item" && "$context_item" != "null" ]]; then
            cdk_params="$cdk_params --context $context_item"
          fi
        done <<< "$context_items"
      fi
      
      # Debug: Show CDK app configuration
      debug_log "=== CDK DIAGNOSTICS START ==="
      debug_log "Stack name parameter: '${stack_name}'"
      debug_log "Working directory: $(pwd)"
      debug_log "Environment variables:"
      debug_log "  AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-NOT_SET}"
      debug_log "  CDK_DEFAULT_REGION=${CDK_DEFAULT_REGION:-NOT_SET}"
      debug_log "  CDK_DEFAULT_ACCOUNT=${CDK_DEFAULT_ACCOUNT:-NOT_SET}"
      debug_log "  AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-NOT_SET}"
      debug_log "  AWS_ACCOUNT=${AWS_ACCOUNT:-NOT_SET}"
      debug_log "  AWS_REGION=${AWS_REGION:-NOT_SET}"
      debug_log "  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:+SET}"
      debug_log "  AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:+[MASKED]}"
      
      if [[ -f "cdk.json" ]]; then
        debug_log "CDK configuration (cdk.json):"
        debug_log "$(cat cdk.json)"
      else
        debug_log "WARNING: No cdk.json found"
      fi
      # Prepare CDK deploy command
      local cdk_deploy_cmd="cdk deploy"
      if [[ -n "${stack_name}" && "${stack_name}" != "null" ]]; then
        cdk_deploy_cmd="${cdk_deploy_cmd} ${stack_name}"
        log "Deploying specific stack: '${stack_name}'"
      else
        cdk_deploy_cmd="${cdk_deploy_cmd} --all"
        log "Deploying all stacks (no specific stack name provided)"
      fi
      cdk_deploy_cmd="${cdk_deploy_cmd} ${cdk_params}"
      
      # Export CDK environment variables explicitly before running command
      export CDK_DEFAULT_ACCOUNT="${CDK_DEFAULT_ACCOUNT:-}"
      export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-${CDK_DEFAULT_ACCOUNT}}"
      export AWS_ACCOUNT="${AWS_ACCOUNT:-${CDK_DEFAULT_ACCOUNT}}"
      setup_aws_region "${aws_region}"
      
      # Debug: Show all AWS/CDK environment variables before command
      debug_log "All AWS environment variables before CDK command:"
      debug_log "$(env | grep -E "^(AWS_|CDK_)" | sort)"
      
      # Debug: Show individual credential variables
      debug_log "Individual credential check:"
      debug_log "  AWS_ACCESS_KEY_ID length: ${#AWS_ACCESS_KEY_ID}"
      debug_log "  AWS_SECRET_ACCESS_KEY length: ${#AWS_SECRET_ACCESS_KEY}"
      debug_log "  AWS_SESSION_TOKEN length: $([ -n "${AWS_SESSION_TOKEN:-}" ] && echo ${#AWS_SESSION_TOKEN} || echo 0)"
      

      if [[ -n "$resource" ]]; then
        get_lifecycle_hooks "$resource"

        # Set CDK environment variables for hooks
        export_cdk_env_for_hooks "${stack_name}" "${project_path}" "${repository}" "${git_ref}"

        # Execute beforeDeploy hook if configured
        if [[ -n "${HOOK_BEFORE_DEPLOY}" ]] && [[ "${HOOK_BEFORE_DEPLOY}" != "null" ]]; then
          execute_lifecycle_hook "${namespace}" "${name}" "beforeDeploy" "${HOOK_BEFORE_DEPLOY}"
          # Continue with deployment regardless of hook result
        fi
      fi

      
      # Run actual CDK deploy command with real-time output
      log "Executing: ${cdk_deploy_cmd}"
      log "CDK environment: CDK_DEFAULT_ACCOUNT=${CDK_DEFAULT_ACCOUNT:-]} AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID} AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
      
      # Create event for deployment start
      create_event "${namespace}" "${name}" "Normal" "StackDeployStart" "Starting CDK deployment: ${stack_name:-all stacks}" || true
      
      # Execute CDK deploy with explicit environment and capture both output and exit code
      local deploy_output deploy_exit_code
      log "=== CDK DEPLOY OUTPUT START ==="
      
      # Verify credentials are available before running CDK
      if [[ -z "${AWS_ACCESS_KEY_ID}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY}" ]]; then
        log "ERROR: AWS credentials not found in current shell environment!"
        log "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:+SET}"
        log "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:+SET}"
        deploy_output="ERROR: AWS credentials not available in shell environment"
        deploy_exit_code=1
      else
        log "Credentials verified, running CDK command..."
        # Run CDK command directly (credentials already exported in current shell)
        # Use set +e to disable exit on error for this command
        set +e
        deploy_output=$(${cdk_deploy_cmd} 2>&1)
        deploy_exit_code=$?
        set -e  # Re-enable exit on error
      fi
      
      # Show output in logs
      log "$deploy_output"
      log "=== CDK DEPLOY OUTPUT END ==="
      
      if [[ $deploy_exit_code -eq 0 ]]; then
        log "CDK deploy completed successfully (exit code: $deploy_exit_code)"
        
        if [[ -n "${HOOK_AFTER_DEPLOY}" ]] && [[ "${HOOK_AFTER_DEPLOY}" != "null" ]]; then
          execute_lifecycle_hook "${namespace}" "${name}" "afterDeploy" "${HOOK_AFTER_DEPLOY}"
        fi

        update_status "${namespace}" "${name}" "$PHASE_SUCCEEDED" "CDK stack deployed successfully"
        create_event "${namespace}" "${name}" "Normal" "StackDeploySuccess" "CDK stack deployed successfully" || true
      else
        log "CDK deploy failed with exit code: $deploy_exit_code"
        
        # Check for specific error types and provide helpful guidance
        local error_summary
        if echo "$deploy_output" | grep -q "no credentials have been configured"; then
          error_summary="AWS credentials not configured. Please verify that the credentials secret '${credentialsSecretName}' exists and contains valid AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
          log "ERROR: AWS credentials problem detected - check secret '${credentialsSecretName}' in namespace '${namespace}'"
          log "Troubleshooting: kubectl get secret ${credentialsSecretName} -n ${namespace}"
        elif echo "$deploy_output" | grep -q "Unable to resolve AWS account"; then
          error_summary="Unable to resolve AWS account. Check credentials permissions and ensure they have access to AWS account. Run 'aws sts get-caller-identity' to test credentials"
        elif echo "$deploy_output" | grep -q "AccessDenied"; then
          error_summary="AWS access denied. The provided credentials lack necessary permissions for CDK operations. Required permissions: CloudFormation, IAM, and service-specific permissions"
        elif echo "$deploy_output" | grep -q "ValidationError"; then
          error_summary="CDK stack validation failed. Check your CDK code for syntax errors or invalid resource configurations"
        elif echo "$deploy_output" | grep -q "npm ERR\|dependency"; then
          error_summary="Node.js dependency installation failed. Check package.json and network connectivity for npm packages"
        elif echo "$deploy_output" | grep -q "Region"; then
          error_summary="AWS region configuration issue. Verify region '${aws_region}' is valid and accessible with your credentials"
        else
          # Generic error parsing with more context
          error_summary=$(echo "$deploy_output" | grep -E "(Error|Failed|error)" | tail -3 | tr '\n' '; ' | sed 's/; $//')
          if [[ -z "$error_summary" ]]; then
            error_summary="CDK deploy failed (exit code: $deploy_exit_code). Check operator logs for detailed error information"
          fi
        fi
        
        log "Setting status to Failed with error: ${error_summary}"
        update_status "${namespace}" "${name}" "$PHASE_FAILED" "CDK deploy failed: ${error_summary}"
        create_event "${namespace}" "${name}" "Warning" "StackDeployFailure" "CDK deployment failed: ${error_summary}" || true
        return 1
      fi
      log "Reconciliation successful."
      ;;
    "$PHASE_SUCCEEDED")
      log "Phase: Already Succeeded. No action needed."
      ;;
    "$PHASE_DRIFT_CHECKING")
      log "Phase: Drift check in progress. No action needed."
      ;;
    "$PHASE_GIT_SYNC_CHECKING")
      log "Phase: Git sync check in progress. No action needed."
      ;;
    "$PHASE_DELETING")
      log "Phase: Resource is being deleted. No action needed."
      ;;
    *)
      log "WARNING: Unknown phase '${current_phase}'. This may be a race condition. Skipping processing."
      debug_log "Available phases are: '', Failed, Cloning, Installing, Deploying, Succeeded, DriftChecking, GitSyncChecking, Deleting"
      return 0  # Don't fail, just skip processing to avoid race conditions
      ;;
  esac
}

# Function to destroy CDK stack
destroy_cdk_stack() {
  local namespace="$1"
  local name="$2"
  
  log "Running CDK destroy for ${name}..."
  
  # Get resource spec for Git information
  local resource repository git_ref project_path stack_name aws_region
  resource=$(kubectl -n "${namespace}" get cdktsstack "${name}" -o json 2>/dev/null)
  
  if [[ -z "$resource" ]]; then
    log "Resource ${name} no longer exists, skipping destroy"
    return 0
  fi
  
  repository=$(echo "$resource" | jq -r '.spec.source.git.repository')
  git_ref=$(echo "$resource" | jq -r '.spec.source.git.ref // "main"')
  project_path=$(echo "$resource" | jq -r '.spec.path // "."')
  stack_name=$(echo "$resource" | jq -r '.spec.stackName')
  aws_region=$(echo "$resource" | jq -r '.spec.awsRegion // "us-east-1"')
  
  # Set AWS region for CDK operations
  setup_aws_region "$aws_region"
  
  local target_dir="/tmp/cdk-destroy-${name}-$$"
  
  # Remove target directory if it exists
  rm -rf "$target_dir"
  
  # Set Git configuration
  setup_git_config
  
  # Clone repository for destroy operation
  if git clone --depth 1 --branch "$git_ref" "$repository" "$target_dir"; then
    log "Repository cloned for destroy operation"
    
    # Check if target directory exists
    local destroy_target_dir="${target_dir}/${project_path}"
    if [[ ! -d "${destroy_target_dir}" ]]; then
      log "Warning: Project path '${project_path}' does not exist in cloned repository, skipping destroy"
      rm -rf "$target_dir"
      return 0
    fi
    
    if ! cd "${destroy_target_dir}"; then
      log "Warning: Failed to change to directory ${destroy_target_dir}, skipping destroy"
      rm -rf "$target_dir"
      return 0
    fi
    
    # Install dependencies if package.json exists
    if [[ -f "package.json" ]]; then
      log "Installing dependencies for destroy..."
      if ! npm ci --no-audit --no-fund; then
        log "Warning: Failed to install dependencies for destroy, but continuing..."
      fi
    fi
    
    # Prepare CDK destroy command
    local cdk_destroy_cmd="npx cdk destroy"
    if [[ -n "${stack_name}" && "${stack_name}" != "null" ]]; then
      cdk_destroy_cmd="${cdk_destroy_cmd} ${stack_name}"
      log "Destroying specific stack: '${stack_name}'"
    else
      cdk_destroy_cmd="${cdk_destroy_cmd} --all"
      log "Destroying all stacks (no specific stack name provided)"
    fi
    cdk_destroy_cmd="${cdk_destroy_cmd} --force"
    
    # Debug: Show working directory and environment before destroy
    debug_log "=== CDK DESTROY DIAGNOSTICS START ==="
    debug_log "Working directory: $(pwd)"
    debug_log "CDK project files:"
    debug_log "$(ls -la)"
    debug_log "Environment variables:"
    debug_log "$(env | grep -E "^(AWS_|CDK_)" | sort)"
    debug_log "=== CDK DESTROY DIAGNOSTICS END ==="
    
    get_lifecycle_hooks "$resource"

    # Set CDK environment variables for hooks
    export_cdk_env_for_hooks "${stack_name}" "${project_path}" "${repository}" "${git_ref}"

    # Execute beforeDestroy hook if configured
    if [[ -n "${HOOK_BEFORE_DESTROY}" ]] && [[ "${HOOK_BEFORE_DESTROY}" != "null" ]]; then
      execute_lifecycle_hook "${namespace}" "${name}" "beforeDestroy" "${HOOK_BEFORE_DESTROY}"
    fi

    # Run actual CDK destroy command
    log "Executing: ${cdk_destroy_cmd}"
    log "=== CDK DESTROY OUTPUT START ==="
    
    local destroy_output destroy_exit_code
    destroy_output=$(${cdk_destroy_cmd} 2>&1)
    destroy_exit_code=$?
    
    # Show full output in logs
    log "$destroy_output"
    log "=== CDK DESTROY OUTPUT END ==="
    
    if [[ $destroy_exit_code -eq 0 ]]; then
      log "CDK destroy completed successfully"
      log "CDK destroy output (last 10 lines):"
      log "$(echo "$destroy_output" | tail -10)"
      
      if [[ -n "${HOOK_AFTER_DESTROY}" ]] && [[ "${HOOK_AFTER_DESTROY}" != "null" ]]; then
        execute_lifecycle_hook "${namespace}" "${name}" "afterDestroy" "${HOOK_AFTER_DESTROY}"
      fi
    else
      log "CDK destroy failed with exit code: $destroy_exit_code, but continuing with cleanup"
      log "CDK destroy error output (last 30 lines):"
      log "$(echo "$destroy_output" | tail -30)"
      local error_summary
      error_summary=$(echo "$destroy_output" | grep -E "(Error|Failed|error)" | tail -2 | tr '\n' '; ' | sed 's/; $//')
      log "Destroy error summary: ${error_summary}"
    fi
    
    # Cleanup cloned repository
    rm -rf "$target_dir"
    
    log "CDK destroy completed for ${name}"
  else
    log "Failed to clone repository for destroy operation, but continuing..."
  fi
} 