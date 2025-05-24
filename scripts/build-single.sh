#!/bin/bash
# build-single.sh - Build BusyBox for a single architecture

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
DOCKCROSS_DIR="${PROJECT_ROOT}/dockcross"
SRC_DIR="${PROJECT_ROOT}/src"
BUILD_DIR="${PROJECT_ROOT}/build"
CONFIGS_DIR="${PROJECT_ROOT}/configs"

# Arguments
ARCH="${1:?Architecture required}"
VERSION="${2:?BusyBox version required}"
CONFIG_FILE="${3:?Config file required}"

# Architecture to dockcross mapping
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
    echo "[${ARCH}] $(date +'%H:%M:%S') $*"
}

error() {
    echo "[${ARCH}] [ERROR] $*" >&2
}

get_arch_config() {
    local arch="$1"
    local base_config="$2"
    local arch_config="${CONFIGS_DIR}/arch-specific/${arch}.config"
    
    # If architecture-specific config exists, merge it with base
    if [[ -f "${arch_config}" ]]; then
        log "Found architecture-specific config for ${arch}"
        # Merge configs (arch-specific overrides base)
        cat "${base_config}" > "${BUILD_DIR}/.config.${arch}"
        cat "${arch_config}" >> "${BUILD_DIR}/.config.${arch}"
        echo "${BUILD_DIR}/.config.${arch}"
    else
        echo "${base_config}"
    fi
}

prepare_build_env() {
    local arch="$1"
    local build_subdir="${BUILD_DIR}/${arch}"
    
    # Create build directory for this architecture
    mkdir -p "${build_subdir}"
    
    # Check if source exists
    if [[ ! -d "${SRC_DIR}/busybox-${VERSION}" ]]; then
        error "BusyBox source directory not found: ${SRC_DIR}/busybox-${VERSION}"
        error "Please run './scripts/fetch-busybox.sh ${VERSION}' first"
        return 1
    fi
    
    # Copy source to build directory
    log "Preparing build environment..."
    cp -r "${SRC_DIR}/busybox-${VERSION}" "${build_subdir}/busybox"
    
    # Get appropriate config
    local config_to_use=$(get_arch_config "${arch}" "${CONFIG_FILE}")
    
    # Copy config to build directory
    cp "${config_to_use}" "${build_subdir}/busybox/.config"
    
    echo "${build_subdir}/busybox"
}

build_busybox() {
    local arch="$1"
    local dockcross_image="${DOCKCROSS_IMAGES[$arch]}"
    
    if [[ -z "$dockcross_image" ]]; then
        error "Unknown architecture: $arch"
        return 1
    fi
    
    local dockcross_script="${DOCKCROSS_DIR}/dockcross-${dockcross_image}"
    
    if [[ ! -x "${dockcross_script}" ]]; then
        error "Dockcross script not found for ${arch}: ${dockcross_script}"
        error "Please run './scripts/setup-dockcross.sh' first to download dockcross images"
        error "Available dockcross scripts:"
        ls -la "${DOCKCROSS_DIR}"/dockcross-* 2>/dev/null || echo "  None found"
        return 1
    fi
    
    # Prepare build environment
    local build_path=$(prepare_build_env "${arch}")
    if [[ -z "${build_path}" ]]; then
        error "Failed to prepare build environment"
        return 1
    fi
    
    log "Starting build for ${arch} using ${dockcross_image}..."
    log "Build path: ${build_path}"
    
    # Build commands
    local build_commands="
        cd /work/busybox && \
        echo 'Starting BusyBox build...' && \
        make oldconfig && \
        echo 'Configuration complete, starting compilation...' && \
        make -j\$(nproc) LDFLAGS='-static' CFLAGS='-Os' V=1 && \
        echo 'Compilation complete, installing...' && \
        make install && \
        echo 'Installation complete' && \
        ls -la _install/bin/
    "
    
    # Run build in dockcross container
    log "Executing build in dockcross container..."
    if ! cd "${BUILD_DIR}/${arch}" && "${dockcross_script}" bash -c "${build_commands}" 2>&1 | tee build.log; then
        error "Build failed for ${arch}"
        error "Last 20 lines of build log:"
        tail -20 build.log || true
        return 1
    fi
    
    # Copy the built binary to the main build directory
    local binary_src="${build_path}/_install/bin/busybox"
    local binary_dst="${BUILD_DIR}/busybox-${VERSION}-${arch}"
    
    if [[ ! -f "${binary_src}" ]]; then
        error "Built binary not found: ${binary_src}"
        return 1
    fi
    
    cp "${binary_src}" "${binary_dst}"
    
    # Strip the binary to reduce size
    log "Stripping binary..."
    if ! cd "${BUILD_DIR}/${arch}" && "${dockcross_script}" strip "/work/../busybox-${VERSION}-${arch}"; then
        log "Warning: Failed to strip binary, continuing anyway"
    fi
    
    # Make it executable
    chmod +x "${binary_dst}"
    
    # Show binary info
    local size=$(ls -lh "${binary_dst}" | awk '{print $5}')
    log "Build complete! Binary size: ${size}"
    
    # Clean up build directory to save space
    rm -rf "${BUILD_DIR}/${arch}"
    
    return 0
}

main() {
    log "Building BusyBox ${VERSION} for ${ARCH}..."
    
    # Verify prerequisites
    if [[ ! -d "${SRC_DIR}/busybox-${VERSION}" ]]; then
        error "BusyBox source not found. Run fetch-busybox.sh first."
        exit 1
    fi
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
    
    # Build BusyBox
    if ! build_busybox "${ARCH}"; then
        error "Build failed for ${ARCH}"
        exit 1
    fi
    
    log "Successfully built BusyBox for ${ARCH}"
}

# Run main function
main "$@"