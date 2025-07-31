#!/usr/bin/env bash

set -euo pipefail

# Load common libraries
source /hooks/lib/common.sh
source /hooks/lib/aws.sh
source /hooks/lib/kubernetes.sh
source /hooks/lib/cdkstack.sh
source /hooks/lib/lifecycle.sh

# Function to handle scheduled drift checks
handle_drift_check_schedule() {
  log "Starting drift checks..."
  log "METRICS_PATH is: ${METRICS_PATH:-not set}"
  
  # First, expire all previous drift metrics in the group
  # This ensures that metrics for deleted resources are removed
  echo '{"group":"drift-status", "action":"expire"}' >> "${METRICS_PATH:-/metrics.txt}"
  
  # Get all CdkTsStack resources from all namespaces
  local resources
  resources=$(kubectl get cdktsstacks --all-namespaces -o json | jq -c '.items[]' 2>/dev/null || echo "")
  
  if [[ -z "$resources" ]]; then
    log "No CdkTsStack resources found"
    return 0
  fi
  
  # Save resources to temporary file
  local temp_file="/tmp/drift_resources_$$"
  echo "$resources" > "$temp_file"
  
  # Process each resource
  while IFS= read -r resource; do
    local name namespace currentPhase driftDetectionAllowed awsRegion stackName
    name=$(echo "$resource" | jq -r '.metadata.name')
    namespace=$(echo "$resource" | jq -r '.metadata.namespace')
    currentPhase=$(echo "$resource" | jq -r '.status.phase // ""')
    driftDetectionAllowed=$(echo "$resource" | jq -r '.spec.actions.driftDetection')
    awsRegion=$(echo "$resource" | jq -r '.spec.awsRegion // "us-east-1"')
    stackName=$(echo "$resource" | jq -r '.spec.stackName')
    
    # Check if drift detection is allowed for this resource
    if [[ "$driftDetectionAllowed" == "false" ]]; then
      log "Drift detection is disabled for ${namespace}/${name}, skipping"
      continue
    fi
    
    if [[ "$currentPhase" == "$PHASE_SUCCEEDED" ]]; then
      log "Running drift check for ${namespace}/${name}..."
      
      # Run drift check but don't exit on failure
      if run_drift_check "$namespace" "$name"; then
        log "Drift check succeeded for ${namespace}/${name}"
      else
        log "WARNING: Drift check failed for ${namespace}/${name}, continuing..."
      fi
      
      # Write metric for total drift checks with environment labels
      local labels_json=$(jq -n \
        --arg ns "$namespace" \
        --arg n "$name" \
        --arg r "$awsRegion" \
        --arg s "$stackName" \
        '{namespace: $ns, resource_name: $n, aws_region: $r, stack_name: $s}')
      
      echo "{\"name\":\"cdktsstack_drift_checks_total\",\"action\":\"add\",\"value\":1,\"labels\":${labels_json}}" >> "${METRICS_PATH:-/metrics.txt}"
    else
      log "Skipping ${namespace}/${name}: not in Succeeded phase (current: ${currentPhase})"
    fi
  done < "$temp_file"
  
  rm -f "$temp_file"
  
  log "Drift checks completed"
  return 0
}

# Function to handle scheduled Git sync checks
handle_git_sync_schedule() {
  log "Starting Git sync checks..."
  
  # First, expire all previous git sync metrics in the group
  echo '{"group":"git-sync-status", "action":"expire"}' >> "${METRICS_PATH:-/metrics.txt}"
  
  # Get all CdkTsStack resources from all namespaces
  local resources
  resources=$(kubectl get cdktsstacks --all-namespaces -o json | jq -c '.items[]' 2>/dev/null || echo "")
  
  if [[ -z "$resources" ]]; then
    log "No CdkTsStack resources found"
    return 0
  fi
  
  # Save resources to temporary file
  local temp_file="/tmp/git_sync_resources_$$"
  echo "$resources" > "$temp_file"
  
  # Process each resource
  while IFS= read -r resource; do
    local name namespace currentPhase deployAllowed
    name=$(echo "$resource" | jq -r '.metadata.name')
    namespace=$(echo "$resource" | jq -r '.metadata.namespace')
    currentPhase=$(echo "$resource" | jq -r '.status.phase // ""')
    deployAllowed=$(echo "$resource" | jq -r '.spec.actions.deploy')
    
    # Check if deploy is allowed for this resource
    if [[ "$deployAllowed" == "false" ]]; then
      log "Deploy is disabled for ${namespace}/${name}, skipping Git sync check"
      continue
    fi
    
    if [[ "$currentPhase" == "$PHASE_SUCCEEDED" ]]; then
      log "Running Git sync check for ${namespace}/${name}..."
      
      # Run Git sync check
      if check_git_sync "$namespace" "$name"; then
        log "Git sync check succeeded for ${namespace}/${name}"
      else
        log "WARNING: Git sync check failed for ${namespace}/${name}, continuing..."
      fi
    elif [[ "$currentPhase" == "$PHASE_GIT_SYNC_CHECKING" ]]; then
      log "Skipping ${namespace}/${name}: already in GitSyncChecking phase"
    else
      log "Skipping ${namespace}/${name}: not in Succeeded phase (current: ${currentPhase})"
    fi
  done < "$temp_file"
  
  rm -f "$temp_file"
  
  log "Git sync checks completed"
  return 0
}

# --- Main Logic ---

if [[ "${1-}" == "--config" ]]; then
  # Configuration is read by shell-operator to discover hooks.
  # Get cron expression from environment variable
  drift_cron="${DRIFT_CHECK_CRON:-*/30 * * * *}"
  git_sync_cron="${GIT_SYNC_CHECK_CRON:-*/5 * * * *}"
  
  log "Using drift check cron: ${drift_cron}" >&2
  log "Using Git sync check cron: ${git_sync_cron}" >&2
  
  cat <<EOF
configVersion: v1
schedule:
- name: "drift-check"
  crontab: "${drift_cron}"
  allowFailure: true
  group: "drift-metrics"
- name: "git-sync-check"
  crontab: "${git_sync_cron}"
  allowFailure: true
  group: "git-sync-metrics"
EOF
else
  # Hook logic is executed when an event occurs.
  log "--- Drift checker hook execution start ---"
  
  check_required_env
  
  # Check if this is a schedule event
  first_context_type=$(jq -r '.[0].type // ""' $BINDING_CONTEXT_PATH)
  first_context_binding=$(jq -r '.[0].binding // ""' $BINDING_CONTEXT_PATH)
  
  # Check for schedule event using either type or binding
  if [[ "$first_context_binding" == "drift-check" ]]; then
    log "Drift check schedule event detected"
    handle_drift_check_schedule
  elif [[ "$first_context_binding" == "git-sync-check" ]]; then
    log "Git sync check schedule event detected"
    handle_git_sync_schedule
  else
    log "Non-schedule event detected (type=$first_context_type, binding=$first_context_binding), ignoring..."
  fi
  
  log "--- Drift checker hook execution finished ---"
fi 