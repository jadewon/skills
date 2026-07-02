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
| [slack-reactions](./slack-reactions) | Remove a reaction or list reactions you left (`reactions.remove`/`reactions.list`) | `/slack-reactions remove ...` or natural language |
| [slack-pins](./slack-pins) | Pin, unpin, or list pinned messages in a channel (`pins.add`/`remove`/`list`) | `/slack-pins ...` or natural language |
| [slack-bookmarks](./slack-bookmarks) | Manage a channel's link bookmark bar (`bookmarks.add`/`edit`/`remove`/`list`) | `/slack-bookmarks ...` or natural language |
| [slack-files](./slack-files) | Upload a local file to a channel or delete a file (external-upload flow, `files.getUploadURLExternal`+`completeUploadExternal`/`files.delete`) | `/slack-files upload ...` or natural language |
| [slack-utils](./slack-utils) | Generate a message permalink (`chat.getPermalink`) and delete a canvas (`canvases.delete`) | `/slack-utils ...` or natural language |
| [slack-status](./slack-status) | Set your own custom status and presence (`users.profile.set`/`users.setPresence`) | `/slack-status set-status ...` or natural language |
| [slack-dnd](./slack-dnd) | Snooze/end-snooze/check your Do Not Disturb state (`dnd.setSnooze`/`endSnooze`/`info`) | `/slack-dnd ...` or natural language |
| [slack-channel-admin](./slack-channel-admin) | Create/archive/rename channels, set topic/purpose, invite/kick members, mark-read (`conversations.*`) | `/slack-channel-admin ...` or natural language |
| [slack-reminders](./slack-reminders) | Create/list/complete/delete your Slack reminders (`reminders.*`) — cross-device, unlike the local `remind` skill | `/slack-reminders ...` or natural language |
| [slack-usergroups](./slack-usergroups) | Create/update Slack user groups and replace membership (`usergroups.*`) — admin-flavored, may need extra scope | `/slack-usergroups ...` or natural language |

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
│   ├── slack-edit-message/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-edit-message/
│   ├── slack-reactions/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-reactions/
│   ├── slack-pins/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-pins/
│   ├── slack-bookmarks/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-bookmarks/
│   ├── slack-files/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-files/
│   ├── slack-utils/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-utils/
│   ├── slack-status/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-status/
│   ├── slack-dnd/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-dnd/
│   ├── slack-channel-admin/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-channel-admin/
│   ├── slack-reminders/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/slack-reminders/
│   └── slack-usergroups/
│       ├── .claude-plugin/plugin.json
│       └── skills/slack-usergroups/
├── remind/                     # Legacy structure (symlink compatible)
├── slack-scheduled-message/
├── weather-daily/
├── fearandgreed/
├── cat-fact-daily/
├── cat-photo-daily/
├── slack-edit-message/
├── slack-reactions/
├── slack-pins/
├── slack-bookmarks/
├── slack-files/
├── slack-utils/
├── slack-status/
├── slack-dnd/
├── slack-channel-admin/
├── slack-reminders/
└── slack-usergroups/
```

Heads up: the `plugins/` copies are real duplicates, not symlinks — edit both and bump `plugin.json` version when changing a skill.

Secrets: this repo is public, so Slack-posting skills load their webhook / bot / user token from a gitignored `.env` (see each skill's `.env.example`) — never commit real secrets. The `slack-*` skills that need a Slack **user** OAuth token (`xoxp-...`, everything except the `*-daily` webhook posters) all check a shared `~/.config/slack-user-token/.env` first, so you only paste the token once and just keep adding OAuth scopes to the same Slack App as you use more of them.
