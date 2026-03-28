# Custom Skills for Claude Code

Personal productivity skills for Claude Code.

> [한국어](./README.ko.md)

## Setup

### Option 1: Plugin Marketplace (recommended)

No clone required:

```bash
# Register marketplace (once)
/plugin marketplace add jadewon/skills

# Install individual plugins
/plugin install remind@jadewon-skills
/plugin install product-docs@jadewon-skills
```

### Option 2: Symlink

```bash
# Clone this repo, then symlink the skill you want
ln -s /path/to/this-repo/remind ~/.claude/skills/remind
# Or from the plugin structure
ln -s /path/to/this-repo/plugins/remind/skills/remind ~/.claude/skills/remind
```

## Skills

| Skill | Description | Usage |
|-------|-------------|-------|
| [remind](./remind) | macOS notification timer | `/remind 5m meeting` or natural language |
| [product-docs](./product-docs) | Create/update docs in a central product docs repo + auto PR | `/product-docs feature login` or natural language |

## Structure

> Root-level `remind/` and `product-docs/` are for backward-compatible symlink installs. `plugins/` contains the same skills wrapped for plugin marketplace installs. Skill files exist in both locations to support both setup methods.

```
skills/
├── .claude-plugin/
│   └── marketplace.json        # Plugin marketplace definition
├── plugins/                    # Plugin structure (for marketplace install)
│   ├── remind/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/remind/
│   └── product-docs/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       └── skills/product-docs/
├── remind/                     # Legacy structure (symlink compatible)
└── product-docs/               # Legacy structure (symlink compatible)
```
