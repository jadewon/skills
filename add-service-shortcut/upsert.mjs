#!/usr/bin/env node
// 바로가기 대시보드(shortcuts.html)의 DATA 배열을 upsert 한다.
// 사용: node upsert.mjs '<JSON>'
//   JSON 필드: name(필수), desc, path, url, urlText, badge('mcp'|'local'), section, memo
//   - 이름(name) 기준 매칭 → 있으면 '준 필드만' 병합 갱신(부분 업데이트), 없으면 추가
//   - path 미제공 시 현재 작업 디렉토리(cwd) 사용, 홈 디렉토리는 ~ 로 치환
//   - section 미제공 시 '실험 서비스'(DEFAULT_SECTION) 로 분류
//   - url 제거는 "url": "" 로 명시
import fs from 'node:fs';
import os from 'node:os';

const TARGET = os.homedir() + '/Workspaces/tport/shortcuts.html';
const SECTIONS = ['실험 서비스', '공개 서비스', '머신', 'MCP', '로컬 Mac only', '로컬 프로젝트 (URL 없음)'];
const DEFAULT_SECTION = '실험 서비스';
const KEYS = ['section', 'name', 'desc', 'path', 'url', 'urlText', 'badge', 'memo'];

function fail(msg) { console.error('ERROR: ' + msg); process.exit(1); }

const raw = process.argv[2];
if (!raw) fail("입력 JSON 인자가 없습니다. 사용: node upsert.mjs '{\"name\":\"...\"}'");

let input;
try { input = JSON.parse(raw); } catch (e) { fail('입력 JSON 파싱 실패: ' + e.message); }
if (!input.name || !String(input.name).trim()) fail('name 은 필수입니다.');

// path 정규화(홈 → ~). 사용자가 명시했을 때만 여기서 처리한다.
// cwd 기본값은 '신규 추가' 일 때만 채운다 — 갱신 시엔 input.path 가 없어야
// `'path' in input` 이 거짓이 되어 기존 path 가 그대로 보존된다.
const home = os.homedir();
const toTilde = p => (p && String(p).startsWith(home)) ? '~' + String(p).slice(home.length) : p;
if (input.path) input.path = toTilde(input.path);

let html;
try { html = fs.readFileSync(TARGET, 'utf8'); } catch (e) { fail('대상 파일 읽기 실패: ' + TARGET); }

const re = /const DATA = \[\n([\s\S]*?)\n(\s*)\];/;
const m = html.match(re);
if (!m) fail('shortcuts.html 에서 DATA 배열을 찾지 못했습니다.');

let data;
try { data = new Function('return [' + m[1] + '\n]')(); } catch (e) { fail('DATA 배열 파싱 실패: ' + e.message); }

// upsert (name 기준, 부분 병합)
const idx = data.findIndex(d => d.name === input.name);
let action;
if (idx >= 0) {
  const cur = data[idx];
  for (const k of KEYS) if (k in input) cur[k] = input[k];
  for (const k of KEYS) if (cur[k] === '' || cur[k] == null) delete cur[k];
  if (!cur.section) cur.section = DEFAULT_SECTION;
  action = 'updated';
} else {
  const it = {};
  for (const k of KEYS) if (input[k] != null && input[k] !== '') it[k] = input[k];
  if (!it.path) it.path = toTilde(process.cwd());
  if (!it.section) it.section = DEFAULT_SECTION;
  data.push(it);
  action = 'added';
}

// 직렬화 (섹션 순서로 그룹핑, 그룹 주석 재생성)
function q(v) {
  return "'" + String(v).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\r/g, '').replace(/\n/g, '\\n') + "'";
}
function serItem(it) {
  const parts = ['section: ' + q(it.section), 'name: ' + q(it.name)];
  for (const k of ['desc', 'path', 'url', 'urlText', 'badge', 'memo']) {
    if (it[k] != null && it[k] !== '') parts.push(k + ': ' + q(it[k]));
  }
  return '    { ' + parts.join(', ') + ' },';
}

const orderedSections = [...SECTIONS];
for (const it of data) if (!orderedSections.includes(it.section)) orderedSections.push(it.section);

const lines = [];
let number = 0, targetNumber = null;
for (const sec of orderedSections) {
  const items = data.filter(d => d.section === sec);
  if (!items.length) continue;
  lines.push('    // ' + sec);
  for (const it of items) {
    number++;
    if (it.name === input.name) targetNumber = number;
    lines.push(serItem(it));
  }
}

const newBlock = 'const DATA = [\n' + lines.join('\n') + '\n' + m[2] + '];';
fs.writeFileSync(TARGET, html.replace(re, () => newBlock));

const it2 = data.find(d => d.name === input.name);
console.log(`✓ ${action}: ${it2.name}  [${it2.section}]  path=${it2.path || '—'}  → #${targetNumber}  (총 ${data.length}개)`);
