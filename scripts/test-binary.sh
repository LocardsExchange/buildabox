#!/bin/bash
# test-binary.sh - Test built BusyBox binary with QEMU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Arguments
BINARY="${1:?Binary path required}"
ARCH="${2:?Architecture required}"

# QEMU binary mapping
declare -A QEMU_BINARIES=(
    # Linux x86/x64
    ["x86_64"]="qemu-x86_64-static"
    ["x86_64-full"]="qemu-x86_64-static"
    ["i386"]="qemu-i386-static"
    
    # Linux ARM
    ["arm64"]="qemu-aarch64-static"
    ["arm64-lts"]="qemu-aarch64-static"
    ["arm64-full"]="qemu-aarch64-static"
    ["arm64-musl"]="qemu-aarch64-static"
    ["armv6-musl"]="qemu-arm-static"
    
    # Android targets (use same QEMU binaries as Linux)
    ["android-arm"]="qemu-arm-static"
    ["android-arm64"]="qemu-aarch64-static"
    ["android-x86"]="qemu-i386-static"
    ["android-x86_64"]="qemu-x86_64-static"
    
    # Linux MIPS
    ["mips"]="qemu-mips-static"
    ["mipsel"]="qemu-mipsel-static"
    
    # Other architectures
    ["s390x"]="qemu-s390x-static"
    ["riscv32"]="qemu-riscv32-static"
    ["riscv64"]="qemu-riscv64-static"
)

log() {
    echo "[TEST] $(date +'%H:%M:%S') $*"
}

error() {
    echo "[ERROR] $*" >&2
}

check_prerequisites() {
    # Check if binary exists
    if [[ ! -f "${BINARY}" ]]; then
        error "Binary not found: ${BINARY}"
        return 1
    fi
    
    # Check if binary is executable
    if [[ ! -x "${BINARY}" ]]; then
        error "Binary is not executable: ${BINARY}"
        return 1
    fi
    
    # Check file type
    log "Binary info:"
    file "${BINARY}" || true
    
    return 0
}

get_qemu_binary() {
    local arch="$1"
    local qemu_bin="${QEMU_BINARIES[$arch]}"
    
    if [[ -z "$qemu_bin" ]]; then
        error "Unknown architecture for QEMU: $arch"
        return 1
    fi
    
    # Check if QEMU is installed
    if ! command -v "${qemu_bin}" &> /dev/null; then
        # Try without -static suffix
        qemu_bin="${qemu_bin%-static}"
        if ! command -v "${qemu_bin}" &> /dev/null; then
            error "QEMU not found for ${arch}. Install ${QEMU_BINARIES[$arch]} or ${qemu_bin}"
            return 1
        fi
    fi
    
    echo "${qemu_bin}"
}

run_test() {
    local binary="$1"
    local qemu_bin="$2"
    local test_name="$3"
    shift 3
    local test_args=("$@")
    
    log "Running test: ${test_name}"
    
    if "${qemu_bin}" "${binary}" "${test_args[@]}" &> /tmp/busybox-test.out; then
        log "✓ ${test_name} passed"
        return 0
    else
        error "✗ ${test_name} failed"
        cat /tmp/busybox-test.out
        return 1
    fi
}

test_binary() {
    local binary="$1"
    local arch="$2"
    
    log "Testing BusyBox binary for ${arch}..."
    
    # Get appropriate QEMU binary
    local qemu_bin
    if [[ "${arch}" == "x86_64" ]] && [[ "$(uname -m)" == "x86_64" ]]; then
        # Native execution, no QEMU needed
        log "Native ${arch} detected, running without QEMU"
        qemu_bin=""
    else
        qemu_bin=$(get_qemu_binary "${arch}")
        if [[ -z "${qemu_bin}" ]]; then
            return 1
        fi
        log "Using QEMU: ${qemu_bin}"
    fi
    
    # Test suite
    local failed=false
    
    # Test 1: Version output
    if ! run_test "${binary}" "${qemu_bin}" "version" --version; then
        failed=true
    fi
    
    # Test 2: List applets
    if ! run_test "${binary}" "${qemu_bin}" "list applets" --list; then
        failed=true
    fi
    
    # Test 3: Basic echo
    if "${qemu_bin}" "${binary}" echo "Hello from BusyBox" | grep -q "Hello from BusyBox"; then
        log "✓ echo test passed"
    else
        error "✗ echo test failed"
        failed=true
    fi
    
    # Test 4: Date command
    if ! run_test "${binary}" "${qemu_bin}" "date command" date +%Y; then
        failed=true
    fi
    
    # Test 5: Basic math with expr
    local result=$("${qemu_bin}" "${binary}" expr 2 + 2 2>/dev/null || echo "failed")
    if [[ "${result}" == "4" ]]; then
        log "✓ expr test passed"
    else
        error "✗ expr test failed (got: ${result})"
        failed=true
    fi
    
    # Test 6: String operations
    local str_result=$("${qemu_bin}" "${binary}" basename /path/to/file.txt 2>/dev/null || echo "failed")
    if [[ "${str_result}" == "file.txt" ]]; then
        log "✓ basename test passed"
    else
        error "✗ basename test failed (got: ${str_result})"
        failed=true
    fi
    
    # Test 7: Check for common forensic tools
    log "Checking for forensic applets..."
    local forensic_applets=(
        "hexdump"
        "strings"
        "xxd"
        "md5sum"
        "sha1sum"
        "sha256sum"
        "stat"
        "find"
        "grep"
        "dd"
        "nc"
        "wget"
    )
    
    for applet in "${forensic_applets[@]}"; do
        if "${qemu_bin}" "${binary}" --list | grep -q "^${applet}$"; then
            log "  ✓ ${applet} available"
        else
            log "  ✗ ${applet} not available"
        fi
    done
    
    # Summary
    if [[ "${failed}" == "true" ]]; then
        error "Some tests failed for ${arch}"
        return 1
    else
        log "All tests passed for ${arch}!"
        return 0
    fi
}

main() {
    if ! check_prerequisites; then
        exit 1
    fi
    
    if ! test_binary "${BINARY}" "${ARCH}"; then
        exit 1
    fi
    
    log "Testing completed successfully!"
}

# Run main function
main "$@"