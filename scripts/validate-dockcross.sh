#!/bin/bash
# validate-dockcross.sh - Validate dockcross images and test availability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKCROSS_DIR="${SCRIPT_DIR}/../dockcross"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Architecture mappings (must match other scripts)
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

check_docker() {
    log "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker."
        return 1
    fi
    
    log "Docker is installed and running"
    docker version --format 'Docker version {{.Server.Version}}'
    return 0
}

test_dockcross_image() {
    local arch="$1"
    local image="$2"
    
    echo -n "  Testing ${arch} (${image})... "
    
    # Test if we can pull/run the image
    if docker run --rm "dockcross/${image}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Available${NC}"
        return 0
    else
        echo -e "${RED}✗ Not available${NC}"
        return 1
    fi
}

validate_single_arch() {
    local arch="$1"
    local image="${DOCKCROSS_IMAGES[$arch]}"
    local script_path="${DOCKCROSS_DIR}/dockcross-${image}"
    
    echo -n "Validating ${arch}:"
    
    # Check if script exists
    if [[ -f "${script_path}" ]]; then
        echo -e " ${GREEN}✓ Script exists${NC}"
        
        # Check if it's executable
        if [[ -x "${script_path}" ]]; then
            echo -e "  ${GREEN}✓ Executable${NC}"
        else
            echo -e "  ${YELLOW}! Not executable${NC} (fixing...)"
            chmod +x "${script_path}"
        fi
        
        # Test if the Docker image works
        echo -n "  Testing Docker image... "
        if "${script_path}" echo "test" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Works${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
            return 1
        fi
    else
        echo -e " ${RED}✗ Script missing${NC}"
        return 1
    fi
    
    return 0
}

test_linux_x86_64_full() {
    log "Testing specific image: linux-x86_64-full"
    
    local test_script="${DOCKCROSS_DIR}/dockcross-linux-x86_64-full"
    
    # Test if we can create the script
    log "Attempting to create dockcross script..."
    if docker run --rm dockcross/linux-x86_64-full > "${test_script}.tmp" 2>/dev/null; then
        if [[ -s "${test_script}.tmp" ]]; then
            mv "${test_script}.tmp" "${test_script}"
            chmod +x "${test_script}"
            log "Successfully created dockcross script for linux-x86_64-full"
            
            # Test the script
            log "Testing the script..."
            if "${test_script}" bash -c "echo 'Hello from linux-x86_64-full'; gcc --version" 2>&1; then
                log "linux-x86_64-full is working correctly!"
                return 0
            else
                error "Script execution failed"
                return 1
            fi
        else
            error "Created script is empty"
            rm -f "${test_script}.tmp"
            return 1
        fi
    else
        error "Failed to pull/run dockcross/linux-x86_64-full"
        error "This image might not exist. Checking available images..."
        
        # Try to list what x86_64 images are available
        log "Searching for available x86_64 dockcross images on Docker Hub..."
        warning "Note: This requires internet connection"
        
        return 1
    fi
}

main() {
    log "Validating Dockcross setup for Buildabox"
    
    # Check Docker
    if ! check_docker; then
        exit 1
    fi
    
    # Create dockcross directory if needed
    mkdir -p "${DOCKCROSS_DIR}"
    
    # Test all configured architectures
    log "Testing configured architectures..."
    local failed=0
    local total=0
    
    for arch in "${!DOCKCROSS_IMAGES[@]}"; do
        ((total++))
        if ! test_dockcross_image "$arch" "${DOCKCROSS_IMAGES[$arch]}"; then
            ((failed++))
        fi
    done
    
    echo ""
    log "Summary: $((total - failed))/${total} architectures available"
    
    # Special test for linux-x86_64-full
    echo ""
    test_linux_x86_64_full
    
    # Validate downloaded scripts
    echo ""
    log "Validating downloaded dockcross scripts..."
    
    local scripts_found=0
    local scripts_working=0
    
    for arch in "${!DOCKCROSS_IMAGES[@]}"; do
        if validate_single_arch "$arch"; then
            ((scripts_working++))
        fi
        
        local script="${DOCKCROSS_DIR}/dockcross-${DOCKCROSS_IMAGES[$arch]}"
        if [[ -f "${script}" ]]; then
            ((scripts_found++))
        fi
    done
    
    echo ""
    log "Scripts found: ${scripts_found}"
    log "Scripts working: ${scripts_working}"
    
    if [[ ${scripts_found} -eq 0 ]]; then
        warning "No dockcross scripts found. Run './scripts/setup-dockcross.sh' to download them."
    elif [[ ${scripts_working} -lt ${scripts_found} ]]; then
        warning "Some scripts are not working properly. You may need to re-run setup-dockcross.sh"
    elif [[ ${scripts_working} -eq ${total} ]]; then
        log "All dockcross scripts are working correctly!"
    fi
    
    # Show what's in the dockcross directory
    echo ""
    log "Contents of dockcross directory:"
    ls -la "${DOCKCROSS_DIR}/" 2>/dev/null || echo "  Directory is empty"
}

# Run main function
main "$@"