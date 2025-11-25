#!/usr/bin/env bash
# XIOPS - Configuration Management
# .env file parsing and validation

# =============================================
# Global configuration variables
# =============================================
XIOPS_CONFIG_LOADED=false
XIOPS_PROJECT_DIR=""

# Required variables for different operations
XIOPS_REQUIRED_BUILD="ACR_NAME SERVICE_NAME"

XIOPS_REQUIRED_DEPLOY="ACR_NAME AKS_CLUSTER_NAME RESOURCE_GROUP NAMESPACE SERVICE_NAME"

XIOPS_OPTIONAL_VARS="IMAGE_TAG IMAGE_NAME KEY_VAULT_NAME WORKLOAD_IDENTITY_CLIENT_ID TENANT_ID SUBSCRIPTION_ID"

# =============================================
# Find project root (directory containing .env)
# =============================================
find_project_root() {
    local dir="$PWD"

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.env" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    return 1
}

# =============================================
# Load .env file
# =============================================
load_env() {
    local env_file="${1:-.env}"
    local project_dir

    # If not absolute path, find project root
    if [[ "$env_file" != /* ]]; then
        project_dir=$(find_project_root) || {
            print_error "No .env file found in current directory or parent directories"
            return 1
        }
        env_file="$project_dir/.env"
        XIOPS_PROJECT_DIR="$project_dir"
    else
        XIOPS_PROJECT_DIR="$(dirname "$env_file")"
    fi

    if [[ ! -f "$env_file" ]]; then
        print_error ".env file not found: $env_file"
        return 1
    fi

    print_step "Loading configuration from .env..."

    # Parse .env file (compatible with both bash and zsh)
    set -a
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue

        # Remove carriage returns
        line=$(echo "$line" | tr -d '\r')

        # Only process lines that look like VAR=value
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            # Strip inline comments (#SECRET=YES/NO etc) but preserve the value
            # Handle: VAR=value #comment -> VAR=value
            local var_name="${line%%=*}"
            local var_value="${line#*=}"

            # Remove inline comment (everything after space+#)
            var_value="${var_value%% \#*}"
            var_value="${var_value%%	\#*}"  # Also handle tab+#

            # Remove quotes if present
            var_value="${var_value#\"}"
            var_value="${var_value%\"}"
            var_value="${var_value#\'}"
            var_value="${var_value%\'}"

            # Trim trailing whitespace
            var_value="${var_value%% }"
            var_value="${var_value%%	}"

            # Export the clean variable
            export "$var_name=$var_value" 2>/dev/null || true
        fi
    done < "$env_file"
    set +a

    XIOPS_CONFIG_LOADED=true
    print_success "Configuration loaded from: $env_file"
    return 0
}

# =============================================
# Validate required variables
# =============================================
validate_required() {
    local required="$1"
    local missing=""
    local has_missing=false

    for var in $required; do
        eval "val=\${$var:-}"
        if [[ -z "$val" ]]; then
            missing="$missing $var"
            has_missing=true
        fi
    done

    if $has_missing; then
        print_error "Missing required variables in .env:"
        for var in $missing; do
            print_bullet "$var"
        done
        return 1
    fi

    print_success "All required variables present"
    return 0
}

# =============================================
# Validate for build operation
# =============================================
validate_for_build() {
    validate_required "$XIOPS_REQUIRED_BUILD"
}

# =============================================
# Validate for deploy operation
# =============================================
validate_for_deploy() {
    validate_required "$XIOPS_REQUIRED_DEPLOY"
}

# =============================================
# Get configuration value with default
# =============================================
get_config() {
    local var="$1"
    local default="$2"

    if [[ -n "${!var}" ]]; then
        echo "${!var}"
    else
        echo "$default"
    fi
}

# =============================================
# Update .env file with new value
# =============================================
update_env() {
    local var="$1"
    local value="$2"
    local env_file="${XIOPS_PROJECT_DIR}/.env"

    if [[ ! -f "$env_file" ]]; then
        print_error ".env file not found"
        return 1
    fi

    # Check if variable exists
    if grep -q "^${var}=" "$env_file" 2>/dev/null; then
        # Update existing variable
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^${var}=.*|${var}=${value}|" "$env_file"
        else
            sed -i "s|^${var}=.*|${var}=${value}|" "$env_file"
        fi
        print_success "Updated ${var} in .env"
    else
        # Add new variable
        echo "" >> "$env_file"
        echo "${var}=${value}" >> "$env_file"
        print_success "Added ${var} to .env"
    fi

    # Update exported variable
    export "${var}=${value}"
}

# =============================================
# Display current configuration
# =============================================
show_config() {
    local operation="${1:-all}"

    echo ""
    print_box_start
    print_box_title "Current Configuration"
    print_box_empty

    case "$operation" in
        build)
            print_box_line "ACR Name" "${ACR_NAME:-not set}"
            print_box_line "Service Name" "${SERVICE_NAME:-not set}"
            print_box_line "Image Name" "${IMAGE_NAME:-$SERVICE_NAME}"
            print_box_line "Image Tag" "${IMAGE_TAG:-auto-generated}"
            ;;
        deploy)
            print_box_line "ACR Name" "${ACR_NAME:-not set}"
            print_box_line "Service Name" "${SERVICE_NAME:-not set}"
            print_box_line "AKS Cluster" "${AKS_CLUSTER_NAME:-not set}"
            print_box_line "Resource Group" "${RESOURCE_GROUP:-not set}"
            print_box_line "Namespace" "${NAMESPACE:-not set}"
            print_box_line "Image Tag" "${IMAGE_TAG:-not set}"
            ;;
        *)
            print_box_line "Project Dir" "${XIOPS_PROJECT_DIR:-not set}"
            print_box_line "ACR Name" "${ACR_NAME:-not set}"
            print_box_line "Service Name" "${SERVICE_NAME:-not set}"
            print_box_line "Image Name" "${IMAGE_NAME:-$SERVICE_NAME}"
            print_box_line "AKS Cluster" "${AKS_CLUSTER_NAME:-not set}"
            print_box_line "Resource Group" "${RESOURCE_GROUP:-not set}"
            print_box_line "Namespace" "${NAMESPACE:-not set}"
            print_box_line "Image Tag" "${IMAGE_TAG:-not set}"
            print_box_line "Key Vault" "${KEY_VAULT_NAME:-not set}"
            ;;
    esac

    print_box_end
    echo ""
}

# =============================================
# Generate .env template
# =============================================
generate_env_template() {
    local output="${1:-.env.example}"

    cat > "$output" << 'EOF'
# =============================================
# XIOPS Configuration
# Project-specific settings for Azure deployment
# =============================================

# Service Configuration (Required)
SERVICE_NAME=my-service

# Azure Container Registry (Required for build)
ACR_NAME=your-acr-name

# Image Name (Optional - defaults to SERVICE_NAME if not set)
# IMAGE_NAME=my-image

# Azure Kubernetes Service (Required for deploy)
AKS_CLUSTER_NAME=your-aks-cluster
RESOURCE_GROUP=your-resource-group
NAMESPACE=your-namespace

# Image Tag (Optional - auto-generated if not set)
# IMAGE_TAG=v01

# Azure Identity (Optional)
# SUBSCRIPTION_ID=your-subscription-id
# TENANT_ID=your-tenant-id
# KEY_VAULT_NAME=your-keyvault
# WORKLOAD_IDENTITY_CLIENT_ID=your-client-id

# =============================================
# Application-specific settings below
# =============================================
EOF

    print_success "Generated .env template: $output"
}

# =============================================
# Get full image path
# =============================================
get_full_image_path() {
    local tag="${1:-$IMAGE_TAG}"
    local image_name="${IMAGE_NAME:-$SERVICE_NAME}"
    echo "${ACR_NAME}.azurecr.io/${image_name}:${tag}"
}

# =============================================
# Get image repository (without tag)
# =============================================
get_image_repository() {
    local image_name="${IMAGE_NAME:-$SERVICE_NAME}"
    echo "${ACR_NAME}.azurecr.io/${image_name}"
}

# =============================================
# Azure Setup - Fetch Azure details and fill .env
# =============================================
azure_setup() {
    print_section "🔧 Azure Setup"
    print_info "This will fetch your Azure resources and configure .env"
    echo ""

    # Check if logged into Azure
    print_step "Checking Azure login..."
    if ! az account show &>/dev/null; then
        print_warning "Not logged into Azure"
        print_step "Opening Azure login..."
        if ! az login; then
            print_error "Azure login failed"
            return 1
        fi
    fi
    print_success "Azure login verified"

    # Get current directory for .env
    local env_file=".env"
    local project_dir="$PWD"

    # Check if .env exists, if not create from template
    if [[ ! -f "$env_file" ]]; then
        print_step "Creating .env file..."
        generate_env_template "$env_file"
    fi

    # ===== SUBSCRIPTION =====
    print_section "📋 Select Subscription"
    local subscriptions
    subscriptions=$(az account list --query "[].{name:name, id:id, isDefault:isDefault}" -o tsv 2>/dev/null)

    if [[ -z "$subscriptions" ]]; then
        print_error "No subscriptions found"
        return 1
    fi

    echo ""
    echo -e "${BOLD}${WHITE}Available Subscriptions:${NC}"
    local i=1
    local sub_ids=()
    local sub_names=()
    local default_sub=""

    while IFS=$'\t' read -r name id is_default; do
        sub_names+=("$name")
        sub_ids+=("$id")
        local marker=""
        if [[ "$is_default" == "true" ]]; then
            marker=" ${GREEN}(current)${NC}"
            default_sub=$i
        fi
        echo -e "  ${CYAN}$i${NC}) $name$marker"
        ((i++))
    done <<< "$subscriptions"

    echo ""
    printf "Select subscription [${default_sub:-1}]: "
    read -r sub_choice </dev/tty
    sub_choice=${sub_choice:-${default_sub:-1}}

    local selected_sub_id="${sub_ids[$((sub_choice-1))]}"
    local selected_sub_name="${sub_names[$((sub_choice-1))]}"

    print_step "Setting subscription: $selected_sub_name"
    az account set --subscription "$selected_sub_id"
    print_success "Subscription set"

    # Get Tenant ID
    local tenant_id
    tenant_id=$(az account show --query tenantId -o tsv)

    # ===== RESOURCE GROUP =====
    print_section "📁 Select Resource Group"
    local resource_groups
    resource_groups=$(az group list --query "[].name" -o tsv 2>/dev/null | sort)

    if [[ -z "$resource_groups" ]]; then
        print_error "No resource groups found"
        return 1
    fi

    echo ""
    echo -e "${BOLD}${WHITE}Available Resource Groups:${NC}"
    i=1
    local rg_names=()
    while read -r rg; do
        rg_names+=("$rg")
        echo -e "  ${CYAN}$i${NC}) $rg"
        ((i++))
    done <<< "$resource_groups"

    echo ""
    printf "Select resource group: "
    read -r rg_choice </dev/tty

    local selected_rg="${rg_names[$((rg_choice-1))]}"
    print_success "Selected: $selected_rg"

    # ===== ACR =====
    print_section "🐳 Select Container Registry (ACR)"
    local acr_list
    acr_list=$(az acr list --resource-group "$selected_rg" --query "[].name" -o tsv 2>/dev/null)

    # If no ACR in selected RG, search all RGs
    if [[ -z "$acr_list" ]]; then
        print_warning "No ACR found in $selected_rg, searching all resource groups..."
        acr_list=$(az acr list --query "[].name" -o tsv 2>/dev/null)
    fi

    local selected_acr=""
    if [[ -z "$acr_list" ]]; then
        print_warning "No ACR found in subscription"
        printf "Enter ACR name manually (or press Enter to skip): "
        read -r selected_acr </dev/tty
    else
        echo ""
        echo -e "${BOLD}${WHITE}Available Container Registries:${NC}"
        i=1
        local acr_names=()
        while read -r acr; do
            acr_names+=("$acr")
            echo -e "  ${CYAN}$i${NC}) $acr"
            ((i++))
        done <<< "$acr_list"

        echo ""
        printf "Select ACR: "
        read -r acr_choice </dev/tty

        selected_acr="${acr_names[$((acr_choice-1))]}"
        print_success "Selected: $selected_acr"
    fi

    # ===== AKS =====
    print_section "☸️ Select Kubernetes Cluster (AKS)"
    local aks_list
    aks_list=$(az aks list --resource-group "$selected_rg" --query "[].name" -o tsv 2>/dev/null)

    # If no AKS in selected RG, search all RGs
    if [[ -z "$aks_list" ]]; then
        print_warning "No AKS found in $selected_rg, searching all resource groups..."
        aks_list=$(az aks list --query "[].name" -o tsv 2>/dev/null)
    fi

    local selected_aks=""
    if [[ -z "$aks_list" ]]; then
        print_warning "No AKS cluster found in subscription"
        printf "Enter AKS cluster name manually (or press Enter to skip): "
        read -r selected_aks </dev/tty
    else
        echo ""
        echo -e "${BOLD}${WHITE}Available AKS Clusters:${NC}"
        i=1
        local aks_names=()
        while read -r aks; do
            aks_names+=("$aks")
            echo -e "  ${CYAN}$i${NC}) $aks"
            ((i++))
        done <<< "$aks_list"

        echo ""
        printf "Select AKS cluster: "
        read -r aks_choice </dev/tty

        selected_aks="${aks_names[$((aks_choice-1))]}"
        print_success "Selected: $selected_aks"
    fi

    # ===== KEY VAULT =====
    print_section "🔐 Select Key Vault (Optional)"
    local kv_list
    kv_list=$(az keyvault list --resource-group "$selected_rg" --query "[].name" -o tsv 2>/dev/null)

    # If no KV in selected RG, search all RGs
    if [[ -z "$kv_list" ]]; then
        kv_list=$(az keyvault list --query "[].name" -o tsv 2>/dev/null)
    fi

    local selected_kv=""
    if [[ -z "$kv_list" ]]; then
        print_info "No Key Vault found"
        printf "Enter Key Vault name manually (or press Enter to skip): "
        read -r selected_kv </dev/tty
    else
        echo ""
        echo -e "${BOLD}${WHITE}Available Key Vaults:${NC}"
        echo -e "  ${CYAN}0${NC}) Skip (no Key Vault)"
        i=1
        local kv_names=()
        while read -r kv; do
            kv_names+=("$kv")
            echo -e "  ${CYAN}$i${NC}) $kv"
            ((i++))
        done <<< "$kv_list"

        echo ""
        printf "Select Key Vault [0 to skip]: "
        read -r kv_choice </dev/tty

        if [[ "$kv_choice" != "0" && -n "$kv_choice" ]]; then
            selected_kv="${kv_names[$((kv_choice-1))]}"
            print_success "Selected: $selected_kv"
        else
            print_info "Skipped Key Vault"
        fi
    fi

    # ===== SERVICE NAME =====
    print_section "📦 Service Configuration"
    local current_service=""
    if [[ -f "$env_file" ]]; then
        current_service=$(grep "^SERVICE_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2)
    fi

    printf "Enter service name [${current_service:-my-service}]: "
    read -r service_name </dev/tty
    service_name=${service_name:-${current_service:-my-service}}

    printf "Enter Kubernetes namespace [${service_name}]: "
    read -r namespace </dev/tty
    namespace=${namespace:-$service_name}

    # ===== WORKLOAD IDENTITY (Optional) =====
    local workload_identity_client_id=""
    if [[ -n "$selected_aks" ]]; then
        print_section "🔑 Workload Identity (Optional)"
        print_info "Checking for managed identities..."

        # Try to get workload identity from AKS
        local aks_identity
        aks_identity=$(az aks show --name "$selected_aks" --resource-group "$selected_rg" \
            --query "identityProfile.kubeletidentity.clientId" -o tsv 2>/dev/null)

        if [[ -n "$aks_identity" && "$aks_identity" != "null" ]]; then
            echo -e "Found AKS kubelet identity: ${CYAN}$aks_identity${NC}"
            printf "Use this identity? [Y/n]: "
            read -r use_identity </dev/tty
            if [[ "$use_identity" != "n" && "$use_identity" != "N" ]]; then
                workload_identity_client_id="$aks_identity"
            fi
        fi

        if [[ -z "$workload_identity_client_id" ]]; then
            printf "Enter Workload Identity Client ID (or press Enter to skip): "
            read -r workload_identity_client_id </dev/tty
        fi
    fi

    # ===== WRITE TO .ENV =====
    print_section "💾 Writing Configuration"

    # Create or update .env file
    cat > "$env_file" << EOF
# =============================================
# XIOPS Configuration
# Auto-generated by 'xiops setup'
# =============================================

# Service Configuration
SERVICE_NAME=${service_name}

# Azure Container Registry
ACR_NAME=${selected_acr}

# Azure Kubernetes Service
AKS_CLUSTER_NAME=${selected_aks}
RESOURCE_GROUP=${selected_rg}
NAMESPACE=${namespace}

# Azure Identity
SUBSCRIPTION_ID=${selected_sub_id}
TENANT_ID=${tenant_id}
EOF

    # Add optional values if set
    if [[ -n "$selected_kv" ]]; then
        echo "KEY_VAULT_NAME=${selected_kv}" >> "$env_file"
    fi

    if [[ -n "$workload_identity_client_id" ]]; then
        echo "WORKLOAD_IDENTITY_CLIENT_ID=${workload_identity_client_id}" >> "$env_file"
    fi

    # Add placeholder for image tag
    cat >> "$env_file" << 'EOF'

# Image Tag (auto-generated if not set)
# IMAGE_TAG=v01

# AI Provider for error analysis (optional)
# AI_PROVIDER=openai
# OPENAI_API_KEY=your-key

# =============================================
# Application-specific settings below
# Mark with # SECRET=YES or # SECRET=NO
# =============================================
EOF

    print_success "Configuration written to .env"

    # ===== SUMMARY =====
    print_section "✅ Setup Complete"
    echo ""
    echo -e "${BOLD}${WHITE}Configuration Summary:${NC}"
    echo -e "  Subscription:    ${CYAN}$selected_sub_name${NC}"
    echo -e "  Resource Group:  ${CYAN}$selected_rg${NC}"
    echo -e "  ACR:             ${CYAN}${selected_acr:-not set}${NC}"
    echo -e "  AKS Cluster:     ${CYAN}${selected_aks:-not set}${NC}"
    echo -e "  Key Vault:       ${CYAN}${selected_kv:-not set}${NC}"
    echo -e "  Service Name:    ${CYAN}$service_name${NC}"
    echo -e "  Namespace:       ${CYAN}$namespace${NC}"
    echo -e "  Tenant ID:       ${CYAN}$tenant_id${NC}"
    echo ""
    print_info "Next steps:"
    echo -e "  1. Review .env file"
    echo -e "  2. Add application-specific variables"
    echo -e "  3. Run ${CYAN}xiops build${NC} to build your image"
    echo -e "  4. Run ${CYAN}xiops deploy${NC} to deploy to AKS"
    echo ""

    return 0
}
