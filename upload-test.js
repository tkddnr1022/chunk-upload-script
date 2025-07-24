#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const FormData = require('form-data');
const fetch = require('node-fetch');
const readline = require('readline');

class UploadTester {
  constructor() {
    this.config = this.loadConfig();
    this.history = this.loadHistory();
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
  }

  loadConfig() {
    try {
      const configPath = path.join(__dirname, 'config.json');
      if (fs.existsSync(configPath)) {
        return JSON.parse(fs.readFileSync(configPath, 'utf8'));
      }
    } catch (error) {
      console.error('설정 파일 로드 실패:', error.message);
    }
    return {
      apiOrigin: "http://localhost:3000",
      testCount: 1,
      parallelCount: 4,
      chunkSize: 10,
      jwtToken: "",
      requestIdPath: "",
      requestIdBody: {
        language: "KO",
        target_language: ["EN", "JP"],
        dir_name: "",
        ext: ""
      },
      paths: {
        singleUploadPath: "/upload",
        uploadChunkPath: "/upload-chunk",
        mergeChunksPath: "/merge-chunks"
      },
      customFields: [{ key: "", value: "" }],
      customHeaders: [{ key: "", value: "" }]
    };
  }

  saveConfig() {
    try {
      fs.writeFileSync(path.join(__dirname, 'config.json'), JSON.stringify(this.config, null, 2));
    } catch (error) {
      console.error('설정 파일 저장 실패:', error.message);
    }
  }

  loadHistory() {
    try {
      const historyPath = path.join(__dirname, 'upload-history.json');
      if (fs.existsSync(historyPath)) {
        return JSON.parse(fs.readFileSync(historyPath, 'utf8'));
      }
    } catch (error) {
      console.error('히스토리 로드 실패:', error.message);
    }
    return [];
  }

  saveHistory() {
    try {
      fs.writeFileSync(path.join(__dirname, 'upload-history.json'), JSON.stringify(this.history, null, 2));
    } catch (error) {
      console.error('히스토리 저장 실패:', error.message);
    }
  }

  convertMBToBytes(mb) {
    return mb * 1024 * 1024;
  }

  convertBytesToMB(bytes) {
    return (bytes / (1024 * 1024)).toFixed(2);
  }

  formatSpeed(bytesPerSec) {
    if (bytesPerSec === 0) return '-';
    if (bytesPerSec >= 1024 * 1024) {
      return `${(bytesPerSec / (1024 * 1024)).toFixed(2)} MB/s`;
    } else if (bytesPerSec >= 1024) {
      return `${(bytesPerSec / 1024).toFixed(2)} KB/s`;
    } else {
      return `${bytesPerSec.toFixed(0)} B/s`;
    }
  }

  calculateSpeed(bytes, startTime) {
    if (!startTime) return 0;
    const elapsed = (Date.now() - startTime) / 1000;
    return elapsed > 0 ? bytes / elapsed : 0;
  }

  getHeadersWithRequestId(requestId, extra = {}) {
    const headerObj = {};
    this.config.customHeaders.forEach(h => {
      if (h.key && h.key.toLowerCase() !== 'authorization') {
        headerObj[h.key] = h.value;
      }
    });
    if (this.config.jwtToken) {
      headerObj['Authorization'] = 'Bearer ' + this.config.jwtToken;
    }
    if (requestId) {
      headerObj['x-request-id'] = requestId;
    }
    Object.entries(extra).forEach(([k, v]) => {
      headerObj[k] = v;
    });
    return headerObj;
  }

  async requestId(requestIdBody, testIndex) {
    if (!this.config.requestIdPath) return null;

    try {
      const response = await fetch(this.config.apiOrigin.replace(/\/$/, '') + this.config.requestIdPath, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...Object.fromEntries(this.config.customHeaders.filter(h => h.key && h.key.toLowerCase() !== 'authorization').map(h => [h.key, h.value])),
          ...(this.config.jwtToken && { 'Authorization': 'Bearer ' + this.config.jwtToken })
        },
        body: JSON.stringify(requestIdBody)
      });

      if (response.ok) {
        const data = await response.json();
        const requestId = data.data?.request_id || null;
        console.log(`테스트 ${testIndex + 1} 발급된 Request ID:`, requestId);
        return requestId;
      } else {
        console.error(`테스트 ${testIndex + 1} Request ID 발급 실패:`, response.status);
        return null;
      }
    } catch (error) {
      console.error(`테스트 ${testIndex + 1} Request ID 발급 중 오류:`, error.message);
      return null;
    }
  }

  async uploadChunk(filePath, chunkSizeInBytes, fileId, totalChunks, uploadChunkUrl, requestId, chunkIndex) {
    const start = chunkIndex * chunkSizeInBytes;
    const end = Math.min(fs.statSync(filePath).size, start + chunkSizeInBytes);
    
    // 특정 범위의 파일 청크를 읽기 위한 스트림 생성
    const chunkStream = fs.createReadStream(filePath, {
      start: start,
      end: end - 1, // end는 inclusive이므로 1을 빼줌
      highWaterMark: 64 * 1024 // 64KB 버퍼
    });

    const formData = new FormData();
    this.config.customFields.forEach(f => {
      if (f.key) formData.append(f.key, f.value);
    });
    formData.append('file', chunkStream, path.basename(filePath));

    const response = await fetch(uploadChunkUrl, {
      method: 'POST',
      body: formData,
      headers: this.getHeadersWithRequestId(requestId, { 'x-chunk-index': chunkIndex, 'x-chunk-total': totalChunks })
    });

    if (!response.ok) {
      throw new Error(`청크 ${chunkIndex} 업로드 실패 (status: ${response.status})`);
    }

    return response.json();
  }

  async parallelChunkUpload(filePath, chunkSizeInBytes, fileId, totalChunks, uploadChunkUrl, requestId, testIndex) {
    let uploadedChunks = 0;
    const chunkStatus = Array(totalChunks).fill(false);
    let aborted = false;
    let errorMessage = '';
    const startTime = performance.now();

    const fileSize = fs.statSync(filePath).size;
    console.log(`[DEBUG] 청크 업로드 시작 - 파일 크기: ${fileSize} bytes, 청크 크기: ${chunkSizeInBytes} bytes, 총 청크 수: ${totalChunks}`);

    const uploadOne = async (i) => {
      if (aborted) return;

      try {
        await this.uploadChunk(filePath, chunkSizeInBytes, fileId, totalChunks, uploadChunkUrl, requestId, i);

        chunkStatus[i] = true;
        uploadedChunks++;

        const chunkPercent = Math.round((uploadedChunks / totalChunks) * 100);
        console.log(`테스트 ${testIndex + 1} - 청크 ${i + 1}/${totalChunks} 완료 (${chunkPercent}%)`);

      } catch (err) {
        aborted = true;
        errorMessage = err.message;
        throw err;
      }
    };

    // 병렬 업로드 컨트롤
    let next = 0;
    const runners = Array(Math.min(this.config.parallelCount, totalChunks)).fill(0).map(async () => {
      while (!aborted && next < totalChunks) {
        const i = next++;
        try {
          await uploadOne(i);
        } catch {
          break;
        }
      }
    });

    try {
      await Promise.all(runners);
    } catch (error) {
      console.error('청크 업로드 중 오류:', error.message);
    }

    if (aborted) {
      console.error('청크 업로드 중단:', errorMessage);
      return { startTime, endTime: performance.now(), success: false };
    }

    const endTime = performance.now();
    return { startTime, endTime, success: true };
  }

  async singleUpload(file, requestId, testIndex) {
    const formData = new FormData();
    formData.append('file', file);
    this.config.customFields.forEach(f => {
      if (f.key) formData.append(f.key, f.value);
    });

    const startTime = performance.now();
    const response = await fetch(this.config.apiOrigin.replace(/\/$/, '') + this.config.paths.singleUploadPath, {
      method: 'POST',
      body: formData,
      headers: this.getHeadersWithRequestId(requestId)
    });

    const endTime = performance.now();
    const elapsed = Math.round(endTime - startTime);

    if (response.ok) {
      console.log(`테스트 ${testIndex + 1} - 단일 업로드 성공 (${(elapsed / 1000).toFixed(2)}s)`);
      return elapsed;
    } else {
      throw new Error(`단일 업로드 실패: ${response.status}`);
    }
  }

  async mergeChunks(fileId, filename, totalChunks, requestId) {
    const mergeRes = await fetch(this.config.apiOrigin.replace(/\/$/, '') + this.config.paths.mergeChunksPath, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...this.getHeadersWithRequestId(requestId, { 'x-chunk-total': totalChunks })
      },
      body: JSON.stringify({
        fileId,
        filename,
        totalChunks,
        ...Object.fromEntries(this.config.customFields.filter(f => f.key).map(f => [f.key, f.value]))
      })
    });

    if (mergeRes.ok) {
      console.log('청크 병합 성공');
      return true;
    } else {
      throw new Error(`병합 실패: ${mergeRes.status}`);
    }
  }

  async runBatchTest(singleFilePath, chunkFilePath) {
    console.log('\n🚀 업로드 테스트 시작...\n');

    // 파일 존재 확인
    if (!fs.existsSync(singleFilePath)) {
      throw new Error(`단일 업로드 파일을 찾을 수 없습니다: ${singleFilePath}`);
    }
    if (!fs.existsSync(chunkFilePath)) {
      throw new Error(`청크 업로드 파일을 찾을 수 없습니다: ${chunkFilePath}`);
    }

    const singleFile = fs.createReadStream(singleFilePath);
    const chunkFile = fs.createReadStream(chunkFilePath);
    const singleFileStats = fs.statSync(singleFilePath);
    const chunkFileStats = fs.statSync(chunkFilePath);

    // 파일 정보 설정
    singleFile.size = singleFileStats.size;
    chunkFile.size = chunkFileStats.size;
    singleFile.name = path.basename(singleFilePath);
    chunkFile.name = path.basename(chunkFilePath);

    // Request ID Body 설정
    const fileName = path.basename(chunkFilePath);
    const lastDotIndex = fileName.lastIndexOf('.');
    const ext = lastDotIndex > 0 ? fileName.substring(lastDotIndex + 1).toLowerCase() : '';
    const dirName = lastDotIndex > 0 ? fileName.substring(0, lastDotIndex) : fileName;

    const requestIdBody = {
      ...this.config.requestIdBody,
      dir_name: dirName,
      ext: ext
    };

    // Request ID 발급
    let requestIds = [];
    if (this.config.requestIdPath) {
      console.log('Request ID 발급 중...');
      const requestIdPromises = Array.from({ length: this.config.testCount }, async (_, i) => {
        return await this.requestId(requestIdBody, i);
      });
      requestIds = await Promise.all(requestIdPromises);
    } else {
      requestIds = Array(this.config.testCount).fill(null);
    }

    // 단일 업로드 테스트
    let singleTimes = [];
    if (singleFile) {
      console.log('\n📤 단일 업로드 테스트 시작...');
      const singleUploadPromises = Array.from({ length: this.config.testCount }, async (_, i) => {
        try {
          const requestId = requestIds[i];
          const elapsed = await this.singleUpload(singleFile, requestId, i);
          return elapsed;
        } catch (error) {
          console.error(`테스트 ${i + 1} 단일 업로드 실패:`, error.message);
          return null;
        }
      });

      const results = await Promise.all(singleUploadPromises);
      singleTimes = results.filter(time => time !== null);
    }

    // 청크 업로드 테스트
    let chunkTimes = [];
    if (chunkFilePath) {
      console.log('\n📤 청크 업로드 테스트 시작...');
      const chunkSizeInBytes = this.convertMBToBytes(this.config.chunkSize);
      const totalChunks = Math.ceil(chunkFileStats.size / chunkSizeInBytes);

      console.log(`파일 크기: ${this.convertBytesToMB(chunkFileStats.size)} MB`);
      console.log(`청크 크기: ${this.config.chunkSize} MB (${chunkSizeInBytes.toLocaleString()} bytes)`);
      console.log(`예상 청크 수: ${totalChunks}개`);
      console.log(`병렬 업로드: ${this.config.parallelCount}개`);

      const chunkUploadPromises = Array.from({ length: this.config.testCount }, async (_, t) => {
        try {
          const requestId = requestIds[t];
          const fileId = `${path.basename(chunkFilePath)}-${chunkFileStats.size}-${chunkFileStats.mtimeMs}-${Date.now()}-${t}`;
          const uploadChunkUrl = this.config.apiOrigin.replace(/\/$/, '') + this.config.paths.uploadChunkPath;

          const { startTime, endTime, success } = await this.parallelChunkUpload(
            chunkFilePath, chunkSizeInBytes, fileId, totalChunks, uploadChunkUrl, requestId, t
          );

          if (success && endTime && startTime) {
            // 청크 병합
            const mergeOk = await this.mergeChunks(fileId, path.basename(chunkFilePath), totalChunks, requestId);

            if (mergeOk) {
              const elapsed = Math.round(endTime - startTime);
              console.log(`테스트 ${t + 1} - 청크 업로드 및 병합 성공 (${(elapsed / 1000).toFixed(2)}s)`);
              return elapsed;
            }
          }
          return null;
        } catch (error) {
          console.error(`테스트 ${t + 1} 청크 업로드 실패:`, error.message);
          return null;
        }
      });

      const results = await Promise.all(chunkUploadPromises);
      chunkTimes = results.filter(time => time !== null);
    }

    // 결과 출력
    console.log('\n📊 테스트 결과:');
    console.log('='.repeat(50));

    if (singleTimes.length > 0) {
      const avgSingle = Math.round(singleTimes.reduce((a, b) => a + b, 0) / singleTimes.length);
      const avgSingleSpeed = Math.round(singleFileStats.size / (avgSingle / 1000));
      console.log(`단일 업로드 평균 시간: ${(avgSingle / 1000).toFixed(2)}s`);
      console.log(`단일 업로드 평균 속도: ${this.formatSpeed(avgSingleSpeed)}`);
    }

    if (chunkTimes.length > 0) {
      const avgChunk = Math.round(chunkTimes.reduce((a, b) => a + b, 0) / chunkTimes.length);
      const avgChunkSpeed = Math.round(chunkFileStats.size / (avgChunk / 1000));
      console.log(`청크 업로드 평균 시간: ${(avgChunk / 1000).toFixed(2)}s`);
      console.log(`청크 업로드 평균 속도: ${this.formatSpeed(avgChunkSpeed)}`);
    }

    // 기록 저장
    const record = {
      date: new Date().toLocaleString(),
      count: this.config.testCount,
      avgSingle: singleTimes.length ? Math.round(singleTimes.reduce((a, b) => a + b, 0) / singleTimes.length) : null,
      avgChunk: chunkTimes.length ? Math.round(chunkTimes.reduce((a, b) => a + b, 0) / chunkTimes.length) : null,
      avgSingleSpeed: singleTimes.length ? Math.round(singleFileStats.size / (singleTimes.reduce((a, b) => a + b, 0) / singleTimes.length) * 1000) : null,
      avgChunkSpeed: chunkTimes.length ? Math.round(chunkFileStats.size / (chunkTimes.reduce((a, b) => a + b, 0) / chunkTimes.length) * 1000) : null,
      requestIds: requestIds,
      chunkSize: this.convertMBToBytes(this.config.chunkSize),
      singleFileName: path.basename(singleFilePath) || '-',
      chunkFileName: path.basename(chunkFilePath) || '-',
      singleFileSize: singleFileStats.size || 0,
      chunkFileSize: chunkFileStats.size || 0
    };

    this.history.unshift(record);
    this.history = this.history.slice(0, 50); // 최대 50개
    this.saveHistory();

    console.log('\n✅ 테스트 완료!');
    process.exit(0);
  }

  showHistory() {
    console.log('\n📋 측정 기록:');
    console.log('='.repeat(80));

    if (this.history.length === 0) {
      console.log('측정 기록이 없습니다.');
      return;
    }

    console.log('날짜\t\t\t\t청크 파일 크기\t\t응답 평균(s)\tRequest ID');
    console.log('-'.repeat(80));

    this.history.slice(0, 10).forEach((h, i) => {
      const formatFileSize = (bytes) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
      };

      const date = h.date;
      const fileSize = formatFileSize(h.chunkFileSize);
      const avgTime = h.avgChunk ? (h.avgChunk / 1000).toFixed(2) : '-';
      const requestIds = h.requestIds && h.requestIds.length > 0 ? h.requestIds.join(', ') : '-';

      console.log(`${date}\t${fileSize}\t\t\t${avgTime}\t\t${requestIds}`);
    });
  }

  clearHistory() {
    this.history = [];
    this.saveHistory();
    console.log('측정 기록이 지워졌습니다.');
  }

  async interactiveMenu() {
    console.log('\n🔧 업로드 테스트 도구');
    console.log('='.repeat(30));
    console.log('1. 설정 보기');
    console.log('2. 설정 수정');
    console.log('3. 테스트 실행');
    console.log('4. 측정 기록 보기');
    console.log('5. 측정 기록 지우기');
    console.log('6. 종료');
    console.log('='.repeat(30));

    const answer = await this.question('선택하세요 (1-6): ');

    switch (answer.trim()) {
      case '1':
        this.showConfig();
        break;
      case '2':
        await this.editConfig();
        break;
      case '3':
        await this.runTest();
        break;
      case '4':
        this.showHistory();
        break;
      case '5':
        this.clearHistory();
        break;
      case '6':
        console.log('프로그램을 종료합니다.');
        this.rl.close();
        return;
      default:
        console.log('잘못된 선택입니다.');
    }

    await this.interactiveMenu();
  }

  showConfig() {
    console.log('\n📋 현재 설정:');
    console.log('='.repeat(50));
    console.log(JSON.stringify(this.config, null, 2));
  }

  async editConfig() {
    console.log('\n✏️ 설정 수정:');
    console.log('='.repeat(30));
    console.log('1. API 서버 Origin');
    console.log('2. 테스트 횟수');
    console.log('3. 병렬 업로드 개수');
    console.log('4. 청크 크기 (MB)');
    console.log('5. JWT 토큰');
    console.log('6. Request ID 발급 Path');
    console.log('7. 뒤로 가기');

    const answer = await this.question('수정할 항목을 선택하세요 (1-7): ');

    switch (answer.trim()) {
      case '1':
        this.config.apiOrigin = await this.question('API 서버 Origin: ');
        break;
      case '2':
        this.config.testCount = parseInt(await this.question('테스트 횟수: '));
        break;
      case '3':
        this.config.parallelCount = parseInt(await this.question('병렬 업로드 개수: '));
        break;
      case '4':
        this.config.chunkSize = parseInt(await this.question('청크 크기 (MB): '));
        break;
      case '5':
        this.config.jwtToken = await this.question('JWT 토큰: ');
        break;
      case '6':
        this.config.requestIdPath = await this.question('Request ID 발급 Path: ');
        break;
      case '7':
        return;
      default:
        console.log('잘못된 선택입니다.');
        return;
    }

    this.saveConfig();
    console.log('설정이 저장되었습니다.');
  }

  async runTest() {
    console.log('\n🚀 테스트 실행:');
    console.log('='.repeat(30));

    const singleFilePath = await this.question('단일 업로드 파일 경로: ');
    const chunkFilePath = await this.question('청크 업로드 파일 경로: ');

    try {
      await this.runBatchTest(singleFilePath.trim(), chunkFilePath.trim());
    } catch (error) {
      console.error('테스트 실행 중 오류:', error.message);
    }
  }

  question(query) {
    return new Promise((resolve) => {
      this.rl.question(query, resolve);
    });
  }
}

// 메인 실행
async function main() {
  const tester = new UploadTester();

  // 명령행 인수 처리
  const args = process.argv.slice(2);

  if (args.length === 0) {
    // 대화형 모드
    await tester.interactiveMenu();
  } else if (args[0] === '--help' || args[0] === '-h') {
    console.log(`
업로드 테스트 도구

사용법:
  node upload-test.js                    # 대화형 모드
  node upload-test.js <single_file> <chunk_file>  # 직접 테스트 실행
  node upload-test.js --help             # 도움말

옵션:
  --help, -h     도움말 표시

설정:
  config.json 파일에서 테스트 설정을 수정할 수 있습니다.
    `);
    process.exit(0);
  } else if (args.length === 2) {
    // 직접 테스트 실행
    try {
      await tester.runBatchTest(args[0], args[1]);
    } catch (error) {
      console.error('테스트 실행 중 오류:', error.message);
      process.exit(1);
    }
  } else {
    console.error('잘못된 인수입니다. --help를 참조하세요.');
    process.exit(1);
  }
}

if (require.main === module) {
  main().catch(console.error);
}

module.exports = UploadTester;