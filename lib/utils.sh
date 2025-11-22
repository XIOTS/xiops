#!/usr/bin/env bash
# XIOPS - Utility Functions
# Colors, formatting, and helper functions

# =============================================
# Color codes and styles
# =============================================
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDERLINE='\033[4m'

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export GRAY='\033[0;90m'

# Background colors
export BG_RED='\033[41m'
export BG_GREEN='\033[42m'
export BG_YELLOW='\033[43m'
export BG_BLUE='\033[44m'

# Reset
export NC='\033[0m'

# =============================================
# Print functions
# =============================================
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}  ${BOLD}${WHITE}$1${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_step() {
    echo -e "${YELLOW}⏳${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅${NC} ${GREEN}$1${NC}"
}

print_error() {
    echo -e "${RED}❌${NC} ${RED}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ ${NC} ${YELLOW}$1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️ ${NC} ${WHITE}$1${NC}"
}

print_config() {
    echo -e "   ${GRAY}├─${NC} ${DIM}$1:${NC} ${CYAN}$2${NC}"
}

print_config_last() {
    echo -e "   ${GRAY}└─${NC} ${DIM}$1:${NC} ${CYAN}$2${NC}"
}

print_bullet() {
    echo -e "   ${MAGENTA}•${NC} $1"
}

# =============================================
# Box drawing helpers
# =============================================
print_box_start() {
    echo -e "   ${GRAY}┌─────────────────────────────────────────────────────────┐${NC}"
}

print_box_title() {
    echo -e "   ${GRAY}│${NC} ${BOLD}${WHITE}$1${NC}"
}

print_box_line() {
    echo -e "   ${GRAY}│${NC}  ${DIM}$1:${NC} ${CYAN}$2${NC}"
}

print_box_empty() {
    echo -e "   ${GRAY}│${NC}"
}

print_box_end() {
    echo -e "   ${GRAY}└─────────────────────────────────────────────────────────┘${NC}"
}

# =============================================
# Success/Failure banners
# =============================================
print_success_banner() {
    echo ""
    echo -e "${BOLD}${BG_GREEN}${WHITE}                                                              ${NC}"
    echo -e "${BOLD}${BG_GREEN}${WHITE}   ✅ $1${NC}"
    echo -e "${BOLD}${BG_GREEN}${WHITE}                                                              ${NC}"
    echo ""
}

print_error_banner() {
    echo ""
    echo -e "${BOLD}${BG_RED}${WHITE}                                                              ${NC}"
    echo -e "${BOLD}${BG_RED}${WHITE}   ❌ $1${NC}"
    echo -e "${BOLD}${BG_RED}${WHITE}                                                              ${NC}"
    echo ""
}

# =============================================
# Confirmation prompts
# =============================================
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-Y}"

    if [[ "$default" == "Y" ]]; then
        echo -ne "   ${BOLD}${WHITE}${prompt}${NC} ${DIM}[Y/n]${NC}: "
    else
        echo -ne "   ${BOLD}${WHITE}${prompt}${NC} ${DIM}[y/N]${NC}: "
    fi

    read -r response

    if [[ -z "$response" ]]; then
        response="$default"
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

# =============================================
# Input prompts
# =============================================
prompt_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        echo -ne "   ${BOLD}${WHITE}${prompt}${NC} ${DIM}[${default}]${NC}: "
    else
        echo -ne "   ${BOLD}${WHITE}${prompt}${NC}: "
    fi

    read -r result

    if [[ -z "$result" ]]; then
        result="$default"
    fi

    echo "$result"
}

# =============================================
# Version number helpers
# =============================================
extract_version_number() {
    local tag="$1"
    # Extract numeric part from v## pattern
    if [[ "$tag" =~ ^v([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

increment_version() {
    local current="$1"
    local next=$((10#$current + 1))
    printf "%02d" "$next"
}

format_version_tag() {
    local num="$1"
    # Pad with leading zero if needed
    local padded=$(printf "%02d" "$((10#$num))" 2>/dev/null || echo "$num")
    echo "v${padded}"
}

# =============================================
# Dependency checks
# =============================================
check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"

    if ! command -v "$cmd" &> /dev/null; then
        print_error "$name is not installed"
        return 1
    fi
    return 0
}

check_dependencies() {
    local missing=()

    if ! check_command "az" "Azure CLI"; then
        missing+=("azure-cli")
    fi

    if ! check_command "kubectl" "kubectl"; then
        missing+=("kubernetes-cli")
    fi

    if ! check_command "docker" "Docker"; then
        missing+=("docker")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            print_bullet "$dep"
        done
        echo ""
        print_info "Install with: brew install ${missing[*]}"
        return 1
    fi

    return 0
}

# =============================================
# Timestamp helpers
# =============================================
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

date_tag() {
    date '+%Y%m%d-%H%M%S'
}
