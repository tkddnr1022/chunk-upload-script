#!/bin/bash

# 업로드 테스트 도구 (리눅스 네이티브 버전)
# 필요한 도구: curl, jq, awk, sed, date, stat, bc

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설정
CONFIG_FILE="$(dirname "$0")/config.json"
HISTORY_FILE="$(dirname "$0")/upload-history.json"

# 기본 설정값
DEFAULT_CONFIG='{
  "apiOrigin": "http://localhost:3000",
  "testCount": 1,
  "parallelCount": 4,
  "chunkSize": 10,
  "jwtToken": "",
  "requestIdPath": "",
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
  "customFields": [{"key": "", "value": ""}],
  "customHeaders": [{"key": "", "value": ""}]
}'

# 유틸리티 함수들
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

# 필수 도구 확인
check_dependencies() {
    local missing_tools=()
    
    for tool in curl jq awk sed date stat bc; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "다음 도구들이 설치되지 않았습니다: ${missing_tools[*]}"
        log_info "설치 명령어:"
        echo "  Ubuntu/Debian: sudo apt-get install curl jq"
        echo "  CentOS/RHEL: sudo yum install curl jq"
        echo "  Alpine: apk add curl jq"
        exit 1
    fi
}

# 설정 파일 로드
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo "$DEFAULT_CONFIG"
    fi
}

# 설정 파일 저장
save_config() {
    echo "$1" > "$CONFIG_FILE"
}

# 히스토리 로드
load_history() {
    if [ -f "$HISTORY_FILE" ]; then
        cat "$HISTORY_FILE"
    else
        echo "[]"
    fi
}

# 히스토리 저장
save_history() {
    echo "$1" > "$HISTORY_FILE"
}

# MB를 바이트로 변환
mb_to_bytes() {
    echo "$1 * 1024 * 1024" | bc
}

# 바이트를 MB로 변환
bytes_to_mb() {
    echo "scale=2; $1 / 1024 / 1024" | bc
}

# 속도 포맷팅
format_speed() {
    local bytes_per_sec=$1
    
    if [ "$bytes_per_sec" -eq 0 ]; then
        echo "-"
        return
    fi
    
    local mb_per_sec
    local mbps
    
    if [ "$bytes_per_sec" -ge 1048576 ]; then
        mb_per_sec=$(echo "scale=2; $bytes_per_sec / 1048576" | bc)
        mbps=$(echo "scale=2; $bytes_per_sec * 8 / 1048576" | bc)
        echo "${mb_per_sec} MB/s (${mbps} Mbps)"
    elif [ "$bytes_per_sec" -ge 1024 ]; then
        local kb_per_sec=$(echo "scale=2; $bytes_per_sec / 1024" | bc)
        local kbps=$(echo "scale=2; $bytes_per_sec * 8 / 1024" | bc)
        echo "${kb_per_sec} KB/s (${kbps} Kbps)"
    else
        local bps=$(echo "$bytes_per_sec * 8" | bc)
        echo "${bytes_per_sec} B/s (${bps} bps)"
    fi
}

# Request ID 발급
request_id() {
    local config=$(load_config)
    local request_id_path=$(echo "$config" | jq -r '.requestIdPath')
    local api_origin=$(echo "$config" | jq -r '.apiOrigin')
    local jwt_token=$(echo "$config" | jq -r '.jwtToken')
    local request_id_body="$1"
    local test_index="$2"
    
    if [ "$request_id_path" = "null" ] || [ -z "$request_id_path" ]; then
        return
    fi
    
    local headers="Content-Type: application/json"
    if [ "$jwt_token" != "null" ] && [ -n "$jwt_token" ]; then
        headers="$headers\nAuthorization: Bearer $jwt_token"
    fi
    
    # 커스텀 헤더 추가
    local custom_headers=$(echo "$config" | jq -r '.customHeaders[] | select(.key != null and .key != "") | "\(.key): \(.value)"' 2>/dev/null || true)
    if [ -n "$custom_headers" ]; then
        headers="$headers\n$custom_headers"
    fi
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "$headers" \
        -d "$request_id_body" \
        "${api_origin%/}$request_id_path" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ]; then
        local request_id=$(echo "$body" | jq -r '.data.request_id // empty')
        if [ -n "$request_id" ]; then
            log_info "테스트 $((test_index + 1)) 발급된 Request ID: $request_id"
            echo "$request_id"
        fi
    else
        log_error "테스트 $((test_index + 1)) Request ID 발급 실패: $http_code"
    fi
}

# 단일 업로드
single_upload() {
    local file_path="$1"
    local request_id="$2"
    local test_index="$3"
    local config=$(load_config)
    local api_origin=$(echo "$config" | jq -r '.apiOrigin')
    local single_upload_path=$(echo "$config" | jq -r '.paths.singleUploadPath')
    local jwt_token=$(echo "$config" | jq -r '.jwtToken')
    
    local headers=""
    if [ "$jwt_token" != "null" ] && [ -n "$jwt_token" ]; then
        headers="-H \"Authorization: Bearer $jwt_token\""
    fi
    
    if [ -n "$request_id" ]; then
        headers="$headers -H \"x-request-id: $request_id\""
    fi
    
    # 커스텀 헤더 추가
    local custom_headers=$(echo "$config" | jq -r '.customHeaders[] | select(.key != null and .key != "") | "-H \"\(.key): \(.value)\""' 2>/dev/null || true)
    if [ -n "$custom_headers" ]; then
        headers="$headers $custom_headers"
    fi
    
    # 커스텀 필드 추가
    local custom_fields=""
    local custom_fields_json=$(echo "$config" | jq -r '.customFields[] | select(.key != null and .key != "") | "\(.key)=\(.value)"' 2>/dev/null || true)
    if [ -n "$custom_fields_json" ]; then
        custom_fields=$(echo "$custom_fields_json" | sed 's/^/-F "/; s/$/"/')
    fi
    
    local start_time=$(date +%s%3N)
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        $headers \
        $custom_fields \
        -F "file=@$file_path" \
        "${api_origin%/}$single_upload_path" 2>/dev/null)
    
    local end_time=$(date +%s%3N)
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    local elapsed=$((end_time - start_time))
    
    if [ "$http_code" = "200" ]; then
        log_success "테스트 $((test_index + 1)) - 단일 업로드 성공 ($(echo "scale=2; $elapsed / 1000" | bc)s)"
        echo "$elapsed"
    else
        log_error "테스트 $((test_index + 1)) 단일 업로드 실패: $http_code"
        return 1
    fi
}

# 청크 업로드
upload_chunk() {
    local file_path="$1"
    local chunk_size="$2"
    local chunk_index="$3"
    local total_chunks="$4"
    local request_id="$5"
    local config=$(load_config)
    local api_origin=$(echo "$config" | jq -r '.apiOrigin')
    local upload_chunk_path=$(echo "$config" | jq -r '.paths.uploadChunkPath')
    local jwt_token=$(echo "$config" | jq -r '.jwtToken')
    
    local start=$((chunk_index * chunk_size))
    local end=$((start + chunk_size - 1))
    local file_size=$(stat -c%s "$file_path")
    
    if [ $end -ge $file_size ]; then
        end=$((file_size - 1))
    fi
    
    # 임시 청크 파일 생성
    local temp_chunk="/tmp/chunk_${chunk_index}_$$"
    dd if="$file_path" of="$temp_chunk" bs=1 skip="$start" count=$((end - start + 1)) 2>/dev/null
    
    local headers=""
    if [ "$jwt_token" != "null" ] && [ -n "$jwt_token" ]; then
        headers="-H \"Authorization: Bearer $jwt_token\""
    fi
    
    if [ -n "$request_id" ]; then
        headers="$headers -H \"x-request-id: $request_id\""
    fi
    
    headers="$headers -H \"x-chunk-index: $chunk_index\" -H \"x-chunk-total: $total_chunks\""
    
    # 커스텀 헤더 추가
    local custom_headers=$(echo "$config" | jq -r '.customHeaders[] | select(.key != null and .key != "") | "-H \"\(.key): \(.value)\""' 2>/dev/null || true)
    if [ -n "$custom_headers" ]; then
        headers="$headers $custom_headers"
    fi
    
    # 커스텀 필드 추가
    local custom_fields=""
    local custom_fields_json=$(echo "$config" | jq -r '.customFields[] | select(.key != null and .key != "") | "\(.key)=\(.value)"' 2>/dev/null || true)
    if [ -n "$custom_fields_json" ]; then
        custom_fields=$(echo "$custom_fields_json" | sed 's/^/-F "/; s/$/"/')
    fi
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        $headers \
        $custom_fields \
        -F "file=@$temp_chunk" \
        "${api_origin%/}$upload_chunk_path" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    # 임시 파일 삭제
    rm -f "$temp_chunk"
    
    if [ "$http_code" = "200" ]; then
        echo "success"
    else
        log_error "청크 $chunk_index 업로드 실패: $http_code"
        return 1
    fi
}

# 병렬 청크 업로드
parallel_chunk_upload() {
    local file_path="$1"
    local chunk_size="$2"
    local file_id="$3"
    local total_chunks="$4"
    local request_id="$5"
    local test_index="$6"
    local config=$(load_config)
    local parallel_count=$(echo "$config" | jq -r '.parallelCount')
    
    local start_time=$(date +%s%3N)
    local uploaded_chunks=0
    local failed=false
    
    # 병렬 업로드를 위한 함수
    upload_chunk_wrapper() {
        local chunk_index="$1"
        if upload_chunk "$file_path" "$chunk_size" "$chunk_index" "$total_chunks" "$request_id"; then
            echo "success"
        else
            echo "failed"
        fi
    }
    
    # 병렬 업로드 실행
    local pids=()
    local results=()
    
    for ((i=0; i<total_chunks; i++)); do
        # 병렬 개수 제한
        while [ ${#pids[@]} -ge $parallel_count ]; do
            for j in "${!pids[@]}"; do
                if ! kill -0 "${pids[j]}" 2>/dev/null; then
                    wait "${pids[j]}"
                    local result=$?
                    if [ $result -eq 0 ]; then
                        uploaded_chunks=$((uploaded_chunks + 1))
                        local percent=$((uploaded_chunks * 100 / total_chunks))
                        log_info "테스트 $((test_index + 1)) - 청크 $uploaded_chunks/$total_chunks 완료 ($percent%)"
                    else
                        failed=true
                    fi
                    unset pids[j]
                    break
                fi
            done
            sleep 0.1
        done
        
        # 새 청크 업로드 시작
        upload_chunk_wrapper "$i" &
        pids+=($!)
    done
    
    # 남은 프로세스들 대기
    for pid in "${pids[@]}"; do
        wait "$pid"
        local result=$?
        if [ $result -eq 0 ]; then
            uploaded_chunks=$((uploaded_chunks + 1))
        else
            failed=true
        fi
    done
    
    local end_time=$(date +%s%3N)
    local elapsed=$((end_time - start_time))
    
    if [ "$failed" = true ]; then
        log_error "청크 업로드 실패"
        return 1
    fi
    
    echo "$elapsed"
}

# 청크 병합
merge_chunks() {
    local file_id="$1"
    local filename="$2"
    local total_chunks="$3"
    local request_id="$4"
    local config=$(load_config)
    local api_origin=$(echo "$config" | jq -r '.apiOrigin')
    local merge_chunks_path=$(echo "$config" | jq -r '.paths.mergeChunksPath')
    local jwt_token=$(echo "$config" | jq -r '.jwtToken')
    
    local headers="Content-Type: application/json"
    if [ "$jwt_token" != "null" ] && [ -n "$jwt_token" ]; then
        headers="$headers\nAuthorization: Bearer $jwt_token"
    fi
    
    if [ -n "$request_id" ]; then
        headers="$headers\nx-request-id: $request_id"
    fi
    
    headers="$headers\nx-chunk-total: $total_chunks"
    
    # 커스텀 헤더 추가
    local custom_headers=$(echo "$config" | jq -r '.customHeaders[] | select(.key != null and .key != "") | "\(.key): \(.value)"' 2>/dev/null || true)
    if [ -n "$custom_headers" ]; then
        headers="$headers\n$custom_headers"
    fi
    
    # 커스텀 필드 추가
    local custom_fields_json=$(echo "$config" | jq -r '.customFields[] | select(.key != null and .key != "") | "\(.key): \"\(.value)\""' 2>/dev/null || true)
    local merge_body="{\"fileId\": \"$file_id\", \"filename\": \"$filename\", \"totalChunks\": $total_chunks"
    if [ -n "$custom_fields_json" ]; then
        merge_body="$merge_body, $(echo "$custom_fields_json" | sed 's/^/, /')"
    fi
    merge_body="$merge_body}"
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "$headers" \
        -d "$merge_body" \
        "${api_origin%/}$merge_chunks_path" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ]; then
        log_success "청크 병합 성공"
        return 0
    else
        log_error "병합 실패: $http_code"
        return 1
    fi
}

# 배치 테스트 실행
run_batch_test() {
    local single_file_path="$1"
    local chunk_file_path="$2"
    
    log_info "업로드 테스트 시작..."
    
    # 파일 존재 확인
    if [ ! -f "$single_file_path" ]; then
        log_error "단일 업로드 파일을 찾을 수 없습니다: $single_file_path"
        return 1
    fi
    
    if [ ! -f "$chunk_file_path" ]; then
        log_error "청크 업로드 파일을 찾을 수 없습니다: $chunk_file_path"
        return 1
    fi
    
    local config=$(load_config)
    local test_count=$(echo "$config" | jq -r '.testCount')
    local chunk_size_mb=$(echo "$config" | jq -r '.chunkSize')
    local chunk_size_bytes=$(mb_to_bytes "$chunk_size_mb")
    
    local single_file_size=$(stat -c%s "$single_file_path")
    local chunk_file_size=$(stat -c%s "$chunk_file_path")
    local total_chunks=$(( (chunk_file_size + chunk_size_bytes - 1) / chunk_size_bytes ))
    
    # Request ID Body 설정
    local filename=$(basename "$chunk_file_path")
    local ext="${filename##*.}"
    local dir_name="${filename%.*}"
    
    local request_id_body=$(echo "$config" | jq --arg dir_name "$dir_name" --arg ext "$ext" \
        '.requestIdBody | .dir_name = $dir_name | .ext = $ext')
    
    # Request ID 발급
    local request_ids=()
    if [ "$(echo "$config" | jq -r '.requestIdPath')" != "null" ] && [ -n "$(echo "$config" | jq -r '.requestIdPath')" ]; then
        log_info "Request ID 발급 중..."
        for ((i=0; i<test_count; i++)); do
            local request_id=$(request_id "$request_id_body" "$i")
            request_ids+=("$request_id")
        done
    else
        for ((i=0; i<test_count; i++)); do
            request_ids+=("")
        done
    fi
    
    # 단일 업로드 테스트
    local single_times=()
    if [ -f "$single_file_path" ]; then
        log_info "단일 업로드 테스트 시작..."
        for ((i=0; i<test_count; i++)); do
            local elapsed=$(single_upload "$single_file_path" "${request_ids[i]}" "$i")
            if [ $? -eq 0 ]; then
                single_times+=("$elapsed")
            fi
        done
    fi
    
    # 청크 업로드 테스트
    local chunk_times=()
    if [ -f "$chunk_file_path" ]; then
        log_info "청크 업로드 테스트 시작..."
        log_info "파일 크기: $(bytes_to_mb "$chunk_file_size") MB"
        log_info "청크 크기: ${chunk_size_mb} MB ($(echo "$chunk_size_bytes" | sed 's/\([0-9]\{1,3\}\)/\1,/g' | sed 's/,$//') bytes)"
        log_info "예상 청크 수: ${total_chunks}개"
        log_info "병렬 업로드: $(echo "$config" | jq -r '.parallelCount')개"
        
        for ((t=0; t<test_count; t++)); do
            local file_id="${filename}-${chunk_file_size}-$(stat -c%Y "$chunk_file_path")-$(date +%s%3N)-${t}"
            local elapsed=$(parallel_chunk_upload "$chunk_file_path" "$chunk_size_bytes" "$file_id" "$total_chunks" "${request_ids[t]}" "$t")
            
            if [ $? -eq 0 ]; then
                if merge_chunks "$file_id" "$filename" "$total_chunks" "${request_ids[t]}"; then
                    log_success "테스트 $((t + 1)) - 청크 업로드 및 병합 성공 ($(echo "scale=2; $elapsed / 1000" | bc)s)"
                    chunk_times+=("$elapsed")
                fi
            fi
        done
    fi
    
    # 결과 출력
    echo ""
    log_info "테스트 결과:"
    echo "=================================================="
    
    if [ ${#single_times[@]} -gt 0 ]; then
        local total_single=0
        for time in "${single_times[@]}"; do
            total_single=$((total_single + time))
        done
        local avg_single=$((total_single / ${#single_times[@]}))
        local avg_single_speed=$((single_file_size * 1000 / avg_single))
        echo "단일 업로드 평균 시간: $(echo "scale=2; $avg_single / 1000" | bc)s"
        echo "단일 업로드 평균 속도: $(format_speed "$avg_single_speed")"
    fi
    
    if [ ${#chunk_times[@]} -gt 0 ]; then
        local total_chunk=0
        for time in "${chunk_times[@]}"; do
            total_chunk=$((total_chunk + time))
        done
        local avg_chunk=$((total_chunk / ${#chunk_times[@]}))
        local avg_chunk_speed=$((chunk_file_size * 1000 / avg_chunk))
        echo "청크 업로드 평균 시간: $(echo "scale=2; $avg_chunk / 1000" | bc)s"
        echo "청크 업로드 평균 속도: $(format_speed "$avg_chunk_speed")"
    fi
    
    # 기록 저장
    local history=$(load_history)
    local record=$(jq -n \
        --arg date "$(date '+%Y-%m-%d %H:%M:%S')" \
        --arg count "$test_count" \
        --arg avg_single "${single_times[0]:-null}" \
        --arg avg_chunk "${chunk_times[0]:-null}" \
        --arg avg_single_speed "$([ ${#single_times[@]} -gt 0 ] && echo $((single_file_size * 1000 / (total_single / ${#single_times[@]}))) || echo null)" \
        --arg avg_chunk_speed "$([ ${#chunk_times[@]} -gt 0 ] && echo $((chunk_file_size * 1000 / (total_chunk / ${#chunk_times[@]}))) || echo null)" \
        --arg request_ids "$(printf '%s' "${request_ids[@]}" | tr ' ' ',')" \
        --arg chunk_size "$chunk_size_bytes" \
        --arg single_filename "$(basename "$single_file_path")" \
        --arg chunk_filename "$(basename "$chunk_file_path")" \
        --arg single_file_size "$single_file_size" \
        --arg chunk_file_size "$chunk_file_size" \
        '{
            date: $date,
            count: ($count | tonumber),
            avgSingle: ($avg_single | tonumber?),
            avgChunk: ($avg_chunk | tonumber?),
            avgSingleSpeed: ($avg_single_speed | tonumber?),
            avgChunkSpeed: ($avg_chunk_speed | tonumber?),
            requestIds: ($request_ids | split(",") | map(select(. != ""))),
            chunkSize: ($chunk_size | tonumber),
            singleFileName: $single_filename,
            chunkFileName: $chunk_filename,
            singleFileSize: ($single_file_size | tonumber),
            chunkFileSize: ($chunk_file_size | tonumber)
        }')
    
    local new_history=$(echo "$history" | jq --argjson record "$record" '[$record] + .[0:49]')
    save_history "$new_history"
    
    log_success "테스트 완료!"
}

# 히스토리 보기
show_history() {
    local history=$(load_history)
    
    echo ""
    log_info "측정 기록:"
    echo "================================================================================="
    
    if [ "$(echo "$history" | jq 'length')" -eq 0 ]; then
        echo "측정 기록이 없습니다."
        return
    fi
    
    echo "날짜\t\t\t\t청크 파일 크기\t\t응답 평균(s)\tRequest ID"
    echo "---------------------------------------------------------------------------------"
    
    echo "$history" | jq -r '.[0:10][] | "\(.date)\t\(.chunkFileSize | . / 1024 / 1024 | floor)MB\t\t\t\(.avgChunk // "-" | if type == "number" then (. / 1000 | floor) else . end)\t\t\(.requestIds // "-" | join(", "))"'
}

# 히스토리 지우기
clear_history() {
    save_history "[]"
    log_success "측정 기록이 지워졌습니다."
}

# 설정 보기
show_config() {
    local config=$(load_config)
    echo ""
    log_info "현재 설정:"
    echo "=================================================="
    echo "$config" | jq '.'
}

# 설정 수정
edit_config() {
    local config=$(load_config)
    
    echo ""
    log_info "설정 수정:"
    echo "================================"
    echo "1. API 서버 Origin"
    echo "2. 테스트 횟수"
    echo "3. 병렬 업로드 개수"
    echo "4. 청크 크기 (MB)"
    echo "5. JWT 토큰"
    echo "6. Request ID 발급 Path"
    echo "7. 뒤로 가기"
    
    read -p "수정할 항목을 선택하세요 (1-7): " choice
    
    case $choice in
        1)
            read -p "API 서버 Origin: " api_origin
            config=$(echo "$config" | jq --arg origin "$api_origin" '.apiOrigin = $origin')
            ;;
        2)
            read -p "테스트 횟수: " test_count
            config=$(echo "$config" | jq --arg count "$test_count" '.testCount = ($count | tonumber)')
            ;;
        3)
            read -p "병렬 업로드 개수: " parallel_count
            config=$(echo "$config" | jq --arg count "$parallel_count" '.parallelCount = ($count | tonumber)')
            ;;
        4)
            read -p "청크 크기 (MB): " chunk_size
            config=$(echo "$config" | jq --arg size "$chunk_size" '.chunkSize = ($size | tonumber)')
            ;;
        5)
            read -p "JWT 토큰: " jwt_token
            config=$(echo "$config" | jq --arg token "$jwt_token" '.jwtToken = $token')
            ;;
        6)
            read -p "Request ID 발급 Path: " request_id_path
            config=$(echo "$config" | jq --arg path "$request_id_path" '.requestIdPath = $path')
            ;;
        7)
            return
            ;;
        *)
            log_error "잘못된 선택입니다."
            return
            ;;
    esac
    
    save_config "$config"
    log_success "설정이 저장되었습니다."
}

# 대화형 메뉴
interactive_menu() {
    while true; do
        echo ""
        log_info "업로드 테스트 도구"
        echo "================================"
        echo "1. 설정 보기"
        echo "2. 설정 수정"
        echo "3. 테스트 실행"
        echo "4. 측정 기록 보기"
        echo "5. 측정 기록 지우기"
        echo "6. 종료"
        echo "================================"
        
        read -p "선택하세요 (1-6): " choice
        
        case $choice in
            1)
                show_config
                ;;
            2)
                edit_config
                ;;
            3)
                read -p "단일 업로드 파일 경로: " single_file
                read -p "청크 업로드 파일 경로: " chunk_file
                run_batch_test "$single_file" "$chunk_file"
                ;;
            4)
                show_history
                ;;
            5)
                clear_history
                ;;
            6)
                log_info "프로그램을 종료합니다."
                exit 0
                ;;
            *)
                log_error "잘못된 선택입니다."
                ;;
        esac
    done
}

# 도움말 출력
show_help() {
    echo "업로드 테스트 도구 (리눅스 네이티브 버전)

사용법:
  $0                    # 대화형 모드
  $0 <single_file> <chunk_file>  # 직접 테스트 실행
  $0 --help             # 도움말

옵션:
  --help, -h     도움말 표시

필수 도구:
  curl, jq, awk, sed, date, stat, bc

설정:
  config.json 파일에서 테스트 설정을 수정할 수 있습니다.
"
}

# 메인 실행
main() {
    check_dependencies
    
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            interactive_menu
            ;;
        *)
            if [ $# -eq 2 ]; then
                run_batch_test "$1" "$2"
            else
                log_error "잘못된 인수입니다. --help를 참조하세요."
                exit 1
            fi
            ;;
    esac
}

# 스크립트 실행
main "$@" 