#!/usr/bin/env bash
# XIOPS - Azure Kubernetes Service Operations
# Deploy and manage applications on AKS

# =============================================
# Connect to AKS cluster
# =============================================
aks_connect() {
    print_section "🔗 Connecting to AKS"
    print_step "Getting AKS credentials..."

    if ! az aks get-credentials \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AKS_CLUSTER_NAME" \
        --overwrite-existing 2>/dev/null; then
        print_error "Failed to connect to AKS cluster"
        print_info "Try: az login"
        return 1
    fi

    print_success "Connected to AKS cluster: ${AKS_CLUSTER_NAME}"
    return 0
}

# =============================================
# Prepare namespace
# =============================================
aks_prepare_namespace() {
    local namespace="${1:-$NAMESPACE}"

    print_step "Preparing namespace: ${namespace}..."

    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

    print_success "Namespace ready: ${namespace}"
    return 0
}

# =============================================
# Process K8s manifests with envsubst
# =============================================
aks_process_manifests() {
    local k8s_dir="${XIOPS_PROJECT_DIR}/k8s"
    local processed_dir="${XIOPS_PROJECT_DIR}/.xiops-processed"

    if [[ ! -d "$k8s_dir" ]]; then
        print_error "k8s directory not found: $k8s_dir"
        return 1
    fi

    print_section "📝 Processing Kubernetes Manifests"

    # Create processed directory (don't modify source files)
    rm -rf "$processed_dir"
    mkdir -p "$processed_dir"

    # Export variables for envsubst
    export NAMESPACE
    export ACR_NAME
    export IMAGE_TAG
    export IMAGE_NAME="${IMAGE_NAME:-$SERVICE_NAME}"
    export SERVICE_NAME
    export WORKLOAD_IDENTITY_CLIENT_ID
    export KEY_VAULT_NAME
    export AZURE_TENANT_ID="${TENANT_ID}"

    # Process each yaml file to the processed directory
    local files=("kustomization.yaml" "deployment.yaml" "configmap.yaml" "service.yaml" "secret-provider-class.yaml" "hpa.yaml")

    for file in "${files[@]}"; do
        if [[ -f "${k8s_dir}/${file}" ]]; then
            print_step "Processing ${file}..."
            envsubst < "${k8s_dir}/${file}" > "${processed_dir}/${file}"
            print_success "${file} processed"
        fi
    done

    # Store processed dir for apply step
    export XIOPS_PROCESSED_DIR="$processed_dir"

    return 0
}

# =============================================
# Apply K8s manifests
# =============================================
aks_apply_manifests() {
    local k8s_dir="${XIOPS_PROCESSED_DIR:-${XIOPS_PROJECT_DIR}/k8s}"

    print_step "Applying manifests with kustomize..."

    if [[ -f "${k8s_dir}/kustomization.yaml" ]]; then
        kubectl apply -k "$k8s_dir"
    else
        # Fallback to applying all yaml files
        kubectl apply -f "$k8s_dir"
    fi

    print_success "All manifests applied"

    # Clean up processed directory
    if [[ -n "$XIOPS_PROCESSED_DIR" && -d "$XIOPS_PROCESSED_DIR" ]]; then
        rm -rf "$XIOPS_PROCESSED_DIR"
    fi

    # Force rollout restart to ensure new image is pulled
    local deployment="${SERVICE_NAME}"
    print_step "Triggering rollout restart for ${deployment}..."
    kubectl rollout restart "deployment/${deployment}" -n "$NAMESPACE" 2>/dev/null || true
    print_success "Rollout restart triggered"

    return 0
}

# =============================================
# Wait for deployment rollout
# =============================================
aks_wait_rollout() {
    local deployment="${1:-$SERVICE_NAME}"
    local namespace="${2:-$NAMESPACE}"
    local timeout="${3:-5m}"

    print_section "⏳ Waiting for Deployment"
    print_step "Waiting for pods to be ready..."

    if kubectl rollout status "deployment/${deployment}" -n "$namespace" --timeout="$timeout"; then
        print_success "Deployment rollout complete"
        return 0
    else
        print_error "Deployment rollout failed or timed out"
        echo ""

        # Show pod status
        print_section "🔍 Debugging Information"
        echo ""
        echo -e "${BOLD}${WHITE}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "app=${deployment}" 2>/dev/null
        echo ""

        # Get pod events for troubleshooting
        echo -e "${BOLD}${WHITE}Recent Pod Events:${NC}"
        kubectl get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null | grep -i "$deployment" | tail -10
        echo ""

        # Show detailed pod errors
        local pod
        pod=$(kubectl get pod -n "$namespace" -l "app=${deployment}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -n "$pod" ]]; then
            echo -e "${BOLD}${WHITE}Pod Describe (Events):${NC}"
            kubectl describe pod "$pod" -n "$namespace" 2>/dev/null | grep -A 20 "^Events:" | head -25
        fi

        echo ""
        print_info "Run 'xiops k describe pod' for full details"

        # Attempt rollout restart to pick up any recent changes
        echo ""
        print_step "Attempting rollout restart to recover..."
        kubectl rollout restart "deployment/${deployment}" -n "$namespace" 2>/dev/null

        return 1
    fi
}

# =============================================
# Show deployment status
# =============================================
aks_show_status() {
    local namespace="${1:-$NAMESPACE}"
    local service="${2:-$SERVICE_NAME}"

    print_section "📊 Deployment Status"

    echo ""
    echo -e "${BOLD}${WHITE}  Pods:${NC}"
    kubectl get pods -n "$namespace" -l "app=${service}" --no-headers 2>/dev/null | while read -r line; do
        local pod_name ready status restarts age
        pod_name=$(echo "$line" | awk '{print $1}')
        ready=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $3}')
        restarts=$(echo "$line" | awk '{print $4}')
        age=$(echo "$line" | awk '{print $5}')

        local status_icon
        if [[ "$status" == "Running" ]]; then
            status_icon="${GREEN}●${NC}"
        else
            status_icon="${YELLOW}●${NC}"
        fi

        echo -e "   ${status_icon} ${CYAN}${pod_name}${NC}"
        echo -e "      ${DIM}Ready:${NC} ${ready}  ${DIM}Status:${NC} ${status}  ${DIM}Restarts:${NC} ${restarts}  ${DIM}Age:${NC} ${age}"
    done

    echo ""
    echo -e "${BOLD}${WHITE}  Services:${NC}"
    kubectl get svc -n "$namespace" -l "app=${service}" --no-headers 2>/dev/null | while read -r line; do
        local svc_name type cluster_ip port
        svc_name=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $2}')
        cluster_ip=$(echo "$line" | awk '{print $3}')
        port=$(echo "$line" | awk '{print $5}')

        echo -e "   ${GREEN}●${NC} ${CYAN}${svc_name}${NC}"
        echo -e "      ${DIM}Type:${NC} ${type}  ${DIM}ClusterIP:${NC} ${cluster_ip}  ${DIM}Port:${NC} ${port}"
    done

    return 0
}

# =============================================
# Full deploy workflow
# =============================================
aks_deploy() {
    local tag="${1:-$IMAGE_TAG}"
    local skip_migrations="${SKIP_MIGRATIONS:-false}"

    # Set IMAGE_TAG for processing
    export IMAGE_TAG="$tag"

    # Connect to AKS
    aks_connect || return 1

    # Prepare namespace
    aks_prepare_namespace || return 1

    # Run migrations (unless skipped)
    if [[ "$skip_migrations" != "true" ]]; then
        if [[ -f "${XIOPS_PROJECT_DIR}/k8s/migration-job.yaml" ]]; then
            run_migration_job "$tag" || {
                print_error "Migration failed. Aborting deployment."
                print_info "Use --skip-migrations to deploy without migrations"
                return 1
            }
        else
            print_info "No migration-job.yaml found, skipping migrations"
        fi
    else
        print_warning "Skipping migrations (--skip-migrations flag)"
    fi

    # Process manifests
    aks_process_manifests || return 1

    # Apply manifests
    aks_apply_manifests || return 1

    # Wait for rollout
    aks_wait_rollout || return 1

    # Save deployed tag
    echo "$tag" > "${XIOPS_PROJECT_DIR}/deployed-image-tag.txt"
    print_info "Image tag saved to deployed-image-tag.txt"

    # Show status
    aks_show_status

    return 0
}

# =============================================
# Stream pod logs
# =============================================
aks_logs() {
    local namespace="${1:-$NAMESPACE}"
    local service="${2:-$SERVICE_NAME}"
    local follow="${3:-true}"

    local cmd="kubectl logs -n $namespace -l app=${service}"

    if [[ "$follow" == "true" ]]; then
        cmd="$cmd -f"
    fi

    print_info "Streaming logs for ${service}..."
    eval "$cmd"
}

# =============================================
# Rollback deployment
# =============================================
aks_rollback() {
    local deployment="${1:-$SERVICE_NAME}"
    local namespace="${2:-$NAMESPACE}"

    print_section "⏪ Rolling Back Deployment"

    print_step "Rolling back ${deployment}..."
    if kubectl rollout undo "deployment/${deployment}" -n "$namespace"; then
        print_success "Rollback initiated"

        print_step "Waiting for rollout..."
        kubectl rollout status "deployment/${deployment}" -n "$namespace" --timeout=5m
        print_success "Rollback complete"
    else
        print_error "Rollback failed"
        return 1
    fi

    return 0
}

# =============================================
# Scale deployment
# =============================================
aks_scale() {
    local replicas="$1"
    local deployment="${2:-$SERVICE_NAME}"
    local namespace="${3:-$NAMESPACE}"

    print_step "Scaling ${deployment} to ${replicas} replicas..."

    if kubectl scale "deployment/${deployment}" -n "$namespace" --replicas="$replicas"; then
        print_success "Scaled to ${replicas} replicas"
    else
        print_error "Failed to scale deployment"
        return 1
    fi

    return 0
}

# =============================================
# Restart deployment
# =============================================
aks_restart() {
    local deployment="${1:-$SERVICE_NAME}"
    local namespace="${2:-$NAMESPACE}"

    print_step "Restarting ${deployment}..."

    if kubectl rollout restart "deployment/${deployment}" -n "$namespace"; then
        print_success "Restart initiated"

        print_step "Waiting for rollout..."
        kubectl rollout status "deployment/${deployment}" -n "$namespace" --timeout=5m
        print_success "Restart complete"
    else
        print_error "Restart failed"
        return 1
    fi

    return 0
}

# =============================================
# Get shell access to pod
# =============================================
aks_shell() {
    local namespace="${1:-$NAMESPACE}"
    local service="${2:-$SERVICE_NAME}"
    local shell="${3:-/bin/bash}"

    local pod
    pod=$(kubectl get pod -n "$namespace" -l "app=${service}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        print_error "No pod found for ${service}"
        return 1
    fi

    print_info "Connecting to ${pod}..."
    kubectl exec -it -n "$namespace" "$pod" -- "$shell"
}

# =============================================
# Describe pod for debugging
# =============================================
aks_describe() {
    local namespace="${1:-$NAMESPACE}"
    local service="${2:-$SERVICE_NAME}"

    local pod
    pod=$(kubectl get pod -n "$namespace" -l "app=${service}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        print_error "No pod found for ${service}"
        return 1
    fi

    kubectl describe pod "$pod" -n "$namespace"
}
