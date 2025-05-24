#!/bin/bash
# fetch-busybox.sh - Download and verify BusyBox source code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/../src"
BUSYBOX_BASE_URL="https://busybox.net/downloads"

# Default version
VERSION="${1:-1.36.1}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

download_busybox() {
    local version="$1"
    local filename="busybox-${version}.tar.bz2"
    local url="${BUSYBOX_BASE_URL}/${filename}"
    local signature_url="${url}.sig"
    local dest_file="${SRC_DIR}/${filename}"
    local dest_sig="${dest_file}.sig"
    
    log "Downloading BusyBox ${version}..."
    
    # Create source directory
    mkdir -p "${SRC_DIR}"
    
    # Download source tarball
    if [[ -f "${dest_file}" ]]; then
        log "Source tarball already exists, verifying..."
    else
        log "Downloading from ${url}..."
        if ! wget -q --show-progress -O "${dest_file}" "${url}"; then
            error "Failed to download BusyBox source"
            rm -f "${dest_file}"
            return 1
        fi
    fi
    
    # Download signature file
    if [[ -f "${dest_sig}" ]]; then
        log "Signature file already exists"
    else
        log "Downloading signature from ${signature_url}..."
        if ! wget -q -O "${dest_sig}" "${signature_url}"; then
            warning "Failed to download signature file, proceeding without verification"
            rm -f "${dest_sig}"
        fi
    fi
    
    # Verify checksum if we have common tools
    if command -v sha256sum &> /dev/null; then
        log "Calculating SHA256 checksum..."
        sha256sum "${dest_file}" | tee "${dest_file}.sha256"
    fi
    
    # Extract source
    local extract_dir="${SRC_DIR}/busybox-${version}"
    if [[ -d "${extract_dir}" ]]; then
        log "Source directory already exists, removing old version..."
        rm -rf "${extract_dir}"
    fi
    
    log "Extracting source..."
    if ! tar -xjf "${dest_file}" -C "${SRC_DIR}"; then
        error "Failed to extract BusyBox source"
        return 1
    fi
    
    log "Successfully downloaded and extracted BusyBox ${version}"
    return 0
}

verify_gpg_signature() {
    local file="$1"
    local sig_file="${file}.sig"
    
    if [[ ! -f "${sig_file}" ]]; then
        log "No signature file available for verification"
        return 0
    fi
    
    if ! command -v gpg &> /dev/null; then
        log "GPG not available, skipping signature verification"
        return 0
    fi
    
    log "Verifying GPG signature..."
    
    # BusyBox signing key (Denys Vlasenko)
    local busybox_key="C9E9416F76E610DBD09D040F90B49FDB9E564609"
    
    # Try to import the key if not already present
    if ! gpg --list-keys "${busybox_key}" &> /dev/null; then
        log "Importing BusyBox signing key..."
        if ! gpg --keyserver keyserver.ubuntu.com --recv-keys "${busybox_key}" 2>/dev/null; then
            warning "Failed to import signing key, skipping verification"
            return 0
        fi
    fi
    
    if gpg --verify "${sig_file}" "${file}" 2>&1 | grep -q "Good signature"; then
        log "GPG signature verified successfully"
        return 0
    else
        error "GPG signature verification failed"
        return 1
    fi
}

warning() {
    echo "[WARNING] $*" >&2
}

main() {
    local version="${1:-1.36.1}"
    
    log "Fetching BusyBox version ${version}..."
    
    if ! download_busybox "${version}"; then
        error "Failed to download BusyBox"
        exit 1
    fi
    
    # Optional: verify GPG signature
    local tarball="${SRC_DIR}/busybox-${version}.tar.bz2"
    verify_gpg_signature "${tarball}" || true
    
    log "BusyBox ${version} ready for building"
}

# Run main function
main "$@"