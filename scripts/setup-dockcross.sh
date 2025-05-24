#!/bin/bash
# setup-dockcross.sh - Download and setup dockcross scripts for cross-compilation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKCROSS_DIR="${SCRIPT_DIR}/../dockcross"
DOCKCROSS_REPO="https://github.com/dockcross/dockcross"

# Architecture mappings
declare -A DOCKCROSS_IMAGES=(
    # Linux x86/x64
    ["x86_64"]="linux-x86_64-full"
    ["x86_64-full"]="linux-x86_64-full"
    ["i386"]="linux-x86"
    
    # Linux ARM
    ["arm64"]="linux-arm64"
    ["arm64-lts"]="linux-arm64-lts"
    ["arm64-full"]="linux-arm64-full"
    ["arm64-musl"]="linux-arm64-musl"
    ["armv6-musl"]="linux-armv6-musl"
    
    # Android targets
    ["android-arm"]="android-arm"
    ["android-arm64"]="android-arm64"
    ["android-x86"]="android-x86"
    ["android-x86_64"]="android-x86_64"
    
    # Linux MIPS
    ["mips"]="linux-mips"
    ["mipsel"]="linux-mipsel-lts"
    
    # Other architectures
    ["s390x"]="linux-s390x"
    ["riscv32"]="linux-riscv32"
    ["riscv64"]="linux-riscv64"
)

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

setup_dockcross() {
    local arch="$1"
    local image="${DOCKCROSS_IMAGES[$arch]}"
    
    if [[ -z "$image" ]]; then
        error "Unknown architecture: $arch"
        return 1
    fi
    
    local script_name="dockcross-${image}"
    local script_path="${DOCKCROSS_DIR}/${script_name}"
    
    if [[ -f "$script_path" ]]; then
        log "Dockcross script for ${arch} already exists, skipping..."
        return 0
    fi
    
    log "Setting up dockcross for ${arch} (${image})..."
    
    # First check if the image exists
    log "Pulling Docker image dockcross/${image}..."
    if ! docker pull "dockcross/${image}" 2>&1 | grep -E "(Downloaded|Image is up to date|Pull complete)"; then
        error "Failed to pull dockcross/${image} - image may not exist"
        error "Skipping ${arch}"
        return 1
    fi
    
    # Pull the docker image and create the script
    docker run --rm "dockcross/${image}" > "${script_path}"
    
    if [[ ! -s "${script_path}" ]]; then
        error "Failed to create dockcross script for ${arch}"
        rm -f "${script_path}"
        return 1
    fi
    
    chmod +x "${script_path}"
    log "Successfully set up dockcross for ${arch}"
}

main() {
    log "Setting up dockcross environment..."
    
    # Create dockcross directory
    mkdir -p "${DOCKCROSS_DIR}"
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        error "Docker is required but not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Download dockcross scripts for all architectures
    local failed=false
    for arch in "${!DOCKCROSS_IMAGES[@]}"; do
        if ! setup_dockcross "$arch"; then
            failed=true
        fi
    done
    
    if [[ "$failed" == "true" ]]; then
        error "Some dockcross setups failed"
        exit 1
    fi
    
    log "Dockcross setup completed successfully!"
    log "Available architectures:"
    ls -1 "${DOCKCROSS_DIR}"/dockcross-* 2>/dev/null | sed 's/.*dockcross-/  - /'
}

# Run main function
main "$@"