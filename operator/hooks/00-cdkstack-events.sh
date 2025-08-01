#!/usr/bin/env bash

set -euo pipefail

# Load common libraries
source /hooks/lib/common.sh
source /hooks/lib/aws.sh
source /hooks/lib/kubernetes.sh
source /hooks/lib/cdkstack.sh
source /hooks/lib/lifecycle.sh

# --- Main Logic ---

if [[ "${1-}" == "--config" ]]; then
  # Configuration is read by shell-operator to discover hooks.
  cat <<EOF
configVersion: v1
kubernetes:
- apiVersion: awscdk.dev/v1alpha1
  kind: CdkTsStack
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
  allowFailure: true
  queue:
    name: "cdkstack-main"
    maxRetries: 3
    retryDelay: "30s"
EOF
else
  # Hook logic is executed when an event occurs.
  log "--- CdkStack events hook execution start ---"
  
  check_required_env
  
  jq -c '.[]' $BINDING_CONTEXT_PATH | while IFS= read -r context; do
    
    # Extract key information from the event
    watchEvent=$(echo "$context" | jq -r '.watchEvent // "Unknown"')
    object=$(echo "$context" | jq '.object')
    resourceName=$(echo "$object" | jq -r '.metadata.name')
    currentPhase=$(echo "$object" | jq -r '.status.phase // ""')
    
    log "Event type: ${watchEvent} for resource: ${resourceName} (current phase: '${currentPhase}')"
    
    # Add a sanity check in case of empty objects in the context
    if [[ -z "${resourceName}" || "${resourceName}" == "null" ]]; then
      continue
    fi

    resourceNs=$(echo "$object" | jq -r '.metadata.namespace')
    deletionTimestamp=$(echo "$object" | jq -r '.metadata.deletionTimestamp')

    # --- DELETED EVENT LOGIC ---
    # Handle actual deletion events (when resource is already removed from etcd)
    if [[ "${watchEvent}" == "Deleted" ]]; then
      log "Resource '${resourceName}' has been deleted from cluster"
      log "Cleanup for deleted resource completed"
      continue # Stop processing this event
    fi

    # --- DELETION LOGIC ---
    # If deletionTimestamp is set, it means the resource is marked for deletion.
    if [[ ${deletionTimestamp} != "null" ]]; then
      log "Resource '${resourceName}' is being deleted..."
      
      # Check if resource still exists in cluster before proceeding
      if ! kubectl -n "${resourceNs}" get cdktsstack "${resourceName}" >/dev/null 2>&1; then
        log "Resource '${resourceName}' no longer exists in cluster, skipping deletion processing"
        continue
      fi
      
      # Check if destroy action is allowed
      destroyAllowed=$(echo "$object" | jq -r '.spec.actions.destroy')
      
      # Check if our finalizer is present - only then we need to do cleanup
      finalizers=$(echo "$object" | jq -r '.metadata.finalizers // []')
      has_finalizer=$(echo "$finalizers" | jq --arg f "$FINALIZER" 'index($f) != null')
      
      if [[ "${has_finalizer}" == "true" ]]; then
        if [[ "${destroyAllowed}" == "false" ]]; then
          log "Destroy action is disabled for '${resourceName}', removing finalizer without destroying AWS resources"
          update_status "${resourceNs}" "${resourceName}" "$PHASE_DELETING" "Destroy disabled, removing finalizer only" || true
        else
          log "Our finalizer is present, running cleanup..."
          
          # Update status to show cleanup is in progress (with error handling)
          update_status "${resourceNs}" "${resourceName}" "$PHASE_DELETING" "Running CDK destroy..." || true
          
          # Load credentials for cleanup
          credentialsSecretName=$(echo "$object" | jq -r '.spec.credentialsSecretName // "null"')
          if [[ "${credentialsSecretName}" != "null" ]]; then
            if load_aws_credentials "${resourceNs}" "${credentialsSecretName}"; then
              destroy_cdk_stack "${resourceNs}" "${resourceName}"
              cleanup_credentials
            else
              log "Failed to load AWS credentials for cleanup, but continuing with finalizer removal"
            fi
          fi
        fi
        
        # After successful cleanup (or skipped destroy), remove the finalizer so Kubernetes can delete the resource
        if remove_finalizer "${resourceNs}" "${resourceName}"; then
          log "Cleanup completed and finalizer removed for '${resourceName}'"
        else
          log "Cleanup completed but finalizer removal failed (resource may have been deleted)"
        fi
      else
        log "Our finalizer not present, skipping cleanup for '${resourceName}'"
      fi
      
      continue # Stop processing this event
    fi

    # --- FINALIZER LOGIC ---
    # Add finalizer on Added events and Synchronization events (for existing resources)
    if [[ "${watchEvent}" == "Added" || "${watchEvent}" == "Synchronization" ]]; then
      log "${watchEvent} event detected, checking if finalizer needs to be added..."
      finalizers=$(echo "$object" | jq -r '.metadata.finalizers // []')
      log "Current finalizers: ${finalizers}"
      
      # Check if our finalizer is present using jq
      has_finalizer=$(echo "$finalizers" | jq --arg f "$FINALIZER" 'index($f) != null')
      log "Has finalizer: ${has_finalizer}"
      
      if [[ "${has_finalizer}" == "false" ]]; then
        log "Adding finalizer to resource..."
        if add_finalizer "${resourceNs}" "${resourceName}"; then
          log "Finalizer was added, will process reconciliation on next Modified event"
          continue
        else
          log "Finalizer was already present (race condition), continuing to reconciliation"
        fi
      else
        log "Finalizer already present, continuing to reconciliation"
      fi
    fi

    # --- ADD/UPDATE LOGIC ---
    log "Processing reconciliation for '${resourceName}'"
    
    # Check if resource still exists before processing
    if ! kubectl -n "${resourceNs}" get cdktsstack "${resourceName}" &>/dev/null; then
      log "Resource '${resourceName}' no longer exists, skipping reconciliation"
      continue
    fi
    
    # Check if deploy action is allowed
    deployAllowed=$(echo "$object" | jq -r '.spec.actions.deploy')
    if [[ "${deployAllowed}" == "false" ]]; then
      log "Deploy action is disabled for '${resourceName}', skipping deployment"
      # If resource hasn't been deployed yet, mark it as such
      if [[ "${currentPhase}" == "" || "${currentPhase}" == "$PHASE_FAILED" ]]; then
        update_status "${resourceNs}" "${resourceName}" "$PHASE_FAILED" "Deploy action is disabled"
      fi
      continue
    fi
    
    # currentPhase already extracted above for logging
    log "Reconciling '${resourceName}', current phase is '${currentPhase}'"

    # --- Load Credentials ---
    credentialsSecretName=$(echo "$object" | jq -r '.spec.credentialsSecretName // "null"')
    log "credentialsSecretName: '${credentialsSecretName}'"
    if [[ "${credentialsSecretName}" == "null" ]]; then
      log "Error: spec.credentialsSecretName must be set"
      update_status "${resourceNs}" "${resourceName}" "$PHASE_FAILED" "spec.credentialsSecretName must be set"
      continue
    fi
    
    if ! load_aws_credentials "${resourceNs}" "${credentialsSecretName}"; then
      log "Failed to load AWS credentials from secret '${credentialsSecretName}'"
      update_status "${resourceNs}" "${resourceName}" "$PHASE_FAILED" "Failed to load AWS credentials from secret '${credentialsSecretName}'"
      continue
    fi

    # Execute deployment
    deploy_cdk_stack "${resourceNs}" "${resourceName}" "${currentPhase}"

    # Unset credentials for safety
    cleanup_credentials
  done
  log "--- Hook execution finished ---"
fi 