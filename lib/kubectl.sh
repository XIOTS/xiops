#!/usr/bin/env bash
# XIOPS - kubectl Wrapper Commands
# Common kubectl operations using namespace and deployment from .env

# =============================================
# Get pods
# =============================================
kube_pods() {
    local wide="${1:-false}"

    print_step "Getting pods in namespace: $NAMESPACE"

    if [[ "$wide" == "true" ]]; then
        kubectl get pods -n "$NAMESPACE" -o wide
    else
        kubectl get pods -n "$NAMESPACE"
    fi
}

# =============================================
# Get all resources
# =============================================
kube_get_all() {
    print_step "Getting all resources in namespace: $NAMESPACE"
    kubectl get all -n "$NAMESPACE"
}

# =============================================
# Get services
# =============================================
kube_services() {
    print_step "Getting services in namespace: $NAMESPACE"
    kubectl get services -n "$NAMESPACE"
}

# =============================================
# Get deployments
# =============================================
kube_deployments() {
    print_step "Getting deployments in namespace: $NAMESPACE"
    kubectl get deployments -n "$NAMESPACE"
}

# =============================================
# Get configmaps
# =============================================
kube_configmaps() {
    print_step "Getting configmaps in namespace: $NAMESPACE"
    kubectl get configmaps -n "$NAMESPACE"
}

# =============================================
# Get secrets
# =============================================
kube_secrets() {
    print_step "Getting secrets in namespace: $NAMESPACE"
    kubectl get secrets -n "$NAMESPACE"
}

# =============================================
# Get ingresses
# =============================================
kube_ingresses() {
    print_step "Getting ingresses in namespace: $NAMESPACE"
    kubectl get ingress -n "$NAMESPACE"
}

# =============================================
# Describe pod
# =============================================
kube_describe_pod() {
    local pod_name="${1:-}"

    if [[ -z "$pod_name" ]]; then
        # Get the first pod for the service
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

        if [[ -z "$pod_name" ]]; then
            print_error "No pods found for service: $SERVICE_NAME"
            return 1
        fi
    fi

    print_step "Describing pod: $pod_name"
    kubectl describe pod "$pod_name" -n "$NAMESPACE"
}

# =============================================
# Describe deployment
# =============================================
kube_describe_deployment() {
    local deployment="${1:-$SERVICE_NAME}"

    print_step "Describing deployment: $deployment"
    kubectl describe deployment "$deployment" -n "$NAMESPACE"
}

# =============================================
# Describe service
# =============================================
kube_describe_service() {
    local svc="${1:-$SERVICE_NAME}"

    print_step "Describing service: $svc"
    kubectl describe service "$svc" -n "$NAMESPACE"
}

# =============================================
# Get pod logs (all pods)
# =============================================
kube_logs_all() {
    local tail="${1:-100}"

    print_step "Getting logs from all pods (last $tail lines)"

    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[*].metadata.name}')

    for pod in $pods; do
        echo ""
        print_section "📋 Logs from: $pod"
        echo ""
        kubectl logs "$pod" -n "$NAMESPACE" --tail="$tail"
    done
}

# =============================================
# Get previous pod logs
# =============================================
kube_logs_previous() {
    local pod_name="${1:-}"
    local tail="${2:-100}"

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [[ -z "$pod_name" ]]; then
        print_error "No pods found"
        return 1
    fi

    print_step "Getting previous logs from: $pod_name"
    kubectl logs "$pod_name" -n "$NAMESPACE" --previous --tail="$tail"
}

# =============================================
# Exec into pod
# =============================================
kube_exec() {
    local pod_name="${1:-}"
    local cmd="${2:-/bin/sh}"

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [[ -z "$pod_name" ]]; then
        print_error "No pods found for service: $SERVICE_NAME"
        return 1
    fi

    print_step "Executing into pod: $pod_name"
    kubectl exec -it "$pod_name" -n "$NAMESPACE" -- "$cmd"
}

# =============================================
# Port forward
# =============================================
kube_port_forward() {
    local local_port="${1:-8080}"
    local remote_port="${2:-80}"
    local resource="${3:-service/$SERVICE_NAME}"

    print_step "Port forwarding $local_port:$remote_port to $resource"
    print_info "Press Ctrl+C to stop"
    echo ""

    kubectl port-forward "$resource" "$local_port:$remote_port" -n "$NAMESPACE"
}

# =============================================
# Scale deployment
# =============================================
kube_scale() {
    local replicas="${1:-}"
    local deployment="${2:-$SERVICE_NAME}"

    if [[ -z "$replicas" ]]; then
        print_error "Number of replicas required"
        print_info "Usage: xiops k scale <replicas>"
        return 1
    fi

    print_step "Scaling $deployment to $replicas replicas"
    kubectl scale deployment "$deployment" --replicas="$replicas" -n "$NAMESPACE"

    print_success "Scaled $deployment to $replicas replicas"
}

# =============================================
# Get events
# =============================================
kube_events() {
    local sort="${1:-lastTimestamp}"

    print_step "Getting events in namespace: $NAMESPACE"
    kubectl get events -n "$NAMESPACE" --sort-by=".$sort"
}

# =============================================
# Top pods (resource usage)
# =============================================
kube_top_pods() {
    print_step "Getting pod resource usage"
    kubectl top pods -n "$NAMESPACE"
}

# =============================================
# Top nodes
# =============================================
kube_top_nodes() {
    print_step "Getting node resource usage"
    kubectl top nodes
}

# =============================================
# Get horizontal pod autoscaler
# =============================================
kube_hpa() {
    print_step "Getting HPA in namespace: $NAMESPACE"
    kubectl get hpa -n "$NAMESPACE"
}

# =============================================
# Restart deployment (rolling restart)
# =============================================
kube_restart() {
    local deployment="${1:-$SERVICE_NAME}"

    print_step "Restarting deployment: $deployment"
    kubectl rollout restart deployment "$deployment" -n "$NAMESPACE"

    print_success "Rolling restart initiated for $deployment"
}

# =============================================
# Watch pods
# =============================================
kube_watch() {
    print_step "Watching pods in namespace: $NAMESPACE"
    print_info "Press Ctrl+C to stop"
    echo ""

    kubectl get pods -n "$NAMESPACE" -w
}

# =============================================
# Get pod YAML
# =============================================
kube_get_yaml() {
    local resource="${1:-deployment/$SERVICE_NAME}"

    print_step "Getting YAML for: $resource"
    kubectl get "$resource" -n "$NAMESPACE" -o yaml
}

# =============================================
# Apply manifest
# =============================================
kube_apply() {
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        print_error "File path required"
        print_info "Usage: xiops k apply <file>"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        print_error "File not found: $file"
        return 1
    fi

    print_step "Applying manifest: $file"
    kubectl apply -f "$file" -n "$NAMESPACE"
}

# =============================================
# Delete resource
# =============================================
kube_delete() {
    local resource="${1:-}"

    if [[ -z "$resource" ]]; then
        print_error "Resource required"
        print_info "Usage: xiops k delete <resource>"
        return 1
    fi

    print_warning "This will delete: $resource"

    if confirm "Are you sure?"; then
        print_step "Deleting: $resource"
        kubectl delete "$resource" -n "$NAMESPACE"
    else
        print_warning "Cancelled"
    fi
}

# =============================================
# Get rollout history
# =============================================
kube_history() {
    local deployment="${1:-$SERVICE_NAME}"

    print_step "Getting rollout history for: $deployment"
    kubectl rollout history deployment "$deployment" -n "$NAMESPACE"
}

# =============================================
# Undo rollout
# =============================================
kube_undo() {
    local deployment="${1:-$SERVICE_NAME}"
    local revision="${2:-}"

    if [[ -n "$revision" ]]; then
        print_step "Rolling back $deployment to revision $revision"
        kubectl rollout undo deployment "$deployment" -n "$NAMESPACE" --to-revision="$revision"
    else
        print_step "Rolling back $deployment to previous version"
        kubectl rollout undo deployment "$deployment" -n "$NAMESPACE"
    fi
}

# =============================================
# Copy file from pod
# =============================================
kube_cp_from() {
    local pod_path="${1:-}"
    local local_path="${2:-.}"
    local pod_name="${3:-}"

    if [[ -z "$pod_path" ]]; then
        print_error "Pod path required"
        print_info "Usage: xiops k cp-from <pod-path> [local-path] [pod-name]"
        return 1
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [[ -z "$pod_name" ]]; then
        print_error "No pods found"
        return 1
    fi

    print_step "Copying from $pod_name:$pod_path to $local_path"
    kubectl cp "$NAMESPACE/$pod_name:$pod_path" "$local_path"
}

# =============================================
# Copy file to pod
# =============================================
kube_cp_to() {
    local local_path="${1:-}"
    local pod_path="${2:-}"
    local pod_name="${3:-}"

    if [[ -z "$local_path" ]] || [[ -z "$pod_path" ]]; then
        print_error "Local path and pod path required"
        print_info "Usage: xiops k cp-to <local-path> <pod-path> [pod-name]"
        return 1
    fi

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [[ -z "$pod_name" ]]; then
        print_error "No pods found"
        return 1
    fi

    print_step "Copying $local_path to $pod_name:$pod_path"
    kubectl cp "$local_path" "$NAMESPACE/$pod_name:$pod_path"
}

# =============================================
# Get contexts
# =============================================
kube_contexts() {
    print_step "Getting kubectl contexts"
    kubectl config get-contexts
}

# =============================================
# Use context
# =============================================
kube_use_context() {
    local context="${1:-}"

    if [[ -z "$context" ]]; then
        print_error "Context name required"
        print_info "Usage: xiops k use-context <context>"
        return 1
    fi

    print_step "Switching to context: $context"
    kubectl config use-context "$context"
}

# =============================================
# Get current context
# =============================================
kube_current_context() {
    print_step "Current context"
    kubectl config current-context
}

# =============================================
# Get namespaces
# =============================================
kube_namespaces() {
    print_step "Getting all namespaces"
    kubectl get namespaces
}

# =============================================
# Edit resource
# =============================================
kube_edit() {
    local resource="${1:-deployment/$SERVICE_NAME}"

    print_step "Editing: $resource"
    kubectl edit "$resource" -n "$NAMESPACE"
}

# =============================================
# Get endpoints
# =============================================
kube_endpoints() {
    print_step "Getting endpoints in namespace: $NAMESPACE"
    kubectl get endpoints -n "$NAMESPACE"
}

# =============================================
# Get persistent volume claims
# =============================================
kube_pvc() {
    print_step "Getting PVCs in namespace: $NAMESPACE"
    kubectl get pvc -n "$NAMESPACE"
}

# =============================================
# Debug/troubleshoot pod
# =============================================
kube_debug() {
    local pod_name="${1:-}"

    if [[ -z "$pod_name" ]]; then
        pod_name=$(kubectl get pods -n "$NAMESPACE" -l "app=$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi

    if [[ -z "$pod_name" ]]; then
        print_error "No pods found"
        return 1
    fi

    echo ""
    print_box_start
    print_box_title "Pod Debug Info: $pod_name"
    print_box_end
    echo ""

    print_section "📋 Pod Status"
    kubectl get pod "$pod_name" -n "$NAMESPACE" -o wide

    echo ""
    print_section "📋 Pod Conditions"
    kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.reason}{"\n"}{end}'

    echo ""
    print_section "📋 Container Status"
    kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}{"Container: "}{.name}{"\n"}{"  Ready: "}{.ready}{"\n"}{"  Restart Count: "}{.restartCount}{"\n"}{"  State: "}{.state}{"\n\n"}{end}'

    echo ""
    print_section "📋 Recent Events"
    kubectl get events -n "$NAMESPACE" --field-selector "involvedObject.name=$pod_name" --sort-by='.lastTimestamp' | tail -10

    echo ""
    print_section "📋 Recent Logs (last 20 lines)"
    kubectl logs "$pod_name" -n "$NAMESPACE" --tail=20
}
