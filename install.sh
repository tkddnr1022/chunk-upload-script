#!/bin/bash

# 업로드 테스트 도구 설치 스크립트
# 리눅스 시스템에서 필요한 도구들을 자동으로 설치합니다.

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# OS 감지
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        OS=SuSE
    elif [ -f /etc/redhat-release ]; then
        OS=RedHat
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    echo "$OS" | tr '[:upper:]' '[:lower:]'
}

# 패키지 매니저 감지
detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# 도구 설치
install_tools() {
    local pkg_manager=$1
    
    log_info "패키지 매니저: $pkg_manager"
    
    case $pkg_manager in
        apt)
            log_info "Ubuntu/Debian 패키지 업데이트 중..."
            sudo apt-get update
            
            log_info "필수 도구 설치 중..."
            sudo apt-get install -y curl jq bc
            ;;
        yum)
            log_info "CentOS/RHEL 패키지 업데이트 중..."
            sudo yum update -y
            
            log_info "필수 도구 설치 중..."
            sudo yum install -y curl jq bc
            ;;
        dnf)
            log_info "Fedora 패키지 업데이트 중..."
            sudo dnf update -y
            
            log_info "필수 도구 설치 중..."
            sudo dnf install -y curl jq bc
            ;;
        zypper)
            log_info "openSUSE 패키지 업데이트 중..."
            sudo zypper refresh
            
            log_info "필수 도구 설치 중..."
            sudo zypper install -y curl jq bc
            ;;
        pacman)
            log_info "Arch Linux 패키지 업데이트 중..."
            sudo pacman -Sy
            
            log_info "필수 도구 설치 중..."
            sudo pacman -S --noconfirm curl jq bc
            ;;
        apk)
            log_info "Alpine Linux 패키지 업데이트 중..."
            sudo apk update
            
            log_info "필수 도구 설치 중..."
            sudo apk add curl jq bc
            ;;
        *)
            log_error "지원하지 않는 패키지 매니저입니다: $pkg_manager"
            log_info "수동으로 다음 도구들을 설치해주세요:"
            echo "  - curl"
            echo "  - jq"
            echo "  - bc"
            return 1
            ;;
    esac
}

# 도구 확인
check_tools() {
    local missing_tools=()
    
    for tool in curl jq awk sed date stat bc; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "모든 필수 도구가 설치되어 있습니다!"
        return 0
    else
        log_warning "다음 도구들이 설치되지 않았습니다: ${missing_tools[*]}"
        return 1
    fi
}

# 실행 권한 설정
set_permissions() {
    if [ -f "upload-test.sh" ]; then
        chmod +x upload-test.sh
        log_success "upload-test.sh 실행 권한이 설정되었습니다."
    else
        log_warning "upload-test.sh 파일을 찾을 수 없습니다."
    fi
}

# 테스트 실행
test_installation() {
    log_info "설치 테스트 중..."
    
    # jq 테스트
    if echo '{"test": "value"}' | jq . >/dev/null 2>&1; then
        log_success "jq 테스트 통과"
    else
        log_error "jq 테스트 실패"
        return 1
    fi
    
    # bc 테스트
    if echo "2 + 2" | bc | grep -q "4"; then
        log_success "bc 테스트 통과"
    else
        log_error "bc 테스트 실패"
        return 1
    fi
    
    # curl 테스트
    if curl --version >/dev/null 2>&1; then
        log_success "curl 테스트 통과"
    else
        log_error "curl 테스트 실패"
        return 1
    fi
    
    log_success "모든 테스트가 통과했습니다!"
}

# 메인 함수
main() {
    log_info "업로드 테스트 도구 설치 시작..."
    
    # OS 감지
    local os=$(detect_os)
    log_info "감지된 OS: $os"
    
    # 패키지 매니저 감지
    local pkg_manager=$(detect_package_manager)
    
    if [ "$pkg_manager" = "unknown" ]; then
        log_error "지원하지 않는 패키지 매니저입니다."
        log_info "수동으로 다음 도구들을 설치해주세요:"
        echo "  - curl"
        echo "  - jq"
        echo "  - bc"
        exit 1
    fi
    
    # 도구 설치
    install_tools "$pkg_manager"
    
    # 도구 확인
    if check_tools; then
        # 실행 권한 설정
        set_permissions
        
        # 설치 테스트
        test_installation
        
        echo ""
        log_success "설치가 완료되었습니다!"
        echo ""
        log_info "사용법:"
        echo "  ./upload-test.sh                    # 대화형 모드"
        echo "  ./upload-test.sh file1.zip file2.zip  # 직접 테스트 실행"
        echo "  ./upload-test.sh --help             # 도움말"
        echo ""
    else
        log_error "일부 도구 설치에 실패했습니다."
        exit 1
    fi
}

# 스크립트 실행
main "$@" 