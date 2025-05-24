#!/bin/bash
# package-release.sh - Package built binaries for release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BUILD_DIR="${PROJECT_ROOT}/build"
RELEASES_DIR="${PROJECT_ROOT}/releases"

# Arguments
VERSION="${1:?BusyBox version required}"
TARGETS="${2:?Target architectures required}"

# Release timestamp
RELEASE_DATE=$(date +%Y%m%d)
RELEASE_TAG="v${VERSION}-${RELEASE_DATE}"

log() {
    echo "[PACKAGE] $(date +'%H:%M:%S') $*"
}

error() {
    echo "[ERROR] $*" >&2
}

create_checksums() {
    local dir="$1"
    local checksum_file="$2"
    
    log "Creating checksums..."
    
    cd "${dir}"
    
    # SHA256 checksums
    if command -v sha256sum &> /dev/null; then
        sha256sum busybox-* > "${checksum_file}.sha256"
        log "Created SHA256 checksums"
    fi
    
    # SHA512 checksums
    if command -v sha512sum &> /dev/null; then
        sha512sum busybox-* > "${checksum_file}.sha512"
        log "Created SHA512 checksums"
    fi
    
    # MD5 checksums (for compatibility)
    if command -v md5sum &> /dev/null; then
        md5sum busybox-* > "${checksum_file}.md5"
        log "Created MD5 checksums"
    fi
}

create_release_archive() {
    local version="$1"
    local release_dir="${RELEASES_DIR}/busybox-${version}-${RELEASE_DATE}"
    
    log "Creating release archive..."
    
    # Create release directory
    mkdir -p "${release_dir}"
    
    # Copy all built binaries
    local binary_count=0
    for target in ${TARGETS}; do
        local binary="${BUILD_DIR}/busybox-${version}-${target}"
        if [[ -f "${binary}" ]]; then
            cp "${binary}" "${release_dir}/"
            ((binary_count++))
        else
            error "Binary not found for ${target}: ${binary}"
        fi
    done
    
    if [[ ${binary_count} -eq 0 ]]; then
        error "No binaries found to package"
        return 1
    fi
    
    log "Copied ${binary_count} binaries to release directory"
    
    # Create README for the release
    cat > "${release_dir}/README.md" << EOF
# BusyBox ${version} - Forensic Build

Release Date: $(date +"%Y-%m-%d")
Release Tag: ${RELEASE_TAG}

## About

This release contains statically compiled BusyBox binaries optimized for forensic analysis.
These binaries can run on systems without dependencies and include tools commonly used in digital forensics.

## Architectures

This release includes binaries for the following architectures:
EOF
    
    for target in ${TARGETS}; do
        local binary="${release_dir}/busybox-${version}-${target}"
        if [[ -f "${binary}" ]]; then
            local size=$(ls -lh "${binary}" | awk '{print $5}')
            echo "- ${target} (${size})" >> "${release_dir}/README.md"
        fi
    done
    
    cat >> "${release_dir}/README.md" << EOF

## Usage

1. Download the binary for your target architecture
2. Make it executable: \`chmod +x busybox-${version}-<arch>\`
3. Run directly or create symlinks for individual applets

### Example: Running as standalone
\`\`\`bash
./busybox-${version}-x86_64 ls -la
./busybox-${version}-x86_64 hexdump -C file.bin
\`\`\`

### Example: Creating applet symlinks
\`\`\`bash
mkdir -p forensic-tools
cd forensic-tools
../busybox-${version}-x86_64 --install -s .
\`\`\`

## Verification

Verify file integrity using the provided checksums:
\`\`\`bash
sha256sum -c checksums.sha256
\`\`\`

## Included Applets

To see all available applets:
\`\`\`bash
./busybox-${version}-<arch> --list
\`\`\`

## License

BusyBox is licensed under GPLv2. See https://busybox.net/license.html

## Build Information

These binaries were built using:
- BusyBox version: ${version}
- Build system: Buildabox
- Compilation: Static linking with musl libc
- Optimization: Forensic-focused configuration
EOF
    
    # Create checksums
    create_checksums "${release_dir}" "${release_dir}/checksums"
    
    # Create compressed archives
    local archive_base="${RELEASES_DIR}/busybox-${version}-forensic-${RELEASE_DATE}"
    
    log "Creating compressed archives..."
    
    # Create .tar.gz
    cd "${RELEASES_DIR}"
    tar -czf "${archive_base}.tar.gz" "busybox-${version}-${RELEASE_DATE}"
    log "Created ${archive_base}.tar.gz"
    
    # Create .tar.xz (better compression)
    if command -v xz &> /dev/null; then
        tar -cJf "${archive_base}.tar.xz" "busybox-${version}-${RELEASE_DATE}"
        log "Created ${archive_base}.tar.xz"
    fi
    
    # Create .zip (for Windows users)
    if command -v zip &> /dev/null; then
        zip -r "${archive_base}.zip" "busybox-${version}-${RELEASE_DATE}"
        log "Created ${archive_base}.zip"
    fi
    
    # Create individual binary archives
    log "Creating individual binary archives..."
    mkdir -p "${RELEASES_DIR}/individual"
    
    for target in ${TARGETS}; do
        local binary="busybox-${version}-${target}"
        if [[ -f "${release_dir}/${binary}" ]]; then
            cd "${release_dir}"
            tar -czf "${RELEASES_DIR}/individual/${binary}.tar.gz" "${binary}"
            log "Created individual archive for ${target}"
        fi
    done
    
    return 0
}

create_release_notes() {
    local version="$1"
    local notes_file="${RELEASES_DIR}/RELEASE_NOTES-${RELEASE_TAG}.md"
    
    log "Creating release notes..."
    
    cat > "${notes_file}" << EOF
# Release Notes - BusyBox ${version} Forensic Build

**Release Tag:** ${RELEASE_TAG}  
**Release Date:** $(date +"%Y-%m-%d")  
**BusyBox Version:** ${version}

## Overview

This release provides statically compiled BusyBox binaries optimized for digital forensics and incident response.

## What's Included

### Architectures
$(for target in ${TARGETS}; do echo "- ${target}"; done)

### Key Features
- Statically linked (no external dependencies)
- Forensic-focused applet selection
- Cross-platform compatibility via QEMU
- Minimal size while maintaining functionality

## Download

### Full Release Archives
- \`busybox-${version}-forensic-${RELEASE_DATE}.tar.gz\` - All architectures
- \`busybox-${version}-forensic-${RELEASE_DATE}.tar.xz\` - All architectures (smaller)
- \`busybox-${version}-forensic-${RELEASE_DATE}.zip\` - All architectures (Windows-friendly)

### Individual Binaries
Available in the \`individual/\` directory:
$(for target in ${TARGETS}; do echo "- \`busybox-${version}-${target}.tar.gz\`"; done)

## Verification

All files include SHA256, SHA512, and MD5 checksums in the \`checksums.*\` files.

## Quick Start

\`\`\`bash
# Download and extract
tar -xzf busybox-${version}-forensic-${RELEASE_DATE}.tar.gz
cd busybox-${version}-${RELEASE_DATE}

# Verify checksums
sha256sum -c checksums.sha256

# Use the binary
./busybox-${version}-x86_64 --help
\`\`\`

## Building from Source

To build these binaries yourself, use the Buildabox project:
\`\`\`bash
git clone https://github.com/yourusername/buildabox
cd buildabox
./build.sh --version ${version}
\`\`\`

## Support

For issues or questions, please open an issue in the Buildabox repository.

---
*This release was automatically generated by Buildabox*
EOF
    
    log "Created release notes: ${notes_file}"
}

main() {
    log "Packaging release for BusyBox ${VERSION}..."
    log "Architectures: ${TARGETS}"
    
    # Create releases directory
    mkdir -p "${RELEASES_DIR}"
    
    # Create release archive
    if ! create_release_archive "${VERSION}"; then
        error "Failed to create release archive"
        exit 1
    fi
    
    # Create release notes
    create_release_notes "${VERSION}"
    
    # Show release summary
    log "Release packaging completed!"
    log "Release files:"
    ls -lh "${RELEASES_DIR}"/*.tar.* 2>/dev/null || true
    ls -lh "${RELEASES_DIR}"/*.zip 2>/dev/null || true
    
    log "Individual binaries:"
    ls -lh "${RELEASES_DIR}/individual/" 2>/dev/null || true
    
    log "Release tag: ${RELEASE_TAG}"
}

# Run main function
main "$@"