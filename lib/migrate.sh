#!/usr/bin/env bash
# XIOPS - Database Migration Operations
# Run Alembic migrations via Kubernetes Jobs

# =============================================
# Run migration job
# =============================================
run_migration_job() {
    local tag="${1:-$IMAGE_TAG}"
    local namespace="${NAMESPACE}"
    local job_name="migration-${SERVICE_NAME}-$(date +%s)"
    local image_name="${IMAGE_NAME:-$SERVICE_NAME}"
    local full_image="${ACR_NAME}.azurecr.io/${image_name}:${tag}"

    print_section "🗃️  Running Database Migrations"
    print_step "Creating migration job..."

    # Create job manifest
    local job_manifest=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${namespace}
  labels:
    app: ${SERVICE_NAME}
    type: migration
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: ${SERVICE_ACCOUNT_NAME:-auth-service-sa}
      containers:
      - name: migrate
        image: ${full_image}
        imagePullPolicy: Always
        command: ["alembic", "upgrade", "head"]
        envFrom:
        - configMapRef:
            name: ${SERVICE_NAME}-config
            optional: true
        - secretRef:
            name: ${SERVICE_NAME}-secrets
            optional: false
        volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets-store"
          readOnly: true
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "${SERVICE_NAME}-spc"
EOF
)

    # Apply the job
    echo "$job_manifest" | kubectl apply -f - 2>/dev/null
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create migration job"
        return 1
    fi

    print_success "Migration job created: ${job_name}"

    # Wait for job completion
    wait_for_migration "$job_name" "$namespace"
    local result=$?

    # Show logs regardless of success/failure
    print_step "Migration logs:"
    kubectl logs "job/${job_name}" -n "$namespace" 2>/dev/null || true

    if [[ $result -eq 0 ]]; then
        print_success "Migrations completed successfully"
        # Clean up all migration jobs in namespace
        print_step "Cleaning up migration jobs..."
        kubectl delete jobs -l type=migration -n "$namespace" --ignore-not-found=true 2>/dev/null || true
        print_success "Migration jobs deleted"
    else
        print_error "Migration failed"
        print_info "Migration jobs kept for debugging. Delete with: kubectl delete jobs -l type=migration -n $namespace"
    fi

    return $result
}

# =============================================
# Wait for migration job to complete
# =============================================
wait_for_migration() {
    local job_name="$1"
    local namespace="$2"
    local timeout="${3:-300}"  # 5 minutes default

    print_step "Waiting for migration to complete (timeout: ${timeout}s)..."

    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            print_error "Migration timed out after ${timeout}s"
            return 1
        fi

        # Check job status - handle multiple success condition types
        local status=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)

        if [[ "$status" == "Complete" ]] || [[ "$status" == "SuccessCriteriaMet" ]]; then
            return 0
        elif [[ "$status" == "Failed" ]]; then
            print_error "Migration job failed"
            return 1
        fi

        # Also check succeeded count
        local succeeded=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.succeeded}' 2>/dev/null)
        if [[ "$succeeded" == "1" ]]; then
            return 0
        fi

        # Check if pod is in error state
        local pod_status=$(kubectl get pods -l "job-name=${job_name}" -n "$namespace" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [[ "$pod_status" == "Failed" ]]; then
            print_error "Migration pod failed"
            return 1
        fi
        if [[ "$pod_status" == "Succeeded" ]]; then
            return 0
        fi

        sleep 2
    done
}

# =============================================
# Get current migration status
# =============================================
get_migration_status() {
    local namespace="${NAMESPACE}"
    local pod

    print_section "🗃️  Migration Status"

    # Find a running pod
    pod=$(kubectl get pod -n "$namespace" -l "app=${SERVICE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        print_warning "No running pods found. Cannot check migration status."
        print_info "Deploy the application first, then check status."
        return 1
    fi

    print_step "Checking current revision..."
    kubectl exec -n "$namespace" "$pod" -- alembic current 2>/dev/null || {
        print_error "Failed to get migration status"
        return 1
    }

    return 0
}

# =============================================
# Show migration history
# =============================================
show_migration_history() {
    local namespace="${NAMESPACE}"
    local pod

    print_section "🗃️  Migration History"

    # Find a running pod
    pod=$(kubectl get pod -n "$namespace" -l "app=${SERVICE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        print_warning "No running pods found. Cannot check migration history."
        print_info "Deploy the application first, then check history."
        return 1
    fi

    print_step "Fetching migration history..."
    kubectl exec -n "$namespace" "$pod" -- alembic history 2>/dev/null || {
        print_error "Failed to get migration history"
        return 1
    }

    return 0
}

# =============================================
# Run migration via exec (for manual runs)
# =============================================
run_migration_exec() {
    local namespace="${NAMESPACE}"
    local pod
    local command="${1:-upgrade head}"

    print_section "🗃️  Running Migration"

    # Find a running pod
    pod=$(kubectl get pod -n "$namespace" -l "app=${SERVICE_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        print_error "No running pods found"
        print_info "Use 'xiops deploy' to deploy the application first"
        return 1
    fi

    print_step "Running alembic ${command} in pod ${pod}..."
    kubectl exec -n "$namespace" "$pod" -- alembic $command || {
        print_error "Migration failed"
        return 1
    }

    print_success "Migration completed"
    return 0
}

# =============================================
# Downgrade migration
# =============================================
run_migration_downgrade() {
    local revision="${1:--1}"

    print_section "🗃️  Downgrade Migration"
    print_warning "This will downgrade to revision: ${revision}"

    if ! confirm "Are you sure you want to downgrade?"; then
        print_info "Downgrade cancelled"
        return 0
    fi

    run_migration_exec "downgrade ${revision}"
}
