# 업로드 테스트 CLI 도구

App.js의 기능을 리눅스에서 실행 가능한 CLI 스크립트로 변환한 도구입니다.

## 기능

- 단일 파일 업로드 성능 테스트
- 청크 단위 업로드 성능 테스트
- 병렬 업로드 지원
- Request ID 발급 및 추적
- JWT 토큰 인증 지원
- 커스텀 헤더 및 FormData 필드 지원
- 측정 기록 저장 및 조회
- 대화형 설정 관리

## 설치

1. 의존성 설치:
```bash
npm install
```

2. 실행 권한 부여 (리눅스/맥):
```bash
chmod +x upload-test.js
```

## 사용법

### 1. 대화형 모드
```bash
node upload-test.js
```

### 2. 직접 테스트 실행
```bash
node upload-test.js <단일업로드파일경로> <청크업로드파일경로>
```

### 3. 도움말
```bash
node upload-test.js --help
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
  "customFields": [
    {
      "key": "",
      "value": ""
    }
  ],
  "customHeaders": [
    {
      "key": "",
      "value": ""
    }
  ]
}
```

### 설정 항목 설명

- `apiOrigin`: API 서버 주소
- `testCount`: 테스트 실행 횟수
- `parallelCount`: 병렬 업로드 개수
- `chunkSize`: 청크 크기 (MB)
- `jwtToken`: JWT 인증 토큰
- `requestIdPath`: Request ID 발급 엔드포인트
- `requestIdBody`: Request ID 발급 시 전송할 데이터
- `paths`: 각종 API 엔드포인트 경로
- `customFields`: 커스텀 FormData 필드
- `customHeaders`: 커스텀 HTTP 헤더

## 대화형 메뉴

1. **설정 보기**: 현재 설정을 확인
2. **설정 수정**: 설정을 대화형으로 수정
3. **테스트 실행**: 파일 경로를 입력하여 테스트 실행
4. **측정 기록 보기**: 이전 테스트 결과 조회
5. **측정 기록 지우기**: 테스트 기록 삭제
6. **종료**: 프로그램 종료

## 출력 예시

```
🚀 업로드 테스트 시작...

📤 단일 업로드 테스트 시작...
테스트 1 - 단일 업로드 성공 (2.34s)

📤 청크 업로드 테스트 시작...
파일 크기: 50.25 MB
청크 크기: 10 MB (10,485,760 bytes)
예상 청크 수: 5개
병렬 업로드: 4개
테스트 1 - 청크 1/5 완료 (20%)
테스트 1 - 청크 2/5 완료 (40%)
테스트 1 - 청크 3/5 완료 (60%)
테스트 1 - 청크 4/5 완료 (80%)
테스트 1 - 청크 5/5 완료 (100%)
청크 병합 성공
테스트 1 - 청크 업로드 및 병합 성공 (1.87s)

📊 테스트 결과:
==================================================
단일 업로드 평균 시간: 2.34s
단일 업로드 평균 속도: 21.47 MB/s
청크 업로드 평균 시간: 1.87s
청크 업로드 평균 속도: 26.87 MB/s

✅ 테스트 완료!
```

## 파일 구조

```
.
├── upload-test.js          # 메인 스크립트
├── config.json            # 설정 파일
├── package.json           # 의존성 정보
├── README.md              # 사용법 설명
└── upload-history.json    # 테스트 기록 (자동 생성)
```

## 요구사항

- Node.js 14.0.0 이상
- npm 또는 yarn

## 라이선스

MIT License 