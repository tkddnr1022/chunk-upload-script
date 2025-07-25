#!/bin/bash

# 업로드 테스트 도구 사용 예시
# 이 스크립트는 업로드 테스트 도구의 다양한 사용법을 보여줍니다.

set -e

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 테스트 파일 생성
create_test_files() {
    log_info "테스트 파일 생성 중..."
    
    # 작은 파일 (1MB)
    dd if=/dev/zero of=small-test.zip bs=1M count=1 2>/dev/null
    log_success "small-test.zip (1MB) 생성 완료"
    
    # 중간 파일 (10MB)
    dd if=/dev/zero of=medium-test.zip bs=1M count=10 2>/dev/null
    log_success "medium-test.zip (10MB) 생성 완료"
    
    # 큰 파일 (50MB)
    dd if=/dev/zero of=large-test.zip bs=1M count=50 2>/dev/null
    log_success "large-test.zip (50MB) 생성 완료"
}

# 설정 예시
show_config_examples() {
    log_info "설정 예시:"
    echo ""
    echo "1. 기본 설정 (로컬 서버):"
    cat << 'EOF'
{
  "apiOrigin": "http://localhost:3000",
  "testCount": 3,
  "parallelCount": 4,
  "chunkSize": 10,
  "jwtToken": "",
  "requestIdPath": "/api/request-id",
  "requestIdBody": {
    "language": "KO",
    "target_language": ["EN", "JP"],
    "dir_name": "",
    "ext": ""
  },
  "paths": {
    "singleUploadPath": "/upload",
    "uploadChunkPath": "/upload-chunk",
    "mergeChunksPath": "/merge-chunks"
  },
  "customFields": [{"key": "user_id", "value": "test_user"}],
  "customHeaders": [{"key": "X-API-Version", "value": "v1"}]
}
EOF
    echo ""
    echo "2. 프로덕션 설정:"
    cat << 'EOF'
{
  "apiOrigin": "https://api.example.com",
  "testCount": 5,
  "parallelCount": 8,
  "chunkSize": 5,
  "jwtToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "requestIdPath": "/api/v1/request-id",
  "requestIdBody": {
    "language": "KO",
    "target_language": ["EN", "JP", "CN"],
    "dir_name": "",
    "ext": ""
  },
  "paths": {
    "singleUploadPath": "/api/v1/upload",
    "uploadChunkPath": "/api/v1/upload-chunk",
    "mergeChunksPath": "/api/v1/merge-chunks"
  },
  "customFields": [
    {"key": "project_id", "value": "proj_123"},
    {"key": "environment", "value": "production"}
  ],
  "customHeaders": [
    {"key": "X-API-Version", "value": "v1"},
    {"key": "X-Client-ID", "value": "test_client"}
  ]
}
EOF
}

# 사용 예시
show_usage_examples() {
    log_info "사용 예시:"
    echo ""
    echo "1. 대화형 모드로 실행:"
    echo "   ./upload-test.sh"
    echo ""
    echo "2. 직접 파일 지정하여 테스트:"
    echo "   ./upload-test.sh small-test.zip large-test.zip"
    echo ""
    echo "3. 도움말 보기:"
    echo "   ./upload-test.sh --help"
    echo ""
    echo "4. 설정 파일 수정:"
    echo "   # config.json 파일을 직접 편집하거나"
    echo "   # 대화형 모드에서 '설정 수정' 선택"
    echo ""
    echo "5. 측정 기록 확인:"
    echo "   # 대화형 모드에서 '측정 기록 보기' 선택"
    echo ""
    echo "6. 배치 테스트 (여러 파일):"
    echo "   for file in *.zip; do"
    echo "     echo \"Testing \$file...\""
    echo "     ./upload-test.sh \$file \$file"
    echo "   done"
}

# 성능 최적화 팁
show_performance_tips() {
    log_info "성능 최적화 팁:"
    echo ""
    echo "1. 청크 크기 조정:"
    echo "   - 네트워크가 빠른 경우: 10-20MB"
    echo "   - 네트워크가 느린 경우: 1-5MB"
    echo "   - 불안정한 네트워크: 1MB 이하"
    echo ""
    echo "2. 병렬 업로드 개수:"
    echo "   - CPU 코어 수에 따라 조정"
    echo "   - 일반적으로 4-8개가 적당"
    echo "   - 너무 많으면 오히려 성능 저하 가능"
    echo ""
    echo "3. 테스트 횟수:"
    echo "   - 정확한 측정을 위해 3-5회 권장"
    echo "   - 네트워크 변동이 큰 경우 더 많이"
    echo ""
    echo "4. 서버 설정 확인:"
    echo "   - 최대 업로드 크기 제한"
    echo "   - 타임아웃 설정"
    echo "   - 동시 연결 수 제한"
}

# 문제 해결
show_troubleshooting() {
    log_info "문제 해결:"
    echo ""
    echo "1. 연결 오류:"
    echo "   curl -I http://localhost:3000"
    echo "   # 서버가 실행 중인지 확인"
    echo ""
    echo "2. 권한 오류:"
    echo "   chmod +x upload-test.sh"
    echo "   # 실행 권한 확인"
    echo ""
    echo "3. JSON 파싱 오류:"
    echo "   echo '{\"test\": \"value\"}' | jq ."
    echo "   # jq 설치 확인"
    echo ""
    echo "4. 메모리 부족:"
    echo "   # 청크 크기를 줄이거나"
    echo "   # 병렬 개수를 줄임"
    echo ""
    echo "5. 네트워크 타임아웃:"
    echo "   # 청크 크기 줄이기"
    echo "   # 병렬 개수 줄이기"
    echo "   # 서버 타임아웃 설정 확인"
}

# 메인 함수
main() {
    echo "=========================================="
    echo "업로드 테스트 도구 사용 예시"
    echo "=========================================="
    echo ""
    
    # 테스트 파일 생성 여부 확인
    read -p "테스트 파일을 생성하시겠습니까? (y/n): " create_files
    
    if [ "$create_files" = "y" ] || [ "$create_files" = "Y" ]; then
        create_test_files
        echo ""
    fi
    
    # 각 섹션 표시
    show_config_examples
    echo ""
    show_usage_examples
    echo ""
    show_performance_tips
    echo ""
    show_troubleshooting
    echo ""
    
    log_success "예시 스크립트 완료!"
    echo ""
    echo "다음 단계:"
    echo "1. ./install.sh 실행 (필요한 도구 설치)"
    echo "2. ./upload-test.sh 실행 (대화형 모드)"
    echo "3. config.json 파일 수정 (필요시)"
    echo "4. 테스트 실행"
}

# 스크립트 실행
main "$@" 