---
name: add-service-shortcut
description: 현재 프로젝트를 바로가기 대시보드(~/Workspaces/tport/shortcuts.html)에 항목으로 추가/수정(upsert)한다. 작업경로는 실행한 디렉토리를 자동 반영. 이름 기준 upsert, 메모만 나중에 붙이는 부분 업데이트 지원.
disable-model-invocation: false
argument-hint: "[이름]  — 없으면 현재 프로젝트에서 추론 (예: /add-service-shortcut my-service)"
allowed-tools: Bash, Read, Glob
---

# Add Service Shortcut

`~/Workspaces/tport/shortcuts.html` 의 `DATA` 배열에 항목을 upsert 한다. 번호·섹션 카운트·총계·정렬은 스크립트가 자동 처리하므로 **HTML 을 직접 편집하지 말 것**.

## 동작 방식 — 묻지 말고 제안

원칙: **현재 디렉토리와 프로젝트 파일에서 값을 스스로 추론해 바로 upsert 한다.** 명확하면 사용자에게 되묻지 않는다. 사용자가 값을 직접 준 경우(대화 맥락·`$ARGUMENTS`)엔 그 값을 우선 사용한다.

| 필드 | 필수 | 추론 방법 (사용자가 안 줬을 때) |
|------|------|------|
| name (이름) | ✅ | `$ARGUMENTS` 첫 토큰 → package.json `name` → 디렉토리명 |
| desc (설명) |  | package.json `description` → README 첫 제목/문장 |
| url |  | README·배포 설정에 명시된 배포 URL 이 있으면 사용, 없으면 생략(URL 없이 등록) |
| section (섹션) |  | **명시 안 하면 항상 `실험 서비스`.** 아래 6개 중 하나 |
| badge |  | `mcp` 또는 `local` (해당할 때만) |
| memo (메모) |  | 프로젝트 성격이 뚜렷하면 요약해 채움. 여러 줄 가능 |
| path (작업경로) |  | 스크립트 실행 디렉토리(cwd) 자동. 사용자가 다른 경로를 명시할 때만 지정 |

섹션 값: `실험 서비스`(기본) · `공개 서비스` · `머신` · `MCP` · `로컬 Mac only` · `로컬 프로젝트 (URL 없음)`

### 되물음은 최소로
- 기본 흐름은 **추론 → 즉시 실행 → 결과 한 줄 보고**. "이 정보로 추가할까요?" 식 확인 질문을 하지 않는다.
- 되물어도 되는 유일한 경우: `name` 조차 특정 못 할 때(빈 디렉토리 등). 이때만 한 줄로 묻는다.
- 섹션을 `실험 서비스` 가 아닌 값으로 넣을 근거(공개 URL·MCP 서버 등)가 뚜렷하면 그 섹션으로 바로 넣는다 — 굳이 묻지 않는다.
- **작업경로는 절대 묻지 않는다.** cwd 자동(홈은 `~` 치환). 사용자가 "경로는 X" 라고 명시할 때만 `path` 를 넘긴다.
- **기존 항목 메모만 갱신**하는 경우엔 이름 + 메모만 넘기면 된다(나머지 필드 유지).

## 실행

수집한 값을 JSON 으로 만들어 스크립트에 넘긴다. **값이 없는 필드는 키 자체를 생략**한다 — 빈 문자열로 넣지 말 것(부분 업데이트가 깨진다). url 을 **제거**하려면 `"url": ""` 로 명시.

작업경로를 자동(현재 디렉토리)으로 쓰려면 `path` 키를 생략한다. 아래처럼 heredoc 으로 JSON 을 전달하면 따옴표·여러 줄 메모도 안전하다:

```bash
node "${CLAUDE_SKILL_DIR}/upsert.mjs" "$(cat <<'JSON'
{
  "name": "my-service",
  "desc": "서비스 한 줄 설명",
  "url": "https://example.com",
  "section": "공개 서비스",
  "memo": "여러 줄\n메모도 가능"
}
JSON
)"
```

메모만 나중에 붙이는 예 (기존 항목 유지, 메모만 갱신):

```bash
node "${CLAUDE_SKILL_DIR}/upsert.mjs" '{"name":"my-service","memo":"실험 중 — YYYY-MM 종료 예정"}'
```

스크립트 출력(`✓ added/updated: … → #N`)을 그대로 사용자에게 보여준다. 실행 후 별도 설명은 붙이지 않는다.

## 주의
- 대상 파일은 `~/Workspaces/tport/shortcuts.html` 고정. 다른 파일 아님.
- 스크립트는 Node(ESM) 로 실행된다.
