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
| [slack-scheduled-message](./slack-scheduled-message) | Schedule a future Slack message (default self-DM, configurable to private channel) with a `claude --resume <session>` command | `/slack-scheduled-message 5/11 09:32 ...` or natural language |
| [weather-daily](./weather-daily) | Daily weather brief for Korea — KMA forecast + air quality + UV, posted to Slack as a one-line summary (temp / humidity / UV) plus actionable advice (outfit / umbrella / mask) | `/weather-daily` (typically wired to a cron at 08:00 KST on an always-on host) |
| [fearandgreed](./fearandgreed) | Daily CNN Fear & Greed Index posted to Slack — score, rating, gauge, prev close/week/month/year | `/fearandgreed` (typically a weekday cron at 09:00 KST) |
| [cat-fact-daily](./cat-fact-daily) | Daily cat fact in the "Momo" cat persona (Korean), posted to Slack | `/cat-fact-daily` (weekday morning cron) |
| [cat-photo-daily](./cat-photo-daily) | Daily random cat photo with a "Momo" cat-persona one-liner, posted to Slack | `/cat-photo-daily` (weekday afternoon cron) |
| [slack-edit-message](./slack-edit-message) | Edit or delete your own Slack messages (`chat.update`/`chat.delete`) — not exposed by the claude_ai Slack MCP tools, so this calls the Web API directly with a user OAuth token | `/slack-edit-message <message link> ...` or natural language |

## Structure

> Root-level `remind/` is for backward-compatible symlink installs. `plugins/` contains the same skill wrapped for plugin marketplace installs. Skill files exist in both locations to support both setup methods.

```
skills/
├── .claude-plugin/
│   └── marketplace.json        # Plugin marketplace definition
├── plugins/                    # Plugin structure (for marketplace install)
│   ├── remind/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/remind/
│   ├── slack-scheduled-message/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-scheduled-message/
│   ├── weather-daily/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/weather-daily/
│   ├── fearandgreed/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/fearandgreed/
│   ├── cat-fact-daily/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/cat-fact-daily/
│   ├── cat-photo-daily/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/cat-photo-daily/
│   └── slack-edit-message/
│       ├── .claude-plugin/plugin.json
│       └── skills/slack-edit-message/
├── remind/                     # Legacy structure (symlink compatible)
├── slack-scheduled-message/
├── weather-daily/
├── fearandgreed/
├── cat-fact-daily/
├── cat-photo-daily/
└── slack-edit-message/
```

Heads up: the `plugins/` copies are real duplicates, not symlinks — edit both and bump `plugin.json` version when changing a skill.

Secrets: this repo is public, so Slack-posting skills load their webhook / bot / user token from a gitignored `.env` (see each skill's `.env.example`) — never commit real secrets.
