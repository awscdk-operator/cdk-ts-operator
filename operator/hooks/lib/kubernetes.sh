#!/usr/bin/env bash

# Kubernetes API functions for CDK Stack Operator

# Function to update the resource's status
# Usage: update_status <namespace> <name> <phase> [message]
update_status() {
  local namespace="$1"
  local name="$2"
  local phase="$3"
  local message="${4-}" # Optional message
  
  # Check if resource still exists before trying to update status
  if ! kubectl -n "${namespace}" get cdktsstack "${name}" >/dev/null 2>&1; then
    log "Resource '${name}' no longer exists, skipping status update"
    return 0
  fi
  
  local status_json
  status_json=$(jq -n --arg p "$phase" --arg m "$message" '{phase: $p, message: $m}')
  
  # If the phase is "Succeeded", add the lastDeploy timestamp.
  if [[ "$phase" == "$PHASE_SUCCEEDED" ]]; then
    local timestamp
    timestamp=$(current_timestamp)
    status_json=$(echo "$status_json" | jq --arg t "$timestamp" '. + {lastDeploy: $t}')
  fi

  # The full status object is patched to ensure it's created if it doesn't exist.
  # We MUST use --subresource=status because our CRD has a status subresource defined.
  if ! kubectl -n "${namespace}" patch cdktsstack "${name}" --subresource=status --type=merge --patch "{\"status\":${status_json}}" 2>/dev/null; then
    log "Warning: Failed to update status for '${name}' - resource may have been deleted"
    return 1
  fi
  
  log "Successfully updated status for '${name}' to phase '${phase}'"
  return 0
}

# Function to add the finalizer to the resource
# Usage: add_finalizer <namespace> <name>
# Returns: 0 if finalizer was added, 1 if already present
add_finalizer() {
  local namespace="$1"
  local name="$2"
  log "Adding finalizer to '${name}'..."
  
  # Get current finalizers array - handle case when .metadata.finalizers doesn't exist
  local current_finalizers
  current_finalizers=$(kubectl -n "${namespace}" get cdktsstack "${name}" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)
  
  # If kubectl returns empty string, set to empty array
  if [[ -z "$current_finalizers" ]]; then
    current_finalizers="[]"
  fi
  
  log "Current finalizers raw: '${current_finalizers}'"
  
  # Check if our finalizer is already present
  if echo "$current_finalizers" | jq -e --arg f "$FINALIZER" 'index($f)' >/dev/null 2>&1; then
    log "Finalizer already present on '${name}'"
    return 1  # Return 1 to indicate finalizer was already present
  fi
  
  log "Finalizer not present, adding it..."
  
  # Add our finalizer to the array
  local new_finalizers
  new_finalizers=$(echo "$current_finalizers" | jq --arg f "$FINALIZER" '. + [$f]')
  
  log "New finalizers: ${new_finalizers}"
  
  kubectl -n "${namespace}" patch cdktsstack "${name}" --type=merge --patch "{\"metadata\":{\"finalizers\":${new_finalizers}}}"
  return 0  # Return 0 to indicate finalizer was added
}

# Function to remove the finalizer from the resource
# Usage: remove_finalizer <namespace> <name>
remove_finalizer() {
  local namespace="$1"
  local name="$2"
  log "Removing finalizer from '${name}'..."
  
  # Check if resource still exists before trying to modify it
  if ! kubectl -n "${namespace}" get cdktsstack "${name}" >/dev/null 2>&1; then
    log "Resource '${name}' no longer exists, skipping finalizer removal"
    return 0
  fi
  
  # Get current finalizers array
  local current_finalizers
  current_finalizers=$(kubectl -n "${namespace}" get cdktsstack "${name}" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)
  
  # Handle case when finalizers field doesn't exist or is empty
  if [[ -z "$current_finalizers" ]]; then
    log "No finalizers found on '${name}', nothing to remove"
    return 0
  fi
  
  # Validate that we got valid JSON
  if ! echo "$current_finalizers" | jq . >/dev/null 2>&1; then
    log "Invalid JSON received for finalizers, trying to get resource again..."
    current_finalizers="[]"
  fi
  
  # Remove our finalizer from the array
  local new_finalizers
  new_finalizers=$(echo "$current_finalizers" | jq --arg f "$FINALIZER" 'map(select(. != $f))')
  
  # Check if resource still exists before patching
  if ! kubectl -n "${namespace}" get cdktsstack "${name}" >/dev/null 2>&1; then
    log "Resource '${name}' was deleted while processing, finalizer removal not needed"
    return 0
  fi
  
  log "Patching finalizers: ${new_finalizers}"
  if ! kubectl -n "${namespace}" patch cdktsstack "${name}" --type=merge --patch "{\"metadata\":{\"finalizers\":${new_finalizers}}}" 2>/dev/null; then
    log "Warning: Failed to remove finalizer from '${name}' - resource may have been deleted"
    return 1
  fi
  
  log "Successfully removed finalizer from '${name}'"
  return 0
}

# Function to get all CdkTsStack resources from all namespaces
get_all_cdktstacks() {
  local result
  # Use timeout and error handling for kubectl command
  if result=$(kubectl get cdktsstacks --all-namespaces -o json 2>/dev/null); then
    # Extract items with jq, handle empty arrays gracefully
    echo "$result" | jq -c '.items[]?' 2>/dev/null || true
  else
    log "ERROR: Failed to get CdkTsStack resources"
    return 1
  fi
} 

# Function to create a Kubernetes event
# Usage: create_event <namespace> <resource_name> <event_type> <reason> <message>
# Event types: Normal, Warning
create_event() {
  local namespace="$1"
  local resource_name="$2"
  local event_type="$3"  # Normal or Warning
  local reason="$4"
  local message="$5"
  
  # Check if resource still exists
  if ! kubectl -n "${namespace}" get cdktsstack "${resource_name}" >/dev/null 2>&1; then
    log "Resource '${resource_name}' no longer exists, skipping event creation"
    return 0
  fi
  
  # Get resource UID for proper event linking
  local resource_uid
  resource_uid=$(kubectl -n "${namespace}" get cdktsstack "${resource_name}" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  
  if [[ -z "$resource_uid" ]]; then
    log "Failed to get resource UID for event creation"
    return 1
  fi
  
  # Create event using kubectl
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Generate unique event name
  local event_name="${resource_name}-$(date +%s)-$$"
  
  cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Event
metadata:
  name: ${event_name}
  namespace: ${namespace}
type: ${event_type}
reason: ${reason}
message: "${message}"
firstTimestamp: ${timestamp}
lastTimestamp: ${timestamp}
count: 1
involvedObject:
  apiVersion: awscdk.dev/v1alpha1
  kind: CdkTsStack
  name: ${resource_name}
  namespace: ${namespace}
  uid: ${resource_uid}
source:
  component: awscdk-operator
reportingComponent: awscdk-operator
reportingInstance: $(hostname)
EOF
  
  if [[ $? -eq 0 ]]; then
    log "Event created: ${event_type}/${reason} for ${resource_name}"
  else
    log "Warning: Failed to create event for ${resource_name}"
  fi
  
  return 0
} 