---
name: product-docs
description: Create/update product docs in a central docs repo and auto-create a PR. Run from any dev repo to centrally manage product documentation.
disable-model-invocation: false
argument-hint: "<doc-type> <title>  (e.g. feature login, api booking API, status)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
# WebSearch/WebFetch intentionally excluded: product docs are written from internal information only
---

# Product Docs Skill

Create/update product documentation in a central docs repo and automatically open a PR, all from your dev repo.

## Input

`$ARGUMENTS`

## Phase 1: Config check

Check for `.product-docs.config.json` in the current working directory.

### Config file missing → Initial setup

Ask the user the following questions in order to generate the config file.

**Questions:**

1. **Docs repo path**: Absolute local path to the product docs repo
   - e.g. `/path/to/your/docs-repo`
   - If path doesn't exist → ask whether to clone
2. **Clone URL** (only if path doesn't exist): Git clone URL for the docs repo
   - e.g. `git@github.com:your-org/your-docs-repo.git`
   - Clone to the specified path after confirmation
   - Saved in config for future re-cloning if the path disappears (optional field)
3. **Product mapping**: Product folder name(s) in the docs repo that this repo maps to
   - List the folders under `products/` in the docs repo for the user to choose from
   - A repo may relate to multiple products (array)
4. **Author name**: Name to record as the document author

**Config file schema (`.product-docs.config.json`):**

```json
{
  "productDocsPath": "/absolute/path/to/docs-repo",
  "cloneUrl": "git@github.com:your-org/your-docs-repo.git",
  "products": ["ProductA"],
  "author": "yourname"
}
```

After creating the config file, remind the user to add `.product-docs.config.json` to `.gitignore`.

### Config file exists

1. Load the config.
2. Verify `productDocsPath` exists.
   - If missing and `cloneUrl` is set → ask whether to clone.
   - If missing and no `cloneUrl` → show error.
3. Pull the latest `main` branch of the docs repo.

## Phase 2: Command parsing

Parse `$ARGUMENTS`.

### Supported commands

| Command | Description | Example |
|---------|-------------|---------|
| `status` | Show document status for mapped product(s) | `/product-docs status` |
| `feature <title>` | Create/update a feature doc | `/product-docs feature login` |
| `api <title>` | Create/update an API doc | `/product-docs api booking API` |
| `arch <title>` | Create/update an architecture doc | `/product-docs arch system overview` |
| `guide <title>` | Create/update a user guide | `/product-docs guide getting started` |
| `ops <title>` | Create/update an ops guide | `/product-docs ops deployment` |
| `data <title>` | Create/update a data model doc | `/product-docs data ERD` |
| `update <doc-path>` | Update an existing doc | `/product-docs update FEAT-001-login.md` |
| `config` | View/edit current config | `/product-docs config` |

### config command details

When `config` is invoked:

1. **No arguments**: Pretty-print the current `.product-docs.config.json`
2. **With arguments** (e.g. `/product-docs config author newname`): Update the specified field and save
3. Editable fields: `productDocsPath`, `cloneUrl`, `products`, `author`
4. If no config file exists, redirect to the initial setup flow (Phase 1)

Natural language input is also accepted. Examples:
- "Add a login feature doc to {product}" → `feature login`
- "Update {product} API docs" → API doc update flow

If `products` array has multiple entries, ask the user which product to target.

## Phase 3: Document work

### 3-1. Context gathering

Gather information needed for writing:

1. **From the current dev repo** (scope: only parts directly related to the requested doc topic):
   - Product/feature descriptions from README.md, CLAUDE.md, etc.
   - Source code structure of the specific feature/module the user indicated (reference only — do not scan the entire repo)
   - If scope is unclear, ask the user which directory/module to reference

2. **From the docs repo**:
   - Existing docs for the product (`products/{product}/`)
   - Document list in the product README.md
   - Relevant templates (`templates/product-templates/`)
   - Existing numbering scheme (to determine the next number)
   - `CLAUDE.md` rules for doc writing (if present, read and follow them)

3. **Ask the user for additional input**:
   - Ask about key content to include in the document
   - Help the developer translate technical knowledge into a business perspective

### 3-2. Writing rules

**These rules MUST be followed:**

#### Target audience: PO (Product Owner) and non-developers

- The readers are **POs, planners, and business stakeholders**, not developers.
- Explain from a **business value and user perspective**, not technical implementation details.

#### Never include

- Source code, code snippets, code blocks (programming code inside ```` ``` ````)
- Programming language syntax, variable/function/class names
- Implementation-level technical terms (ORM, middleware, hook, callback, etc.)
- Dependency package or library names
- Environment variables, config file contents
- CLI commands, build/deploy scripts

#### Exceptions allowed

- **API docs**: Endpoint paths (`POST /v1/bookings`)
- **API docs**: JSON request/response examples (from a business data perspective)
- **Data model docs**: ERD (Mermaid diagrams)
- **Architecture docs**: System diagrams (Mermaid or ASCII)
- Technology stack mentions (briefly, in table form)

#### Tone & style

- Write in **Korean** (the docs repo's language)
- **Concise, clear sentences**: one piece of information per sentence
- **Use tables liberally**: for comparisons and lists
- **Prefer Mermaid diagrams**: for processes, data flows, state transitions
- **Range notation**: Use en dash (`–`) instead of tilde (`~`) (e.g. `3–7월`)
- Avoid unnecessary modifiers and exaggeration
- Use formal Korean ("~합니다" style)

#### File naming conventions

| Doc type | Prefix | Format | Example |
|----------|--------|--------|---------|
| Architecture | `ARCH` | `ARCH-[number]-[title].md` | `ARCH-001-시스템-개요.md` |
| Feature | `FEAT` | `FEAT-[number]-[title].md` | `FEAT-001-로그인.md` |
| API | `API` | `API-[number]-[title].md` | `API-001-인증-API.md` |
| User guide | `USER` | `USER-[number]-[title].md` | `USER-001-시작하기.md` |
| Ops guide | `OPS` | `OPS-[number]-[title].md` | `OPS-001-배포-절차.md` |
| Data model | `DATA` | `DATA-[number]-[title].md` | `DATA-001-ERD.md` |

- Number = last existing number for that product + 1
- Title in Korean, words joined by hyphens (`-`)
- Do not rename existing files when updating

#### Document header

Every document starts with:

```
# [PREFIX]-[NUMBER]-[TITLE]

> 문서 상태: `DRAFT` | 작성자: [author] | 작성일: [YYYY-MM-DD]
```

#### Template reference

When creating a document, always read the corresponding template from `templates/product-templates/` in the docs repo and follow its structure:

| Command | Template file |
|---------|--------------|
| `feature` | `templates/product-templates/feature.md` |
| `api` | `templates/product-templates/api.md` |
| `arch` | `templates/product-templates/architecture.md` |
| `guide` | `templates/product-templates/user-guide.md` |
| `ops` | `templates/product-templates/ops-guide.md` |
| `data` | `templates/product-templates/data.md` |

### 3-3. Document creation procedure

1. Read the corresponding template from the docs repo.
2. Check existing docs in the product folder to determine the next number.
3. Write the document based on gathered context and user input.
4. Show the draft to the user and get confirmation.

### 3-4. Side effects

After creating/updating a document, always handle:

1. **Update product README.md**: Add new doc link to the document list section
2. **CHANGELOG entry**: Add change record to `changelog/CHANGELOG-[current-year].md`
3. **INDEX update**: Update `products/INDEX.md` if needed

## Phase 4: Git workflow (automated)

Once the document is finalized, perform the following in the docs repo.

### 4-0. User confirmation before PR

Before creating a branch or pushing, show the user a summary and get approval:

- Target repo path
- Branch name to create
- List of files to be changed/created
- Draft commit message

Proceed to 4-1 only after approval. If rejected, revise the document or abort.

### 4-1. Create branch

```bash
cd {productDocsPath}
git checkout main
git pull origin main
git checkout -b docs/{product}-{brief-description}
```

Branch name example: `docs/ProductA-login-feature-doc`, `docs/ProductB-booking-API`

### 4-2. Commit

```bash
git add {changed files}
git commit -m "docs: {product} {document title}"
```

Commit message rules:
- Prefix: `docs:`
- Include product name
- Brief change description

### 4-3. Create PR

```bash
git push origin docs/{branch-name}
gh pr create --title "docs: {product} {document title}" --body "{PR body}"
```

PR body format:

```markdown
## Changes

- {Change summary}

## Document type

- [ ] Architecture (ARCH)
- [ ] Feature (FEAT)
- [ ] API
- [ ] User guide (USER)
- [ ] Ops guide (OPS)
- [ ] Data model (DATA)

## Related product

{product}

## Checklist

- [ ] Template format followed
- [ ] File naming convention followed
- [ ] Product README document list updated
- [ ] CHANGELOG entry added
```

### 4-4. Completion report

Report to the user:
- Created/updated document file path
- PR URL
- Next steps (e.g. request review)

## Phase 5: status command

When `status` is invoked, show the document status for the mapped product(s):

1. Read `products/{product}/README.md` to check the document list
2. Verify actual file existence in each subfolder
3. Output in this format:

```
{product} Document Status

Architecture: {N} docs
Features:     {N} docs
API:          {N} docs
Guides:       {N} docs
Data:         {N} docs

Recent changes:
- {Last 3 entries from CHANGELOG}
```

## Error handling

- Config path invalid → ask for the path again
- Git conflict in docs repo → guide user to resolve manually
- gh CLI not installed → suggest `brew install gh`
- gh not authenticated → suggest `gh auth login`
- Branch name collision → append timestamp suffix
