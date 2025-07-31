#!/usr/bin/env bash

# AWS-specific functions for CDK Stack Operator

# Function to load AWS credentials from a secret
# Usage: load_aws_credentials <namespace> <secret_name>
# Exports AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and optional AWS_SESSION_TOKEN
load_aws_credentials() {
  local namespace="$1"
  local secret_name="$2"
  
  log "Fetching credentials from secret '${secret_name}' in namespace '${namespace}'..."
  local creds_json
  creds_json=$(kubectl -n "${namespace}" get secret "${secret_name}" -o json 2>/dev/null)
  
  if [[ -z "$creds_json" ]]; then
    log "ERROR: Secret '${secret_name}' not found in namespace '${namespace}'"
    return 1
  fi

  local key_id_b64 aws_key_b64
  key_id_b64=$(echo "$creds_json" | jq -r '.data.AWS_ACCESS_KEY_ID // "null"')
  aws_key_b64=$(echo "$creds_json" | jq -r '.data.AWS_SECRET_ACCESS_KEY // "null"')
  
  if [[ "$key_id_b64" == "null" ]] || [[ "$aws_key_b64" == "null" ]]; then
    log "ERROR: Secret '${secret_name}' is missing .data.AWS_ACCESS_KEY_ID or .data.AWS_SECRET_ACCESS_KEY"
    return 1
  fi
  
  export AWS_ACCESS_KEY_ID=$(echo "$key_id_b64" | base64 -d)
  export AWS_SECRET_ACCESS_KEY=$(echo "$aws_key_b64" | base64 -d)

  local session_token_b64
  session_token_b64=$(echo "$creds_json" | jq -r '.data.AWS_SESSION_TOKEN // "null"')
  if [[ "$session_token_b64" != "null" ]]; then
    export AWS_SESSION_TOKEN=$(echo "$session_token_b64" | base64 -d)
  else
    unset AWS_SESSION_TOKEN
  fi
  
  log "AWS credentials exported successfully"
  debug_log "Exported credentials - AWS_ACCESS_KEY_ID length: ${#AWS_ACCESS_KEY_ID}, AWS_SECRET_ACCESS_KEY length: ${#AWS_SECRET_ACCESS_KEY}"
  return 0
} 