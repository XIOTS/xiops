#!/usr/bin/env bash
# XIOPS - Azure Key Vault Operations
# Read and write secrets to Azure Key Vault

# =============================================
# Key Vault connection
# =============================================
kv_connect() {
    if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
        print_error "KEY_VAULT_NAME not set in .env"
        return 1
    fi

    print_step "Connecting to Key Vault: $KEY_VAULT_NAME"

    # Check if logged into Azure
    if ! az account show &>/dev/null; then
        print_error "Not logged into Azure CLI"
        print_info "Run 'az login' first"
        return 1
    fi

    # Verify Key Vault exists and is accessible
    if ! az keyvault show --name "$KEY_VAULT_NAME" &>/dev/null; then
        print_error "Key Vault '$KEY_VAULT_NAME' not found or not accessible"
        print_info "Check that KEY_VAULT_NAME is correct and you have access"
        return 1
    fi

    print_success "Connected to Key Vault: $KEY_VAULT_NAME"
    return 0
}

# =============================================
# List secrets
# =============================================
kv_list_secrets() {
    local filter="${1:-}"

    print_step "Listing secrets in $KEY_VAULT_NAME..."

    local secrets
    secrets=$(az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].{name:name, enabled:attributes.enabled}" -o tsv 2>/dev/null)

    if [[ -z "$secrets" ]]; then
        print_warning "No secrets found in Key Vault"
        return 0
    fi

    echo ""
    print_box_start
    print_box_title "Secrets in $KEY_VAULT_NAME"
    print_box_empty

    while IFS=$'\t' read -r name enabled; do
        if [[ -n "$filter" ]] && [[ ! "$name" =~ $filter ]]; then
            continue
        fi

        local status_icon
        if [[ "$enabled" == "true" ]]; then
            status_icon="${GREEN}●${NC}"
        else
            status_icon="${RED}○${NC}"
        fi

        echo -e "   ${GRAY}│${NC}  $status_icon  ${CYAN}$name${NC}"
    done <<< "$secrets"

    print_box_empty
    echo -e "   ${GRAY}│${NC}  ${DIM}● enabled  ○ disabled${NC}"
    print_box_end
    echo ""
}

# =============================================
# Get secret value
# =============================================
kv_get_secret() {
    local secret_name="$1"
    local show_value="${2:-false}"

    if [[ -z "$secret_name" ]]; then
        print_error "Secret name is required"
        return 1
    fi

    print_step "Reading secret: $secret_name"

    local secret_value
    secret_value=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$secret_name" --query "value" -o tsv 2>/dev/null)

    if [[ -z "$secret_value" ]]; then
        print_error "Secret '$secret_name' not found or empty"
        return 1
    fi

    print_success "Secret '$secret_name' retrieved"

    if [[ "$show_value" == "true" ]]; then
        echo ""
        print_box_start
        print_box_title "Secret: $secret_name"
        print_box_empty
        echo -e "   ${GRAY}│${NC}  ${CYAN}$secret_value${NC}"
        print_box_end
        echo ""
    else
        # Return value for programmatic use
        echo "$secret_value"
    fi
}

# =============================================
# Set secret value
# =============================================
kv_set_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="${3:-}"

    if [[ -z "$secret_name" ]]; then
        print_error "Secret name is required"
        return 1
    fi

    if [[ -z "$secret_value" ]]; then
        print_error "Secret value is required"
        return 1
    fi

    print_step "Setting secret: $secret_name"

    local cmd="az keyvault secret set --vault-name \"$KEY_VAULT_NAME\" --name \"$secret_name\" --value \"$secret_value\""

    if [[ -n "$description" ]]; then
        cmd="$cmd --description \"$description\""
    fi

    if eval "$cmd" &>/dev/null; then
        print_success "Secret '$secret_name' set successfully"
        return 0
    else
        print_error "Failed to set secret '$secret_name'"
        return 1
    fi
}

# =============================================
# Delete secret
# =============================================
kv_delete_secret() {
    local secret_name="$1"

    if [[ -z "$secret_name" ]]; then
        print_error "Secret name is required"
        return 1
    fi

    print_step "Deleting secret: $secret_name"

    if az keyvault secret delete --vault-name "$KEY_VAULT_NAME" --name "$secret_name" &>/dev/null; then
        print_success "Secret '$secret_name' deleted"
        print_info "Secret is soft-deleted and can be recovered within retention period"
        return 0
    else
        print_error "Failed to delete secret '$secret_name'"
        return 1
    fi
}

# =============================================
# Show secret metadata
# =============================================
kv_show_secret_info() {
    local secret_name="$1"

    if [[ -z "$secret_name" ]]; then
        print_error "Secret name is required"
        return 1
    fi

    print_step "Getting info for secret: $secret_name"

    local info
    info=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$secret_name" \
        --query "{name:name, enabled:attributes.enabled, created:attributes.created, updated:attributes.updated, expires:attributes.expires, contentType:contentType}" \
        -o json 2>/dev/null)

    if [[ -z "$info" ]] || [[ "$info" == "null" ]]; then
        print_error "Secret '$secret_name' not found"
        return 1
    fi

    local name enabled created updated expires content_type
    name=$(echo "$info" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    enabled=$(echo "$info" | grep -o '"enabled":[^,}]*' | cut -d':' -f2)
    created=$(echo "$info" | grep -o '"created":"[^"]*"' | cut -d'"' -f4)
    updated=$(echo "$info" | grep -o '"updated":"[^"]*"' | cut -d'"' -f4)
    expires=$(echo "$info" | grep -o '"expires":[^,}]*' | cut -d':' -f2 | tr -d '"null')
    content_type=$(echo "$info" | grep -o '"contentType":[^,}]*' | cut -d':' -f2 | tr -d '"null')

    echo ""
    print_box_start
    print_box_title "Secret Information"
    print_box_empty
    print_box_line "Name" "$name"
    print_box_line "Enabled" "$enabled"
    print_box_line "Created" "${created:-N/A}"
    print_box_line "Updated" "${updated:-N/A}"
    print_box_line "Expires" "${expires:-Never}"
    print_box_line "Content Type" "${content_type:-Not set}"
    print_box_end
    echo ""
}

# =============================================
# Sync .env secrets to Key Vault
# =============================================
kv_sync_to_vault() {
    local env_file="${XIOPS_PROJECT_DIR}/.env"
    local prefix="${1:-}"
    local dry_run="${2:-false}"

    if [[ ! -f "$env_file" ]]; then
        print_error ".env file not found"
        return 1
    fi

    print_step "Syncing secrets from .env to Key Vault..."

    local count=0
    local secrets_to_sync=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        # Only process lines that look like VAR=value
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            local var_name="${line%%=*}"
            local var_value="${line#*=}"

            # Skip empty values
            [[ -z "$var_value" ]] && continue

            # Skip XIOPS config variables
            case "$var_name" in
                SERVICE_NAME|ACR_NAME|AKS_CLUSTER_NAME|RESOURCE_GROUP|NAMESPACE|IMAGE_TAG|KEY_VAULT_NAME)
                    continue
                    ;;
            esac

            # Apply prefix filter if specified
            if [[ -n "$prefix" ]] && [[ ! "$var_name" =~ ^$prefix ]]; then
                continue
            fi

            # Convert to Key Vault naming convention (replace _ with -)
            local secret_name="${var_name//_/-}"

            secrets_to_sync="$secrets_to_sync$secret_name=$var_value"$'\n'
            ((count++))
        fi
    done < "$env_file"

    if [[ $count -eq 0 ]]; then
        print_warning "No secrets to sync"
        return 0
    fi

    echo ""
    print_box_start
    print_box_title "Secrets to Sync"
    print_box_empty

    while IFS='=' read -r name value; do
        [[ -z "$name" ]] && continue
        local masked_value="${value:0:3}***"
        echo -e "   ${GRAY}│${NC}  ${CYAN}$name${NC} = ${DIM}$masked_value${NC}"
    done <<< "$secrets_to_sync"

    print_box_empty
    echo -e "   ${GRAY}│${NC}  ${BOLD}Total: $count secrets${NC}"
    print_box_end
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run - no secrets were synced"
        return 0
    fi

    if ! confirm "Sync these secrets to Key Vault?"; then
        print_warning "Sync cancelled"
        return 0
    fi

    echo ""
    local success=0
    local failed=0

    while IFS='=' read -r name value; do
        [[ -z "$name" ]] && continue
        if kv_set_secret "$name" "$value" 2>/dev/null; then
            ((success++))
        else
            ((failed++))
        fi
    done <<< "$secrets_to_sync"

    echo ""
    print_success "Synced $success secrets to Key Vault"
    if [[ $failed -gt 0 ]]; then
        print_warning "Failed to sync $failed secrets"
    fi
}

# =============================================
# Export secrets to .env format
# =============================================
kv_export_secrets() {
    local output_file="${1:--}"
    local filter="${2:-}"

    print_step "Exporting secrets from Key Vault..."

    local secrets
    secrets=$(az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[?attributes.enabled].name" -o tsv 2>/dev/null)

    if [[ -z "$secrets" ]]; then
        print_warning "No enabled secrets found"
        return 0
    fi

    local output=""
    output+="# Exported from Key Vault: $KEY_VAULT_NAME"$'\n'
    output+="# Date: $(date '+%Y-%m-%d %H:%M:%S')"$'\n'
    output+=""$'\n'

    local count=0
    while read -r secret_name; do
        # Apply filter if specified
        if [[ -n "$filter" ]] && [[ ! "$secret_name" =~ $filter ]]; then
            continue
        fi

        local value
        value=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$secret_name" --query "value" -o tsv 2>/dev/null)

        if [[ -n "$value" ]]; then
            # Convert Key Vault naming back to env var format (replace - with _)
            local env_name="${secret_name//-/_}"
            env_name=$(echo "$env_name" | tr '[:lower:]' '[:upper:]')
            output+="${env_name}=${value}"$'\n'
            ((count++))
        fi
    done <<< "$secrets"

    if [[ "$output_file" == "-" ]]; then
        echo "$output"
    else
        echo "$output" > "$output_file"
        print_success "Exported $count secrets to: $output_file"
    fi
}
