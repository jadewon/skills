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

## Structure

> Root-level `remind/` is for backward-compatible symlink installs. `plugins/` contains the same skill wrapped for plugin marketplace installs. Skill files exist in both locations to support both setup methods.

```
skills/
├── .claude-plugin/
│   └── marketplace.json        # Plugin marketplace definition
├── plugins/                    # Plugin structure (for marketplace install)
│   └── remind/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       └── skills/remind/
└── remind/                     # Legacy structure (symlink compatible)
```
