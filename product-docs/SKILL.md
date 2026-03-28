---
name: product-docs
description: 중앙 제품 문서 레포에 문서를 생성/수정하고 자동으로 PR을 올리는 스킬. 개발 레포에서 실행하여 제품 문서를 중앙 관리합니다.
disable-model-invocation: false
argument-hint: "<문서유형> <제목>  (e.g. feature 로그인 기능, api 예약 API, status)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
# WebSearch, WebFetch는 의도적 제외: 제품 문서는 내부 정보만으로 작성하며 외부 검색이 필요하지 않음
---

# Product Docs Skill

개발 레포에서 중앙 제품 문서 레포의 제품 문서를 생성/수정하고 자동 PR을 올립니다.

## Input

`$ARGUMENTS`

## Phase 1: 설정 확인

현재 작업 디렉토리에서 `.product-docs.config.json` 파일을 확인합니다.

### 설정 파일이 없는 경우 → 초기 설정

사용자에게 순서대로 질문하여 설정 파일을 생성합니다.

**질문 항목:**

1. **제품 문서 레포 경로**: 로컬에 제품 문서 레포가 있는 절대 경로
   - 예: `/path/to/your/docs-repo`
   - 경로가 존재하지 않으면 → clone 여부를 물어봄
2. **clone URL** (경로가 없을 때만): 제품 문서 레포 git clone URL
   - 예: `git@github.com:your-org/your-docs-repo.git`
   - 확인 후 해당 경로에 clone 실행
   - 나중에 경로가 사라졌을 때 재 clone을 위해 설정에 저장 (선택 필드)
3. **제품 매핑**: 현재 레포가 대응하는 제품 문서 레포 내 제품 폴더명
   - 제품 문서 레포의 `products/` 하위 폴더명을 안내하여 선택하도록 함
   - 여러 제품과 관련된 레포일 수 있음 (배열)
4. **작성자 이름**: 문서 작성자로 기록할 이름

**설정 파일 스키마 (`.product-docs.config.json`):**

```json
{
  "productDocsPath": "/absolute/path/to/docs-repo",
  "cloneUrl": "git@github.com:your-org/your-docs-repo.git",
  "products": ["ProductA"],
  "author": "yourname"
}
```

설정 파일 생성 후 사용자에게 `.gitignore`에 `.product-docs.config.json`을 추가할 것을 안내합니다.

### 설정 파일이 있는 경우

1. 설정을 로드합니다.
2. `productDocsPath` 경로가 실제 존재하는지 확인합니다.
   - 존재하지 않고 `cloneUrl`이 있으면 clone 여부를 확인합니다.
   - 존재하지 않고 `cloneUrl`도 없으면 에러를 출력합니다.
3. 제품 문서 레포의 `main` 브랜치를 pull하여 최신 상태를 확인합니다.

## Phase 2: 명령 파싱

`$ARGUMENTS`를 파싱합니다.

### 지원 명령

| 명령 | 설명 | 예시 |
|------|------|------|
| `status` | 매핑된 제품의 문서 현황 조회 | `/product-docs status` |
| `feature <제목>` | 기능 문서 생성/수정 | `/product-docs feature 로그인 기능` |
| `api <제목>` | API 문서 생성/수정 | `/product-docs api 예약 API` |
| `arch <제목>` | 아키텍처 문서 생성/수정 | `/product-docs arch 시스템 개요` |
| `guide <제목>` | 사용자 가이드 생성/수정 | `/product-docs guide 시작하기` |
| `ops <제목>` | 운영 가이드 생성/수정 | `/product-docs ops 배포 절차` |
| `data <제목>` | 데이터 모델 문서 생성/수정 | `/product-docs data ERD` |
| `update <문서경로>` | 기존 문서 수정 | `/product-docs update FEAT-001-로그인.md` |
| `config` | 현재 설정 확인/수정 | `/product-docs config` |

### config 명령 상세

`config` 명령 실행 시:

1. **인자 없이 실행**: 현재 `.product-docs.config.json` 내용을 보기 좋게 출력
2. **인자와 함께 실행** (예: `/product-docs config author newname`): 해당 필드를 수정하고 파일에 저장
3. 수정 가능 필드: `productDocsPath`, `cloneUrl`, `products`, `author`
4. 설정 파일이 없으면 초기 설정 흐름(Phase 1)으로 안내

자연어 입력도 허용합니다. 예:
- "{제품명} 제품에 로그인 기능 문서 추가해줘" → `feature 로그인`
- "{제품명} API 문서 업데이트해줘" → 해당 제품의 API 문서 수정 흐름

`products` 배열에 제품이 여러 개면 어떤 제품인지 사용자에게 확인합니다.

## Phase 3: 문서 작업

### 3-1. 컨텍스트 수집

문서 작성에 필요한 정보를 수집합니다:

1. **현재 개발 레포에서 수집** (범위 기준: 사용자가 요청한 문서 주제와 직접 관련된 부분만):
   - README.md, CLAUDE.md 등에서 제품/기능 설명
   - 사용자가 지정한 기능/모듈의 소스 코드 구조 (문서 작성 참고용으로만 사용, 전체 레포를 탐색하지 않음)
   - 범위가 불명확하면 사용자에게 어떤 디렉토리/모듈을 참고할지 질문

2. **제품 문서 레포에서 수집**:
   - 해당 제품의 기존 문서 (`products/{제품명}/`)
   - 제품 README.md의 문서 목록
   - 관련 템플릿 (`templates/product-templates/`)
   - 기존 문서의 번호 체계 (다음 번호 결정)
   - `CLAUDE.md`의 문서 작성 규칙 (있다면 반드시 읽고 따른다)

3. **사용자에게 추가 정보 요청**:
   - 문서에 포함할 핵심 내용을 사용자에게 물어봅니다
   - 개발자가 알고 있는 기술적 내용을 비즈니스 관점으로 정리할 수 있도록 질문합니다

### 3-2. 문서 작성 규칙

**이 규칙은 반드시 준수해야 합니다:**

#### 대상 독자: PO (Product Owner) 및 비개발자

- 이 문서의 독자는 개발자가 아니라 **PO, 기획자, 비즈니스 담당자**입니다.
- 기술 구현 세부사항이 아닌 **비즈니스 가치와 사용자 관점**에서 설명합니다.

#### 절대 포함하지 않는 것

- 소스 코드, 코드 스니펫, 코드 블록 (```` ``` ```` 안의 프로그래밍 코드)
- 프로그래밍 언어 문법, 변수명, 함수명, 클래스명
- 구현 수준의 기술 용어 (ORM, middleware, hook, callback 등)
- 의존성 패키지명, 라이브러리명
- 환경 변수, 설정 파일 내용
- CLI 명령어, 빌드/배포 스크립트

#### 예외적으로 허용하는 것

- **API 문서**에서의 엔드포인트 경로 (`POST /v1/bookings`)
- **API 문서**에서의 JSON 요청/응답 예시 (비즈니스 데이터 관점)
- **데이터 모델 문서**에서의 ERD (Mermaid 다이어그램)
- **아키텍처 문서**에서의 시스템 구성도 (Mermaid 또는 ASCII 다이어그램)
- 기술 스택 언급 (테이블 형태로 간략히)

#### 문서 톤 & 스타일

- **한국어**로 작성합니다
- **간결하고 명확한 문장**: 한 문장에 하나의 정보
- **표(Table) 적극 활용**: 정보 비교, 목록 정리에 표 사용
- **Mermaid 다이어그램 권장**: 프로세스, 데이터 흐름, 상태 전이 시각화
- **범위 표기**: 틸드(`~`) 대신 en dash(`–`) 사용 (예: `3–7월`)
- 불필요한 수식어, 과장 표현 지양
- "~합니다" 체 사용

#### 파일명 규칙

| 문서 유형 | 접두어 | 형식 | 예시 |
|----------|--------|------|------|
| 아키텍처 | `ARCH` | `ARCH-[번호]-[제목].md` | `ARCH-001-시스템-개요.md` |
| 기능 | `FEAT` | `FEAT-[번호]-[제목].md` | `FEAT-001-로그인.md` |
| API | `API` | `API-[번호]-[제목].md` | `API-001-인증-API.md` |
| 사용자 가이드 | `USER` | `USER-[번호]-[제목].md` | `USER-001-시작하기.md` |
| 운영 가이드 | `OPS` | `OPS-[번호]-[제목].md` | `OPS-001-배포-절차.md` |
| 데이터 모델 | `DATA` | `DATA-[번호]-[제목].md` | `DATA-001-ERD.md` |

- 번호는 해당 제품의 기존 문서에서 마지막 번호 + 1
- 제목은 한글, 단어 사이 하이픈(`-`)으로 연결
- 기존 문서 수정 시 파일명 변경하지 않음

#### 문서 헤더

모든 문서는 다음 헤더로 시작합니다:

```
# [접두어]-[번호]-[제목]

> 문서 상태: `DRAFT` | 작성자: [author] | 작성일: [YYYY-MM-DD]
```

#### 템플릿 참조

문서 생성 시 반드시 제품 문서 레포의 `templates/product-templates/` 하위 해당 템플릿을 읽고, 그 구조를 따릅니다:

| 명령 | 템플릿 파일 |
|------|-----------|
| `feature` | `templates/product-templates/feature.md` |
| `api` | `templates/product-templates/api.md` |
| `arch` | `templates/product-templates/architecture.md` |
| `guide` | `templates/product-templates/user-guide.md` |
| `ops` | `templates/product-templates/ops-guide.md` |
| `data` | `templates/product-templates/data.md` |

### 3-3. 문서 생성 절차

1. 제품 문서 레포에서 해당 템플릿 파일을 읽습니다.
2. 해당 제품 폴더의 기존 문서를 확인하여 다음 번호를 결정합니다.
3. 수집한 컨텍스트와 사용자 입력을 바탕으로 문서를 작성합니다.
4. 작성된 문서를 사용자에게 보여주고 확인을 받습니다.

### 3-4. 부수 작업

문서 생성/수정 후 반드시 처리합니다:

1. **제품 README.md 업데이트**: `문서 목록` 섹션에 새 문서 링크 추가
2. **CHANGELOG 기록**: `changelog/CHANGELOG-[현재년도].md`에 변경 내역 추가
3. **INDEX 업데이트**: 필요시 `products/INDEX.md` 업데이트

## Phase 4: Git 워크플로 (자동화)

문서 작성이 완료되면 제품 문서 레포에서 다음을 수행합니다.

### 4-0. PR 생성 전 사용자 확인

브랜치 생성 및 push 전에 사용자에게 다음 요약을 보여주고 확인을 받습니다:

- 대상 레포 경로
- 생성할 브랜치명
- 변경/생성될 파일 목록
- 커밋 메시지 초안

사용자가 승인하면 4-1부터 진행합니다. 거부하면 문서를 수정하거나 작업을 중단합니다.

### 4-1. 브랜치 생성

```bash
cd {productDocsPath}
git checkout main
git pull origin main
git checkout -b docs/{제품명}-{간략설명}
```

브랜치명 예시: `docs/ProductA-로그인-기능-문서`, `docs/ProductB-예약-API`

### 4-2. 커밋

```bash
git add {변경된 파일들}
git commit -m "docs: {제품명} {문서 제목}"
```

커밋 메시지 규칙:
- 접두어: `docs:`
- 제품명 포함
- 간결한 변경 설명

### 4-3. PR 생성

```bash
git push origin docs/{브랜치명}
gh pr create --title "docs: {제품명} {문서 제목}" --body "{PR 본문}"
```

PR 본문 형식:

```markdown
## 변경 내용

- {변경 사항 요약}

## 문서 유형

- [ ] 아키텍처 (ARCH)
- [ ] 기능 (FEAT)
- [ ] API
- [ ] 사용자 가이드 (USER)
- [ ] 운영 가이드 (OPS)
- [ ] 데이터 모델 (DATA)

## 관련 제품

{제품명}

## 체크리스트

- [ ] 템플릿 형식 준수
- [ ] 파일명 규칙 준수
- [ ] 제품 README 문서 목록 업데이트
- [ ] CHANGELOG 기록
```

### 4-4. 완료 보고

사용자에게 다음을 보고합니다:
- 생성/수정된 문서 파일 경로
- PR URL
- 다음 단계 안내 (리뷰 요청 등)

## Phase 5: status 명령

`status` 명령 시 매핑된 제품의 문서 현황을 조회합니다:

1. `products/{제품명}/README.md`를 읽어 문서 목록 확인
2. 각 하위 폴더의 실제 파일 존재 여부 확인
3. 다음 형식으로 출력:

```
{제품명} 문서 현황

아키텍처: {N}개 문서
기능:     {N}개 문서
API:      {N}개 문서
가이드:   {N}개 문서
데이터:   {N}개 문서

최근 변경:
- {CHANGELOG에서 최근 3개 항목}
```

## 에러 처리

- 설정 파일 경로 오류 → 경로를 다시 입력받음
- 제품 문서 레포 git 충돌 → 사용자에게 수동 해결 안내
- gh CLI 미설치 → 설치 안내 (`brew install gh`)
- gh 인증 안됨 → `gh auth login` 안내
- 브랜치명 중복 → 타임스탬프 접미사 추가
