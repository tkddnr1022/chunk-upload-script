# 업로드 테스트 도구 (리눅스 네이티브 버전)

Node.js 없이 리눅스 기본 기능만으로 동작하는 업로드 테스트 스크립트입니다.

## 필수 도구

다음 도구들이 시스템에 설치되어 있어야 합니다:

- `curl` - HTTP 요청 전송
- `jq` - JSON 처리
- `awk` - 텍스트 처리
- `sed` - 텍스트 편집
- `date` - 날짜/시간 처리
- `stat` - 파일 정보 조회
- `bc` - 수학 계산

## 설치

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install curl jq
```

### CentOS/RHEL
```bash
sudo yum install curl jq
```

### Alpine Linux
```bash
apk add curl jq
```

## 실행 권한 설정

```bash
chmod +x upload-test.sh
```

## 사용법

### 대화형 모드
```bash
./upload-test.sh
```

### 직접 테스트 실행
```bash
./upload-test.sh <단일업로드파일> <청크업로드파일>
```

### 도움말
```bash
./upload-test.sh --help
```

## 설정

`config.json` 파일에서 테스트 설정을 수정할 수 있습니다:

```json
{
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
}
```

## 주요 기능

1. **단일 업로드 테스트** - 전체 파일을 한 번에 업로드
2. **청크 업로드 테스트** - 파일을 여러 청크로 나누어 병렬 업로드
3. **병렬 처리** - 설정 가능한 병렬 업로드 개수
4. **Request ID 지원** - API에서 Request ID 발급 및 사용
5. **JWT 인증** - Bearer 토큰 인증 지원
6. **커스텀 헤더/필드** - 추가 헤더 및 폼 필드 설정
7. **측정 기록** - 테스트 결과 히스토리 저장
8. **속도 측정** - MB/s, Mbps 단위로 속도 표시

## 출력 예시

```
[INFO] 업로드 테스트 시작...

[INFO] Request ID 발급 중...
[INFO] 테스트 1 발급된 Request ID: req_123456

[INFO] 단일 업로드 테스트 시작...
[SUCCESS] 테스트 1 - 단일 업로드 성공 (2.45s)

[INFO] 청크 업로드 테스트 시작...
[INFO] 파일 크기: 50.25 MB
[INFO] 청크 크기: 10 MB (10,485,760 bytes)
[INFO] 예상 청크 수: 5개
[INFO] 병렬 업로드: 4개
[INFO] 테스트 1 - 청크 1/5 완료 (20%)
[INFO] 테스트 1 - 청크 2/5 완료 (40%)
[INFO] 테스트 1 - 청크 3/5 완료 (60%)
[INFO] 테스트 1 - 청크 4/5 완료 (80%)
[INFO] 테스트 1 - 청크 5/5 완료 (100%)
[SUCCESS] 청크 병합 성공
[SUCCESS] 테스트 1 - 청크 업로드 및 병합 성공 (1.23s)

[INFO] 테스트 결과:
==================================================
단일 업로드 평균 시간: 2.45s
단일 업로드 평균 속도: 20.51 MB/s (164.08 Mbps)
청크 업로드 평균 시간: 1.23s
청크 업로드 평균 속도: 40.85 MB/s (326.80 Mbps)

[SUCCESS] 테스트 완료!
```

## 주의사항

1. **임시 파일**: 청크 업로드 시 `/tmp/` 디렉토리에 임시 파일이 생성됩니다.
2. **메모리 사용**: 대용량 파일 처리 시 충분한 메모리가 필요합니다.
3. **네트워크**: 안정적인 네트워크 연결이 필요합니다.
4. **권한**: 스크립트 실행 권한이 필요합니다.

## 문제 해결

### 도구가 설치되지 않은 경우
```bash
# Ubuntu/Debian
sudo apt-get install curl jq

# CentOS/RHEL
sudo yum install curl jq

# Alpine
apk add curl jq
```

### 실행 권한 오류
```bash
chmod +x upload-test.sh
```

### JSON 파싱 오류
`jq` 도구가 올바르게 설치되었는지 확인하세요:
```bash
echo '{"test": "value"}' | jq .
```

### 네트워크 연결 오류
API 서버가 실행 중이고 접근 가능한지 확인하세요:
```bash
curl -I http://localhost:3000
``` 