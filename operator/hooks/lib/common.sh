#!/usr/bin/env bash

# Common constants and utility functions for CDK Stack Operator

# The finalizer name, must be unique
readonly FINALIZER="cdkstack.awscdk.dev/finalizer"

# Phase constants
readonly PHASE_CLONING="Cloning"
readonly PHASE_INSTALLING="Installing"
readonly PHASE_DEPLOYING="Deploying"
readonly PHASE_SUCCEEDED="Succeeded"
readonly PHASE_FAILED="Failed"
readonly PHASE_DELETING="Deleting"
readonly PHASE_DRIFT_CHECKING="DriftChecking"
readonly PHASE_GIT_SYNC_CHECKING="GitSyncChecking"

# Log helper function
log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*"
}

# Debug log helper function - only logs when DEBUG_MODE=true
debug_log() {
  if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
    log "[DEBUG] $*"
  fi
}

# Error handling
die() {
  log "ERROR: $*" >&2
  exit 1
}

# Check if required environment variables are set
check_required_env() {
  if [[ -z "${BINDING_CONTEXT_PATH:-}" ]]; then
    die "BINDING_CONTEXT_PATH environment variable is not set. This indicates a shell-operator configuration issue. Please check operator deployment and logs"
  fi
}

# Generate current timestamp
current_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Clean up credentials for safety
cleanup_credentials() {
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# Setup Git configuration for CDK operations
setup_git_config() {
  git config --global user.email "belov38@gmail.com"
  git config --global user.name "AWS CDK Operator"
  git config --global init.defaultBranch main
}

# Setup AWS region environment variables
setup_aws_region() {
  local region="$1"
  export AWS_DEFAULT_REGION="$region"
  export CDK_DEFAULT_REGION="$region"
}

# Write metric to the metrics file
# Usage: write_metric <operation> <metric_name> <metric_help> <value> [labels_json] [group]
# Operations: "add" for counter, "set" for gauge, "observe" for histogram
write_metric() {
  local operation="$1"
  local metric_name="$2"
  local metric_help="$3"
  local value="$4"
  local labels_json="${5:-}"  # Optional: JSON object with labels, e.g., '{"namespace":"default","phase":"Failed"}'
  local group="${6:-}"         # Optional: shell-operator group name for grouping metrics

  debug_log "write_metric called with: op=$operation, name=$metric_name, value=$value, group=$group"

  # Validate required parameters
  if [[ -z "$operation" ]] || [[ -z "$metric_name" ]] || [[ -z "$value" ]]; then
    log "ERROR: write_metric requires at least operation, name, and value"
    return 1
  fi

  # Check if METRICS_PATH is set
  if [[ -z "${METRICS_PATH:-}" ]]; then
    debug_log "METRICS_PATH is not set, skipping metric write"
    return 0
  fi

  debug_log "METRICS_PATH is set to: $METRICS_PATH"

  # Validate labels JSON if provided
  if [[ -n "$labels_json" ]]; then
    if ! echo "$labels_json" | jq . >/dev/null 2>&1; then
      log "ERROR: Invalid JSON for labels: $labels_json"
      return 1
    fi
  fi

  # Build the metric JSON based on whether group is provided
  local metric_json
  if [[ -n "$group" ]]; then
    debug_log "Building metric JSON with group"
    if [[ -n "$labels_json" ]]; then
      metric_json=$(jq -n \
        --arg name "$metric_name" \
        --arg op "$operation" \
        --arg value "$value" \
        --arg group "$group" \
        --argjson labels "$labels_json" \
        '{name: $name, action: $op, value: ($value | tonumber), group: $group, labels: $labels}')
    else
      metric_json=$(jq -n \
        --arg name "$metric_name" \
        --arg op "$operation" \
        --arg value "$value" \
        --arg group "$group" \
        '{name: $name, action: $op, value: ($value | tonumber), group: $group}')
    fi
  else
    debug_log "Building metric JSON without group"
    if [[ -n "$labels_json" ]]; then
      metric_json=$(jq -n \
        --arg name "$metric_name" \
        --arg op "$operation" \
        --arg value "$value" \
        --argjson labels "$labels_json" \
        '{name: $name, action: $op, value: ($value | tonumber), labels: $labels}')
    else
      metric_json=$(jq -n \
        --arg name "$metric_name" \
        --arg op "$operation" \
        --arg value "$value" \
        '{name: $name, action: $op, value: ($value | tonumber)}')
    fi
  fi

  # For counters, ensure we're always adding a positive value
  if [[ "$operation" == "add" ]] && [[ $(echo "$value < 0" | bc -l) -eq 1 ]]; then
    log "WARNING: Counter metrics should not have negative values. Converting to positive."
    value=$(echo "$value * -1" | bc -l)
  fi

  debug_log "Generated metric JSON: $metric_json"

  # Write to metrics file
  if ! echo "$metric_json" >> "$METRICS_PATH"; then
    log "ERROR: Failed to write metric to $METRICS_PATH"
    return 1
  fi

  return 0
} 