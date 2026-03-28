# product-docs

A Claude Code skill that creates/updates product documentation in a central docs repo and automatically opens a PR.

> [한국어](./README.ko.md)

## Prerequisites

- A central product docs repo (markdown-based, with `products/` and `templates/product-templates/` directory structure)
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- Push access to the product docs repo

## Usage

### First run (initial setup)

On first run, a config file (`.product-docs.config.json`) doesn't exist yet, so the skill walks you through an interactive setup.

```
/product-docs feature login
```

Questions asked:
1. Local path to the product docs repo (offers to clone if missing)
2. Product name to map to this repo
3. Your author name

After setup, `.product-docs.config.json` is created. **Add this file to `.gitignore`.**

### Creating documents

```
/product-docs feature login                # Feature doc
/product-docs api booking API              # API doc
/product-docs arch system overview         # Architecture doc
/product-docs guide getting started        # User guide
/product-docs ops deployment               # Ops guide
/product-docs data ERD                     # Data model
```

Also works with natural language:

```
Add a login feature doc
Update the booking API doc
```

### Check document status

```
/product-docs status
```

### Update an existing document

```
/product-docs update FEAT-001-login.md
```

### View/edit config

```
/product-docs config
```

## Config schema

`.product-docs.config.json`:

```json
{
  "productDocsPath": "/absolute/path/to/docs-repo",
  "cloneUrl": "git@github.com:your-org/your-docs-repo.git",
  "products": ["ProductA"],
  "author": "yourname"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `productDocsPath` | Y | Absolute local path to the product docs repo |
| `cloneUrl` | N | Clone URL for when the repo doesn't exist locally |
| `products` | Y | Array of product folder names to map |
| `author` | Y | Author name for document headers |

## Workflow

```
Run /product-docs from your dev repo
  ↓
Check config (.product-docs.config.json)
  ↓
Gather context from current repo (README, code structure)
  ↓
Write document based on templates
  ↓
User review
  ↓
Create docs/* branch → commit → PR
  ↓
Report PR URL
```

## Writing principles

- Target audience: **PO / product managers** (non-developers)
- Written from a business value and user perspective
- No source code or programming jargon allowed
- Follows the product docs repo's templates and naming conventions
