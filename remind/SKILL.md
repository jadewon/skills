---
name: remind
description: Set a macOS reminder notification after a specified time
disable-model-invocation: false
argument-hint: "<when> [message]  (e.g. 5m 회의 시작, 17:00 퇴근)"
allowed-tools: Bash
---

# Reminder Timer

Set a macOS notification reminder. Parse the user's input and run the reminder script.

## Input format

`$ARGUMENTS`

The first token is the time, the rest is the message. If no message is given, use "Times up!".

### Time formats

**Relative (상대 시간):**
- `30s` → 30 seconds
- `5m` → 5 minutes
- `2h` → 2 hours
- `1h30m` → compound (1 hour 30 minutes)
- `1h30m15s` → compound
- Plain number like `90` → seconds

**Absolute (절대 시간):**
- `17:00` → 24h format
- `5pm`, `9am` → 12h format
- `5:30pm`, `9:30am` → 12h with minutes

## Instructions

1. Parse the time from `$ARGUMENTS` (first token) and the message (remaining tokens).
2. Run the remind script:

```bash
"${CLAUDE_SKILL_DIR}/remind.sh" <time> <message>
```

3. Show the output to the user. Do NOT add any extra commentary — just run the command and show the result.

## Error handling

If the script exits with an error (invalid format, time already passed, etc.), show the error message as-is.
