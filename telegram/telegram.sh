#!/usr/bin/env bash
# telegram.sh — one-shot Telegram Bot API calls: me / send / file / edit / react / inbox / download.
#
# No poller, no daemon: every API call is a single `curl --max-time` that exits.
# Incoming messages are only read when someone runs `inbox`.
#
# State lives outside this repo (it is PUBLIC) in ~/.claude/channels/telegram/:
#   .env         TELEGRAM_BOT_TOKEN (mode 600)
#   access.json  {"allowFrom": ["<user id>", ...]} — the only chats this script talks to / reads from
#   offset       last confirmed getUpdates update_id
#   inbox/       files fetched by `download`
#
# The token is never put on a command line: the request URL is fed to curl on stdin (`-K -`),
# so it does not show in `ps`, and curl error text is scrubbed of it before printing.
set -euo pipefail

TG_DIR="$HOME/.claude/channels/telegram"
ENV_FILE="$TG_DIR/.env"
ACCESS_FILE="$TG_DIR/access.json"
OFFSET_FILE="$TG_DIR/offset"
INBOX_DIR="$TG_DIR/inbox"

API_TIMEOUT=10
FILE_TIMEOUT=120
CHUNK_MAX=4096                          # Bot API text limit per message (counted in UTF-16 units below)
UPLOAD_MAX=$((50 * 1024 * 1024))        # sendDocument limit
PHOTO_MAX=$((10 * 1024 * 1024))         # sendPhoto limit; larger images go as a document
DOWNLOAD_MAX=$((20 * 1024 * 1024))      # getFile limit

die() { echo "ERROR: $1" >&2; exit "${2:-1}"; }   # die <message> [exit code]

usage() {
  cat <<'EOF'
usage: telegram.sh <command> [args]

  me                                               bot username (getMe)
  send [--md] [--reply-to <msg_id>] [--chat <id>] [--dry-run] <text>
                                                   send text, split into <=4096-char messages;
                                                   prints each message_id (--md = MarkdownV2)
  file [--chat <id>] <abs-path> [caption]          image -> sendPhoto, else sendDocument (<=50MB)
  edit [--md] [--chat <id>] <msg_id> <text>        editMessageText
  react [--chat <id>] <msg_id> <emoji>             setMessageReaction
  inbox [--peek]                                   new messages from allowFrom, one JSON per line;
                                                   --peek leaves the offset file untouched
  download <file_id>                               fetch into ~/.claude/channels/telegram/inbox/ (<=20MB)

--chat must be listed in access.json allowFrom; default is allowFrom[0].
EOF
}

load_token() {
  [[ -f "$ENV_FILE" ]] || die "token file not found: $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  : "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN required in $ENV_FILE}"
}

# curl_tg <url-path-after-host> <max-time> [curl args...] — prints the body.
# <url-path> contains the token, so it goes through stdin, never argv.
curl_tg() {
  local path="$1" max="$2" errf rc=0 out err
  shift 2
  errf=$(mktemp /tmp/telegram-curl.XXXXXX)
  out=$(printf 'url = "https://api.telegram.org/%s"\n' "$path" \
        | curl -sS --max-time "$max" -K - "$@" 2>"$errf") || rc=$?
  err=$(cat "$errf"); rm -f "$errf"
  if [[ $rc -ne 0 ]]; then
    err="${err//"$TELEGRAM_BOT_TOKEN"/<token>}"
    die "curl failed (exit $rc): $err" 4
  fi
  printf '%s' "$out"
}

# api <method> <json-body | -> [curl args...] — POSTs JSON (or multipart when body is "-"),
# checks .ok, prints .result as compact JSON.
api() {
  local method="$1" body="$2" max="$API_TIMEOUT" resp
  shift 2
  load_token
  if [[ "$body" == "-" ]]; then
    max="$FILE_TIMEOUT"
    resp=$(curl_tg "bot$TELEGRAM_BOT_TOKEN/$method" "$max" "$@")
  else
    resp=$(curl_tg "bot$TELEGRAM_BOT_TOKEN/$method" "$max" \
           -H 'Content-Type: application/json; charset=utf-8' --data-binary "$body")
  fi
  jq -e . >/dev/null 2>&1 <<<"$resp" || die "$method: non-JSON response: ${resp:0:200}" 3
  if [[ "$(jq -r '.ok' <<<"$resp")" != "true" ]]; then
    local code desc
    code=$(jq -r '.error_code // "?"' <<<"$resp")
    desc=$(jq -r '.description // "no description"' <<<"$resp")
    if [[ "$code" == "409" ]]; then
      desc="$desc (a webhook is set or another getUpdates poller is running for this bot)"
    fi
    die "$method rejected: $code $desc" 3
  fi
  jq -c '.result' <<<"$resp"
}

allowed_chat() {  # allowed_chat <id> — exit 0 when <id> is in allowFrom
  jq -e --arg c "$1" '.allowFrom | map(tostring) | index($c) != null' "$ACCESS_FILE" >/dev/null
}

resolve_chat() {  # resolve_chat [<id>] — prints the chat id to use, or dies
  local chat="${1:-}"
  [[ -f "$ACCESS_FILE" ]] || die "allowlist not found: $ACCESS_FILE"
  if [[ -z "$chat" ]]; then
    chat=$(jq -r '.allowFrom[0] // empty | tostring' "$ACCESS_FILE")
    [[ -n "$chat" ]] || die "allowFrom is empty in $ACCESS_FILE"
  fi
  allowed_chat "$chat" || die "chat $chat is not in allowFrom ($ACCESS_FILE); refusing" 2
  printf '%s' "$chat"
}

need_int() { [[ "$2" =~ ^[0-9]+$ ]] || die "$1 must be a positive integer, got: $2" 2; }

file_size() { wc -c <"$1" | tr -d ' '; }

cmd_me() {
  api getMe '{}' | jq -r '"@" + .username'
}

cmd_send() {
  local md="" reply="null" chat="" dry=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --md) md="MarkdownV2"; shift ;;
      --reply-to) [[ $# -ge 2 ]] || die "--reply-to needs a message id" 2
                  need_int --reply-to "$2"; reply="$2"; shift 2 ;;
      --chat) [[ $# -ge 2 ]] || die "--chat needs an id" 2; chat="$2"; shift 2 ;;
      --dry-run) dry=1; shift ;;
      --) shift; break ;;
      -*) die "send: unknown option $1" 2 ;;
      *) break ;;
    esac
  done
  [[ $# -ge 1 ]] || die "send: text required" 2
  local text="$*"
  [[ -n "$text" ]] || die "send: text is empty" 2
  chat=$(resolve_chat "$chat")

  # Split on characters, never bytes, so multibyte text is never cut mid-character.
  # Telegram counts UTF-16 code units, so a non-BMP character (emoji) weighs 2.
  local bodies
  bodies=$(jq -nc --arg t "$text" --argjson max "$CHUNK_MAX" \
                --arg chat "$chat" --arg mode "$md" --argjson reply "$reply" '
    ($t | explode
        | reduce .[] as $c ({out: [], cur: [], n: 0};
            (if $c > 65535 then 2 else 1 end) as $w
            | if .n + $w > $max then .out += [.cur] | .cur = [$c] | .n = $w
              else .cur += [$c] | .n += $w end)
        | (.out + [.cur]) | map(implode)) as $chunks
    | range(0; $chunks | length) as $i
    | {chat_id: $chat, text: $chunks[$i]}
      + (if $mode != "" then {parse_mode: $mode} else {} end)
      + (if $i == 0 and $reply != null
         then {reply_parameters: {message_id: $reply, allow_sending_without_reply: true}}
         else {} end)')

  local body
  while IFS= read -r body; do
    if [[ -n "$dry" ]]; then
      printf '%s\n' "$body"
    else
      api sendMessage "$body" | jq -r '.message_id'
    fi
  done <<<"$bodies"
}

cmd_file() {
  local chat=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chat) [[ $# -ge 2 ]] || die "--chat needs an id" 2; chat="$2"; shift 2 ;;
      --) shift; break ;;
      -*) die "file: unknown option $1" 2 ;;
      *) break ;;
    esac
  done
  [[ $# -ge 1 ]] || die "file: path required" 2
  local path="$1" caption="${2:-}"
  [[ "$path" == /* ]] || die "file: path must be absolute: $path" 2
  [[ -f "$path" ]] || die "file: not a regular file: $path" 2
  [[ "$path" != *'"'* ]] || die "file: path must not contain a double quote: $path" 2
  chat=$(resolve_chat "$chat")

  local size
  size=$(file_size "$path")
  [[ "$size" -le "$UPLOAD_MAX" ]] || die "file: $size bytes exceeds the 50MB Bot API upload limit" 2

  local ext method field
  ext=$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    jpg|jpeg|png|gif|webp) method=sendPhoto; field=photo ;;
    *) method=sendDocument; field=document ;;
  esac
  if [[ "$method" == sendPhoto && "$size" -gt "$PHOTO_MAX" ]]; then
    method=sendDocument; field=document
  fi

  # --form-string keeps caption/chat_id literal (no @file / <file interpretation).
  api "$method" - --form-string "chat_id=$chat" --form-string "caption=$caption" \
      -F "$field=@\"$path\"" | jq -r '.message_id'
}

cmd_edit() {
  local md="" chat=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --md) md="MarkdownV2"; shift ;;
      --chat) [[ $# -ge 2 ]] || die "--chat needs an id" 2; chat="$2"; shift 2 ;;
      --) shift; break ;;
      -*) die "edit: unknown option $1" 2 ;;
      *) break ;;
    esac
  done
  [[ $# -ge 2 ]] || die "edit: usage: edit [--md] [--chat <id>] <msg_id> <text>" 2
  need_int msg_id "$1"
  local mid="$1"; shift
  local text="$*"
  [[ -n "$text" ]] || die "edit: text is empty" 2
  [[ "$(jq -rn --arg t "$text" '$t | length')" -le "$CHUNK_MAX" ]] \
    || die "edit: text longer than $CHUNK_MAX characters" 2
  chat=$(resolve_chat "$chat")
  api editMessageText "$(jq -nc --arg chat "$chat" --argjson mid "$mid" --arg t "$text" --arg mode "$md" \
    '{chat_id: $chat, message_id: $mid, text: $t} + (if $mode != "" then {parse_mode: $mode} else {} end)')" \
    >/dev/null
  echo "ok"
}

cmd_react() {
  local chat=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chat) [[ $# -ge 2 ]] || die "--chat needs an id" 2; chat="$2"; shift 2 ;;
      --) shift; break ;;
      -*) die "react: unknown option $1" 2 ;;
      *) break ;;
    esac
  done
  [[ $# -eq 2 ]] || die "react: usage: react [--chat <id>] <msg_id> <emoji>" 2
  need_int msg_id "$1"
  chat=$(resolve_chat "$chat")
  api setMessageReaction "$(jq -nc --arg chat "$chat" --argjson mid "$1" --arg e "$2" \
    '{chat_id: $chat, message_id: $mid, reaction: [{type: "emoji", emoji: $e}]}')" >/dev/null
  echo "ok"
}

cmd_inbox() {
  local peek=""
  case "${1:-}" in
    "") ;;
    --peek) peek=1 ;;
    *) die "inbox: unknown argument $1" 2 ;;
  esac
  [[ -f "$ACCESS_FILE" ]] || die "allowlist not found: $ACCESS_FILE"

  local stored="" body
  if [[ -f "$OFFSET_FILE" ]]; then
    stored=$(tr -d '[:space:]' <"$OFFSET_FILE")
    need_int "offset file $OFFSET_FILE" "$stored"
  fi
  # timeout 0 = plain request, no long poll. offset = stored+1 confirms everything up to stored.
  if [[ -n "$stored" ]]; then
    body=$(jq -nc --argjson o "$((stored + 1))" '{offset: $o, timeout: 0}')
  else
    body='{"timeout":0}'
  fi

  local result
  result=$(api getUpdates "$body")

  jq -c --slurpfile acl "$ACCESS_FILE" '
    ($acl[0].allowFrom | map(tostring)) as $allow
    | .[]
    | . as $u
    | (.message // .edited_message) as $m
    | select($m != null)
    | select((($m.from.id // "" | tostring) as $f | $allow | index($f) != null)
             or (($m.chat.id | tostring) as $c | $allow | index($c) != null))
    | ( if $m.photo then {type: "photo", file_id: ($m.photo | max_by(.file_size // (.width * .height)) | .file_id)}
        else (first(("document", "voice", "audio", "video", "video_note", "animation", "sticker") as $k
                    | select($m[$k] != null) | {type: $k, file_id: $m[$k].file_id}) // null)
        end ) as $file
    | {update_id: $u.update_id, message_id: $m.message_id, chat_id: $m.chat.id,
       date: ($m.date | todate),
       from: {id: $m.from.id, username: $m.from.username, name: $m.from.first_name},
       text: ($m.text // $m.caption)}
      + (if $u.edited_message then {edited: true} else {} end)
      + (if $file then {file: $file} else {} end)' <<<"$result"

  local count
  count=$(jq 'length' <<<"$result")
  [[ "$count" -lt 100 ]] || echo "NOTE: 100 updates returned; more may be pending — run inbox again" >&2

  if [[ -z "$peek" && "$count" -gt 0 ]]; then
    local max tmp
    max=$(jq 'map(.update_id) | max' <<<"$result")
    if [[ -z "$stored" || "$max" -gt "$stored" ]]; then
      tmp=$(mktemp "$TG_DIR/.offset.XXXXXX")
      printf '%s\n' "$max" >"$tmp"
      mv -f "$tmp" "$OFFSET_FILE"
    fi
  fi
}

cmd_download() {
  [[ $# -eq 1 && -n "$1" ]] || die "download: usage: download <file_id>" 2
  local info fpath fsize uniq base dest tmp code
  load_token   # api runs in a subshell below; the file URL needs the token in this shell too
  info=$(api getFile "$(jq -nc --arg f "$1" '{file_id: $f}')")
  fpath=$(jq -r '.file_path // empty' <<<"$info")
  fsize=$(jq -r '.file_size // 0' <<<"$info")
  uniq=$(jq -r '.file_unique_id // "file"' <<<"$info")
  [[ -n "$fpath" ]] || die "download: getFile returned no file_path (file over 20MB?)" 3
  [[ "$fsize" -le "$DOWNLOAD_MAX" ]] || die "download: $fsize bytes exceeds the 20MB getFile limit" 2
  [[ "$fpath" =~ ^[A-Za-z0-9._/-]+$ ]] || die "download: unexpected file_path from API: $fpath" 3
  [[ "$uniq" =~ ^[A-Za-z0-9_-]+$ ]] || die "download: unexpected file_unique_id from API: $uniq" 3
  base=$(basename "$fpath")
  [[ "$base" != "." && "$base" != ".." ]] || die "download: unexpected file_path from API: $fpath" 3

  mkdir -p "$INBOX_DIR"
  chmod 700 "$INBOX_DIR"
  dest="$INBOX_DIR/${uniq}_${base}"
  tmp=$(mktemp "$INBOX_DIR/.dl.XXXXXX")
  code=$(curl_tg "file/bot$TELEGRAM_BOT_TOKEN/$fpath" "$FILE_TIMEOUT" -o "$tmp" -w '%{http_code}') \
    || { rm -f "$tmp"; exit 4; }
  if [[ "$code" != "200" ]]; then
    rm -f "$tmp"
    die "download: HTTP $code" 3
  fi
  mv -f "$tmp" "$dest"
  printf '%s\n' "$dest"
}

[[ $# -ge 1 ]] || { usage; exit 2; }
cmd="$1"; shift
case "$cmd" in
  me) cmd_me "$@" ;;
  send) cmd_send "$@" ;;
  file) cmd_file "$@" ;;
  edit) cmd_edit "$@" ;;
  react) cmd_react "$@" ;;
  inbox) cmd_inbox "$@" ;;
  download) cmd_download "$@" ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
