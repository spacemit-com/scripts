#!/bin/bash
# Buildroot for K1 quick download script (external versions)

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
VERSION=""
SHALLOW_CLONE=false
DEBUG_MODE=false
TARGET_DIR=""
REQUIRED_REPO_VERSION="2.41"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_debug() { [[ $DEBUG_MODE == true ]] && echo -e "${CYAN}[DEBUG]${NC} $*"; }

# Version mapping table
declare -A EXTERNAL_VERSION_MAP=(
    ["v1.0"]="bl-v1.0.y.xml"
    ["v2.0"]="bl-v2.0.y.xml"
    ["v2.1"]="k1-bl-v2.1.y.xml"
    ["v2.2"]="k1-bl-v2.2.y.xml"
)

declare -A EXTERNAL_BRANCH_MAP=(
    ["v1.0"]="bl-v1.0.y"
    ["v2.0"]="bl-v2.0.y"
    ["v2.1"]="k1-bl-v2.1.y"
    ["v2.2"]="k1-bl-v2.2.y"
)

# Show help information
show_help() {
    cat << 'EOF'
Buildroot for K1 quick download script

Usage: ./download.sh [options]

Interactive mode:
    ./download.sh
    If no arguments are provided, enter interactive mode and configure options via Q&A

Command line mode:
    -v, --version VERSION      Specify Buildroot version
                              Supported: v1.0, v2.0, v2.1, v2.2
    -s, --shallow             Enable shallow clone (save time and disk space)
    -d, --debug               Show debug info, including command output
    -t, --target-dir DIR      Specify target directory (default: ./buildroot-k1-VERSION)
    -h, --help                Show this help message

Examples:
    # Interactive mode
    ./download.sh

    # Command line mode
    ./download.sh -v v2.2 -s -d
    ./download.sh -v v2.1 --target-dir /opt/buildroot-k1
    ./download.sh -v v2.0 --shallow

EOF
}

# Run command with or without debug output
run_cmd() {
    local cmd="$*"
    log_debug "Executing command: $cmd"

    if [[ $DEBUG_MODE == true ]]; then
        eval "$cmd"
    else
        eval "$cmd" >/dev/null 2>&1
    fi
}

# Run command and capture output
run_cmd_capture() {
    local cmd="$*"
    log_debug "Executing command (capture output): $cmd"
    eval "$cmd"
}

# 1. Validate script arguments
validate_arguments() {
    log_info "Validating script arguments..."

    if [[ -z "$VERSION" ]]; then
        log_error "You must specify a version with -v/--version"
        show_help
        exit 1
    fi

    # Check version validity
    if [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+$ ]]; then
        # External version
        if [[ ! "${EXTERNAL_VERSION_MAP[$VERSION]:-}" ]]; then
            log_error "Unsupported version: $VERSION"
            log_info "Supported versions: ${!EXTERNAL_VERSION_MAP[*]}"
            exit 1
        fi
        log_info "Detected version: $VERSION"
    else
        log_error "Invalid version format: $VERSION"
        log_info "Supported version formats: v1.0, v2.0, v2.1, v2.2"
        exit 1
    fi

    # Set default target dir
    if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="./buildroot-k1-$VERSION"
    fi
    TARGET_DIR=$(realpath "$TARGET_DIR")

    log_success "Argument validation passed"
    log_info "Version: $VERSION"
    log_info "Shallow clone: $([[ $SHALLOW_CLONE == true ]] && echo "enabled" || echo "disabled")"
    log_info "DEBUG mode: $([[ $DEBUG_MODE == true ]] && echo "enabled" || echo "disabled")"
    log_info "Target dir: $TARGET_DIR"
}

# 2. Check environment - required commands
check_required_commands() {
    log_info "Checking required commands..."

    local missing_commands=()

    # Define command to package mapping for different systems
    declare -A cmd_to_pkg_deb=(
        ["git"]="git"
        ["curl"]="curl"
        ["wget"]="wget"
        ["ssh"]="openssh-client"
        ["timeout"]="coreutils"
        ["awk"]="gawk"
        ["dig"]="dnsutils"
        ["make"]="make"
    )

    declare -A cmd_to_pkg_rpm=(
        ["git"]="git"
        ["curl"]="curl"
        ["wget"]="wget"
        ["ssh"]="openssh-clients"
        ["timeout"]="coreutils"
        ["awk"]="gawk"
        ["dig"]="bind-utils"
        ["make"]="make"
    )

    local required_commands=("git" "curl" "wget" "ping" "ssh" "awk" "dig" "make")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
            log_warning "Command not found: $cmd"
        else
            log_debug "Command found: $cmd"
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_info "Please install the missing packages, e.g.:"
        # Convert to DEB package names for display
        local deb_packages=()
        for cmd in "${missing_commands[@]}"; do
            deb_packages+=("${cmd_to_pkg_deb[$cmd]}")
        done
        log_info "  Ubuntu/Debian: sudo apt-get install ${deb_packages[*]}"
        # Convert to RPM package names for display
        local rpm_packages=()
        for cmd in "${missing_commands[@]}"; do
            rpm_packages+=("${cmd_to_pkg_rpm[$cmd]}")
        done
        log_info "  CentOS/RHEL:   sudo yum install ${rpm_packages[*]}"
        return 1
    fi

    log_success "All required commands are installed"
    return 0
}

# Check internal/external network
check_network_environment() {
    log_info "Checking network environment..."

    # Check archive.spacemit.com DNS
    local archive_ip
    archive_ip=$(dig +short archive.spacemit.com 2>/dev/null | head -1)

    if [[ -z "$archive_ip" ]]; then
        log_warning "Failed to resolve archive.spacemit.com, trying nslookup"
        archive_ip=$(nslookup archive.spacemit.com 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    fi

    if [[ -z "$archive_ip" ]]; then
        log_error "Network error: failed to resolve archive.spacemit.com"
        log_info "Please check your network connection and DNS settings"
        return 1
    fi

    log_debug "archive.spacemit.com resolved to: $archive_ip"

    # Determine internal/external
    if [[ "$archive_ip" =~ ^10\. ]]; then
        log_info "Detected internal network (archive.spacemit.com -> $archive_ip)"
        export NETWORK_TYPE="internal"
    else
        log_info "Detected external network (archive.spacemit.com -> $archive_ip)"
        export NETWORK_TYPE="external"
    fi

    return 0
}

# Identify download protocol
identify_download_protocol() {
    log_info "Identifying download protocol..."

    # Check if SSH key exists
    local ssh_key_exists=false
    for key_type in rsa ed25519 ecdsa; do
        if [[ -f "$HOME/.ssh/id_$key_type" ]]; then
            ssh_key_exists=true
            log_debug "Found SSH key: id_$key_type"
            break
        fi
    done

    # Check if rsa key and openssh version
    if [[ -f "$HOME/.ssh/id_rsa" ]]; then
        local ssh_version
        ssh_version=$(ssh -V 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$ssh_version" ]]; then
            # Compare version number
            if awk "BEGIN{exit !($ssh_version >= 8.8)}"; then
                log_info "Detected OpenSSH >= 8.8, need to configure support for rsa algorithm"
                # Append to ~/.ssh/config if not already present
                local ssh_config="$HOME/.ssh/config"
                local rsa_config="PubkeyAcceptedKeyTypes +ssh-rsa"
                if [[ ! -f "$ssh_config" ]] || ! grep -q "$rsa_config" "$ssh_config"; then
                    {
                        echo -e "\nHost *"
                        echo "PubkeyAcceptedKeyTypes +ssh-rsa"
                        echo "HostKeyAlgorithms +ssh-rsa"
                    } >> "$ssh_config"
                    log_info "Appended rsa config to $ssh_config"
                else
                    log_info "$ssh_config already contains rsa config"
                fi
            fi
        fi
    fi

    if [[ $ssh_key_exists == false ]]; then
        log_error "No SSH key found, you need to generate one, e.g.:\nssh-keygen -o -a 256 -t ed25519 -C \"\$(hostname)-\$(date +'%d-%m-%Y')\""
        return 1
    fi

    log_info "SSH key found, testing SSH connection..."

    # Test SSH connection
    local ssh_works=false
    # Test external SSH connection
    log_debug "Testing SSH connection to gitee.com..."
    if run_cmd "ssh -T git@gitee.com -o ConnectTimeout=10 -o StrictHostKeyChecking=no" 2>/dev/null; then
        ssh_works=true
        log_debug "gitee.com SSH connection successful"
    else
        log_error "gitee.com SSH connection failed"
        log_error "Maybe you need to add your SSH public key to https://gitee.com/profile/sshkeys\nThen you can use ssh -T git@gitee.com to test connection"
        return 1
    fi

    if [[ $ssh_works == true ]]; then
        log_info "SSH connection test successful, will use SSH protocol"
        export PROTOCOL="ssh"
    else
        log_error "SSH connection test failed"
        return 1
    fi

    return 0
}

# Check repo command
check_repo_command() {
    log_info "Checking repo command..."

    if ! command -v repo >/dev/null 2>&1; then
        log_warning "repo command not found, need to install"
        return 1
    fi

    # Check if only launcher exists
    local repo_output
    repo_output=$(repo --version 2>/dev/null || true)

    if echo "$repo_output" | grep -q "<repo not installed>"; then
        log_info "Detected repo launcher, but actual repo not installed"
        return 0
    fi

    # Check version - look for line containing "repo version" 
    local current_version
    current_version=$(echo "$repo_output" | grep "^repo version" | grep -oE 'v[0-9]+\.[0-9]+' | head -1 | sed 's/v//')

    if [[ -z "$current_version" ]]; then
        log_warning "Unable to get repo version info"
        return 1
    fi

    # Version comparison
    if printf '%s\n%s\n' "$REQUIRED_REPO_VERSION" "$current_version" | sort -V -C; then
        log_success "repo version check passed: v$current_version (required >= $REQUIRED_REPO_VERSION)"
        return 0
    else
        log_warning "repo version too low: v$current_version (required >= $REQUIRED_REPO_VERSION)"
        return 1
    fi
}

# Install repo command
install_repo_command() {
    log_info "Installing repo command..."

    # Define all possible launcher URLs and repo URLs
    local launcher_urls=()
    local repo_urls=()

    if [[ "$NETWORK_TYPE" == "internal" ]]; then
        launcher_urls=(
            "https://storage.googleapis.com/git-repo-downloads/repo"
            "https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
        )
        repo_urls=(
            "http://gerrit.dc.com:8080/git-repo"
            "https://gerrit.googlesource.com/git-repo"
            "https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
        )
    else
        launcher_urls=(
            "https://storage.googleapis.com/git-repo-downloads/repo"
            "https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
        )
        repo_urls=(
            "https://gerrit.googlesource.com/git-repo"
            "https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
        )
    fi

    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"

    # Test launcher URLs
    local download_url=""
    log_info "Testing repo launcher sources..."
    for url in "${launcher_urls[@]}"; do
        log_debug "Testing launcher: $url"
        if curl -L --connect-timeout 5 --max-time 30 -f "$url" -o /dev/null 2>/dev/null; then
            download_url="$url"
            log_success "Found working launcher: $download_url"
            break
        else
            log_warning "Failed to access launcher: $url"
        fi
    done

    if [[ -z "$download_url" ]]; then
        log_error "No accessible repo launcher found"
        log_info "You need to install repo launcher manually"
        return 1
    fi

    # Test repo URLs
    local repo_url=""
    log_info "Testing repo runtime sources..."
    for url in "${repo_urls[@]}"; do
        log_info "Testing repo source: $url"
        if timeout 5 git ls-remote --heads "$url" >/dev/null 2>&1; then
            repo_url="$url"
            log_success "Found working repo source: $repo_url"
            break
        else
            log_warning "Failed to access repo source: $url"
        fi
    done

    if [[ -z "$repo_url" ]]; then
        log_error "No accessible repo source found"
        return 1
    fi

    export REPO_URL="$repo_url"

    # Download repo launcher
    log_info "Downloading repo launcher from $download_url..."
    if ! curl -L "$download_url" -o "$install_dir/repo"; then
        log_error "Failed to download repo launcher"
        return 1
    fi

    # Check repo launcher contents
    if grep -q "<!DOCTYPE html>" "$install_dir/repo"; then
        log_error "Repo launcher is not a valid executable"
        log_info "Repo launcher contents:"
        log_info "$(cat "$install_dir/repo")"
        return 1
    fi

    chmod +x "$install_dir/repo"

    # Add to PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        echo "export PATH=\"$install_dir:\$PATH\"" >> "$HOME/.bashrc"
        export PATH="$install_dir:$PATH"
        log_info "$install_dir added to PATH"
    fi

    # Set REPO_URL in bashrc
    if ! grep -q "REPO_URL" "$HOME/.bashrc" 2>/dev/null; then
        echo "export REPO_URL='$REPO_URL'" >> "$HOME/.bashrc"
        log_info "REPO_URL set to: $REPO_URL in .bashrc"
    fi

    log_success "repo installation complete"
    log_info "Using launcher: $download_url"
    log_info "Using repo source: $repo_url"
    return 0
}

# 3. Determine Buildroot repo URL, branch, and manifest file
determine_repository_config() {
    log_info "Determining repository configuration..."

    # Only support external versions now
    log_info "Configuring external repository..."

    if [[ "$PROTOCOL" == "ssh" ]]; then
        export REPO_URL_MANIFEST="git@gitee.com:spacemit-buildroot/manifests.git"
    else
        export REPO_URL_MANIFEST="https://gitee.com/spacemit-buildroot/manifests.git"
    fi
    export REPO_BRANCH="main"
    export MANIFEST_FILE="${EXTERNAL_VERSION_MAP[$VERSION]}"
    export WORK_BRANCH="${EXTERNAL_BRANCH_MAP[$VERSION]}"

    log_success "Repository configuration determined"
    log_info "Repository URL: $REPO_URL_MANIFEST"
    log_info "Branch: $REPO_BRANCH"
    log_info "Manifest file: $MANIFEST_FILE"
    log_info "Work branch: $WORK_BRANCH"

    return 0
}

# 4. Download code
download_code() {
    log_info "Starting code download..."

    # Ensure target directory exists
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"

    # Set REPO_URL for repo sync
    if [[ "$NETWORK_TYPE" == "internal" ]]; then
        export REPO_URL="http://gerrit.dc.com:8080/git-repo"
        log_info "Using internal repo source: $REPO_URL"
    else
        if [[ -z "$REPO_URL" ]]; then
            # Test repo URLs if REPO_URL is not set
            local repo_urls=(
                "https://gerrit.googlesource.com/git-repo"
                "https://mirrors.tuna.tsinghua.edu.cn/git/git-repo"
            )

            local repo_url=""
            log_info "Testing repo runtime sources..."
            for url in "${repo_urls[@]}"; do
                log_debug "Testing repo source: $url"
                if timeout 5 git ls-remote --heads "$url" >/dev/null 2>&1; then
                    repo_url="$url"
                    log_success "Found working repo source: $repo_url"
                    break
                else
                    log_warning "Failed to access repo source: $url"
                fi
            done

            if [[ -z "$repo_url" ]]; then
                log_error "No accessible repo source found"
                return 1
            fi
            export REPO_URL="$repo_url"
        fi
        log_info "Using repo source: $REPO_URL"
    fi

    # Build repo init command
    local repo_init_cmd="repo init -u \"$REPO_URL_MANIFEST\" -b \"$REPO_BRANCH\" -m \"$MANIFEST_FILE\""

    if [[ $SHALLOW_CLONE == true ]]; then
        repo_init_cmd="$repo_init_cmd --depth=1"
        log_info "Using shallow clone mode"
    fi

    log_info "Running repo init..."
    log_debug "Command: $repo_init_cmd"

    if [[ $DEBUG_MODE == true ]]; then
        eval "$repo_init_cmd"
    else
        eval "$repo_init_cmd" >/dev/null 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        log_error "repo init failed"
        return 1
    fi

    # Check repo version again
    log_info "Checking repo version..."
    if ! check_repo_command; then
        log_error "repo version after init still does not meet requirements, please delete .repo directory and retry"
        log_info "Delete command: rm -rf .repo"
        return 1
    fi

    # If using http protocol, patch manifest remotes if needed
    if [[ "$PROTOCOL" == "http" ]]; then
        manifest_path=".repo/manifests/$MANIFEST_FILE"
        if [[ -f "$manifest_path" ]]; then
            log_info "Checking manifest remotes in $manifest_path"
            # replace git@gitee.com:spacemit-buildroot
            if grep -q 'git@gitee.com:spacemit-buildroot' "$manifest_path"; then
                sed -i -E "s#git@gitee.com:spacemit-buildroot#https://gitee.com/spacemit-buildroot#g" "$manifest_path"
                log_info "Patched manifest remotes to use https"
            else
                log_debug "No git@gitee.com:spacemit-buildroot remotes found in manifest"
            fi
        else
            log_error "Manifest file not found: $manifest_path"
            return 1
        fi
    fi

    # repo sync
    log_info "Starting code sync..."
    local jobs
    jobs=$(nproc)
    log_info "Using $jobs parallel jobs"

    if [[ $DEBUG_MODE == true ]]; then
        repo sync -j"$jobs"
    else
        repo sync -j"$jobs" >/dev/null 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        log_error "repo sync failed"
        return 1
    fi

    # repo start
    log_info "Starting work branch: $WORK_BRANCH"
    if [[ $DEBUG_MODE == true ]]; then
        repo start "$WORK_BRANCH" --all
    else
        repo start "$WORK_BRANCH" --all >/dev/null 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        log_error "repo start failed"
        return 1
    fi

    log_success "Code download complete"
    cd - >/dev/null 2>&1
    return 0
}

# 5. Download buildroot dependencies
download_buildroot_dependencies() {
    log_info "Downloading buildroot dependencies..."

    # Only prompt in external network
    if [[ "$NETWORK_TYPE" == "external" ]]; then
        echo
        log_info "Detected external network, please choose download method:"
        echo "1) Download from default address (http://archive.spacemit.com/buildroot/dl)"
        echo "2) Copy from existing directory"
        echo "3) Skip download"

        while true; do
            read -p "Please select (1/2/3): " choice
            case $choice in
                1)
                    log_info "Downloading from default address..."
                    download_from_archive
                    break
                    ;;
                2)
                    download_from_existing_dir
                    break
                    ;;
                3)
                    log_info "Skipping buildroot dependencies download"
                    return 0
                    ;;
                *)
                    echo "Please enter 1, 2 or 3"
                    ;;
            esac
        done
    else
        # Internal network, download directly
        download_from_archive
    fi

    return 0
}

# Download from archive
download_from_archive() {
    local dl_dir="$TARGET_DIR"
    mkdir -p "$dl_dir"

    log_info "Downloading to directory: $dl_dir"

    if [[ $DEBUG_MODE == true ]]; then
        wget -c -r -nv -np -nH -R "index.html*" -P "$dl_dir" http://archive.spacemit.com/buildroot/dl/
    else
        wget -c -r -nv -np -nH -R "index.html*" -P "$dl_dir" http://archive.spacemit.com/buildroot/dl/ >/dev/null 2>&1
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Buildroot dependencies download complete"
    else
        log_warning "Buildroot dependencies download failed, missing packages will be downloaded during build"
    fi
}

# Copy from existing directory
download_from_existing_dir() {
    echo
    read -p "Please enter the path to an existing buildroot/dl directory: " existing_dir

    if [[ ! -d "$existing_dir" ]]; then
        log_error "Directory does not exist: $existing_dir"
        return 1
    fi

    local dl_dir="$TARGET_DIR/buildroot/dl"
    log_info "Copying from $existing_dir to $dl_dir"

    mkdir -p "$dl_dir"

    if [[ $DEBUG_MODE == true ]]; then
        cp -r "$existing_dir"/* "$dl_dir"/
    else
        cp -r "$existing_dir"/* "$dl_dir"/ >/dev/null 2>&1
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Buildroot dependencies copy complete"
    else
        log_error "Buildroot dependencies copy failed"
        return 1
    fi
}

# Interactive selection mode
interactive_mode() {
    echo "=== Buildroot for K1 Interactive Download ==="
    echo

    # Version selection
    echo "Please select the version to download:"
    echo "1) v2.2 (latest, recommended)"
    echo "2) v2.1"
    echo "3) v2.0"
    echo "4) v1.0"
    echo

    while true; do
        read -p "Please select (1-4): " choice
        case $choice in
            1) VERSION="v2.2"; break ;;
            2) VERSION="v2.1"; break ;;
            3) VERSION="v2.0"; break ;;
            4) VERSION="v1.0"; break ;;
            *)
                echo "Invalid selection, please enter 1-4"
                ;;
        esac
    done

    echo
    # Shallow clone selection
    read -p "Enable shallow clone (save time and space)? [y/N]: " shallow_choice
    if [[ "$shallow_choice" =~ ^[Yy]$ ]]; then
        SHALLOW_CLONE=true
    else
        SHALLOW_CLONE=false
    fi

    echo
    # Debug mode selection
    read -p "Enable debug mode (show detailed info)? [y/N]: " debug_choice
    if [[ "$debug_choice" =~ ^[Yy]$ ]]; then
        DEBUG_MODE=true
    else
        DEBUG_MODE=false
    fi

    echo
    # Target directory selection
    read -p "Please enter target directory (leave blank for default ./buildroot-k1-$VERSION): " target_dir_input
    if [[ -n "$target_dir_input" ]]; then
        TARGET_DIR="$target_dir_input"
    else
        TARGET_DIR="./buildroot-k1-$VERSION"
    fi

    echo
    echo "=== Download configuration ==="
    echo "Version: $VERSION"
    echo "Shallow clone: $([[ $SHALLOW_CLONE == true ]] && echo "enabled" || echo "disabled")"
    echo "Debug mode: $([[ $DEBUG_MODE == true ]] && echo "enabled" || echo "disabled")"
    echo "Target directory: $TARGET_DIR"
    echo

    read -p "Confirm to start download? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Download cancelled"
        exit 0
    fi

    echo

    log_info "Interactive configuration complete, starting download..."
}

# Main function
main() {
    echo "============================================"
    echo "   Buildroot for K1 Quick Download Script  "
    echo "============================================"
    echo

    # If no arguments, enter interactive mode
    if [[ $# -eq 0 ]]; then
        interactive_mode
    else
        # Parse command line arguments
        while [[ $# -gt 0 ]]; do
            case $1 in
                -v|--version)
                    VERSION="$2"
                    shift 2
                    ;;
                -s|--shallow)
                    SHALLOW_CLONE=true
                    shift
                    ;;
                -d|--debug)
                    DEBUG_MODE=true
                    shift
                    ;;
                -t|--target-dir)
                    TARGET_DIR="$2"
                    shift 2
                    ;;
                -h|--help)
                    show_help
                    exit 0
                    ;;
                *)
                    log_error "Unknown argument: $1"
                    show_help
                    exit 1
                    ;;
            esac
        done
    fi
    validate_arguments

    echo
    log_info "Starting environment check..."

    # 2. Check environment
    check_required_commands || exit 1
    check_network_environment || exit 1
    identify_download_protocol || exit 1
    # Check and install repo
    if ! check_repo_command; then
        install_repo_command || exit 1
    fi
    echo

    # 3. Determine repo config
    determine_repository_config || exit 1
    echo

    # 4. Download code
    download_code || exit 1
    echo

    # 5. Download buildroot dependencies
    download_buildroot_dependencies || exit 1
    echo

    log_success "============================================"
    log_success "           All tasks complete!            "
    log_success "============================================"
    echo
    log_info "Code directory: $(realpath "$TARGET_DIR")"
    log_info "Getting started:"
    log_info "  cd $(realpath "$TARGET_DIR")"
    log_info "  make help"
    echo
}

# Run main function
main "$@"
