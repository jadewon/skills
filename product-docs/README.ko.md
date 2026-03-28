# product-docs

개발 레포에서 중앙 제품 문서 레포의 제품 문서를 생성/수정하고 자동으로 PR을 올리는 Claude Code 스킬입니다.

## 설치

```bash
ln -s /path/to/this-repo/product-docs ~/.claude/skills/product-docs
```

## 사전 요구사항

- 중앙 제품 문서 레포 (마크다운 기반, `products/`, `templates/product-templates/` 디렉토리 구조를 갖춘 레포)
- [GitHub CLI](https://cli.github.com/) 설치 및 인증 (`gh auth login`)
- 제품 문서 레포에 대한 push 권한

## 사용법

### 첫 실행 (초기 설정)

스킬을 처음 실행하면 설정 파일(`.product-docs.config.json`)이 없으므로 대화형으로 설정을 생성합니다.

```
/product-docs feature 로그인 기능
```

질문 항목:
1. 제품 문서 레포의 로컬 경로 (없으면 clone 제안)
2. 현재 레포에 매핑할 제품명
3. 문서 작성자 이름

설정 완료 후 `.product-docs.config.json`이 생성됩니다. **이 파일을 `.gitignore`에 추가하세요.**

### 문서 생성

```
/product-docs feature 로그인 기능          # 기능 문서
/product-docs api 예약 API                # API 문서
/product-docs arch 시스템 개요             # 아키텍처 문서
/product-docs guide 시작하기               # 사용자 가이드
/product-docs ops 배포 절차                # 운영 가이드
/product-docs data ERD                    # 데이터 모델
```

자연어로도 사용 가능합니다:

```
로그인 기능 문서 추가해줘
예약 API 문서 업데이트해줘
```

### 문서 현황 조회

```
/product-docs status
```

### 기존 문서 수정

```
/product-docs update FEAT-001-로그인.md
```

### 설정 확인/수정

```
/product-docs config
```

## 설정 파일 스키마

`.product-docs.config.json`:

```json
{
  "productDocsPath": "/absolute/path/to/docs-repo",
  "cloneUrl": "git@github.com:your-org/your-docs-repo.git",
  "products": ["ProductA"],
  "author": "yourname"
}
```

| 필드 | 필수 | 설명 |
|------|------|------|
| `productDocsPath` | Y | 제품 문서 레포의 로컬 절대 경로 |
| `cloneUrl` | N | 레포가 없을 때 clone할 URL |
| `products` | Y | 매핑할 제품 폴더명 배열 |
| `author` | Y | 문서 작성자 이름 |

## 워크플로

```
개발 레포에서 /product-docs 실행
  ↓
설정 확인 (.product-docs.config.json)
  ↓
현재 레포 컨텍스트 수집 (README, 코드 구조)
  ↓
템플릿 기반 문서 작성
  ↓
사용자 확인
  ↓
docs/* 브랜치 생성 → 커밋 → PR
  ↓
PR URL 보고
```

## 문서 작성 원칙

- 대상 독자는 **PO/기획자** (비개발자)
- 비즈니스 가치와 사용자 관점에서 작성
- 소스 코드, 프로그래밍 용어 포함 금지
- 제품 문서 레포의 템플릿 형식과 네이밍 규칙 준수
