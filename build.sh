#!/bin/bash
# build.sh - Main build orchestrator for Buildabox
# Builds statically compiled BusyBox binaries for multiple architectures

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
BUILD_DIR="${SCRIPT_DIR}/build"
RELEASES_DIR="${SCRIPT_DIR}/releases"
SRC_DIR="${SCRIPT_DIR}/src"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
DOCKCROSS_DIR="${SCRIPT_DIR}/dockcross"

# Default options
BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.36.1}"
BUILD_TARGETS="${BUILD_TARGETS:-x86_64-full i386 arm64 arm64-musl}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIGS_DIR}/busybox-forensic.config}"
PARALLEL_BUILDS="${PARALLEL_BUILDS:-4}"
SKIP_TESTS="${SKIP_TESTS:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Build statically compiled BusyBox binaries for multiple architectures.

Options:
    -h, --help              Show this help message
    -v, --version VERSION   BusyBox version to build (default: ${BUSYBOX_VERSION})
    -t, --targets TARGETS   Space-separated list of targets (default: ${BUILD_TARGETS})
    -c, --config FILE       BusyBox config file (default: ${CONFIG_FILE})
    -j, --jobs N            Number of parallel builds (default: ${PARALLEL_BUILDS})
    -s, --skip-tests        Skip testing built binaries
    -C, --clean             Clean build directories before building
    -r, --release           Package binaries for release after building

Supported targets:
    Linux: x86_64-full, i386, arm64, arm64-lts, arm64-full, 
           arm64-musl, armv6-musl, mips, mipsel, s390x, riscv32, riscv64
    Android: android-arm, android-arm64, android-x86, android-x86_64

Examples:
    # Build for all default architectures
    $0

    # Build only for x86_64 and arm64
    $0 --targets "x86_64 arm64"

    # Build BusyBox 1.35.0 with custom config
    $0 --version 1.35.0 --config my-config.config

    # Clean build and create release packages
    $0 --clean --release
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                BUSYBOX_VERSION="$2"
                shift 2
                ;;
            -t|--targets)
                BUILD_TARGETS="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -j|--jobs)
                PARALLEL_BUILDS="$2"
                shift 2
                ;;
            -s|--skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            -C|--clean)
                CLEAN_BUILD=true
                shift
                ;;
            -r|--release)
                CREATE_RELEASE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

setup_environment() {
    log "Setting up build environment..."
    
    # Create necessary directories
    mkdir -p "${BUILD_DIR}" "${RELEASES_DIR}" "${SRC_DIR}" "${DOCKCROSS_DIR}"
    
    # Clean build directory if requested
    if [[ "${CLEAN_BUILD:-false}" == "true" ]]; then
        log "Cleaning build directories..."
        rm -rf "${BUILD_DIR:?}"/*
        rm -rf "${SRC_DIR:?}"/*
    fi
    
    # Check if dockcross scripts exist
    if [[ ! -f "${DOCKCROSS_DIR}/dockcross-linux-x64" ]]; then
        log "Dockcross scripts not found. Running setup..."
        "${SCRIPTS_DIR}/setup-dockcross.sh"
    fi
    
    # Check if BusyBox source exists
    if [[ ! -d "${SRC_DIR}/busybox-${BUSYBOX_VERSION}" ]]; then
        log "BusyBox source not found. Downloading..."
        "${SCRIPTS_DIR}/fetch-busybox.sh" "${BUSYBOX_VERSION}"
    fi
    
    # Verify config file exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
}

build_targets() {
    log "Building BusyBox ${BUSYBOX_VERSION} for targets: ${BUILD_TARGETS}"
    
    local build_pids=()
    local build_count=0
    
    for target in ${BUILD_TARGETS}; do
        # Limit parallel builds
        if [[ ${build_count} -ge ${PARALLEL_BUILDS} ]]; then
            # Wait for at least one build to complete
            wait -n
            ((build_count--))
        fi
        
        log "Starting build for ${target}..."
        "${SCRIPTS_DIR}/build-single.sh" "${target}" "${BUSYBOX_VERSION}" "${CONFIG_FILE}" &
        build_pids+=($!)
        ((build_count++))
    done
    
    # Wait for all builds to complete
    local failed_builds=()
    for pid in "${build_pids[@]}"; do
        if ! wait "${pid}"; then
            failed_builds+=("${pid}")
        fi
    done
    
    if [[ ${#failed_builds[@]} -gt 0 ]]; then
        error "Some builds failed: ${failed_builds[*]}"
        return 1
    fi
    
    log "All builds completed successfully!"
}

test_binaries() {
    if [[ "${SKIP_TESTS}" == "true" ]]; then
        log "Skipping binary tests (--skip-tests specified)"
        return 0
    fi
    
    log "Testing built binaries..."
    
    local test_failed=false
    for target in ${BUILD_TARGETS}; do
        local binary="${BUILD_DIR}/busybox-${BUSYBOX_VERSION}-${target}"
        
        if [[ ! -f "${binary}" ]]; then
            error "Binary not found: ${binary}"
            test_failed=true
            continue
        fi
        
        if ! "${SCRIPTS_DIR}/test-binary.sh" "${binary}" "${target}"; then
            error "Test failed for ${target}"
            test_failed=true
        fi
    done
    
    if [[ "${test_failed}" == "true" ]]; then
        error "Some tests failed"
        return 1
    fi
    
    log "All tests passed!"
}

create_release() {
    if [[ "${CREATE_RELEASE:-false}" != "true" ]]; then
        return 0
    fi
    
    log "Creating release packages..."
    "${SCRIPTS_DIR}/package-release.sh" "${BUSYBOX_VERSION}" "${BUILD_TARGETS}"
    
    log "Release packages created in ${RELEASES_DIR}/"
}

main() {
    parse_args "$@"
    
    log "Starting Buildabox build process..."
    log "BusyBox version: ${BUSYBOX_VERSION}"
    log "Build targets: ${BUILD_TARGETS}"
    log "Config file: ${CONFIG_FILE}"
    
    setup_environment
    build_targets
    test_binaries
    create_release
    
    log "Build process completed successfully!"
    
    # Show built binaries
    log "Built binaries:"
    ls -lh "${BUILD_DIR}"/busybox-* 2>/dev/null || true
}

# Run main function
main "$@"
