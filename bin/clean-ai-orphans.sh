#!/bin/bash

set -u

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG_FILE="${HOME}/Library/Logs/clean-ai-orphans.log"
DRY_RUN=0
VERBOSE=0
INCLUDE_SHELLS=0
AGGRESSIVE=0
STALE_CODEX_COHORTS=0
STALE_CLAUDE_HELPERS=0
STALE_GENERIC_HELPERS=0
AGGRESSIVE_MIN_AGE_SECONDS=1200
AGGRESSIVE_MAX_CPU_TENTHS=2
AGGRESSIVE_MIN_RSS_KB=120000
STALE_CODEX_MIN_AGE_SECONDS=900
STALE_CODEX_KEEP_PER_FAMILY=2
STALE_CLAUDE_MIN_AGE_SECONDS=900
STALE_CLAUDE_KEEP_PER_FAMILY=2
STALE_GENERIC_MIN_AGE_SECONDS=900
STALE_GENERIC_KEEP_PER_FAMILY=2
STALE_HELPER_MAX_CPU_TENTHS=2
PROCESS_FIXTURE="${CLEAN_AI_ORPHANS_PROCESS_FIXTURE:-}"
PROCESS_CACHE_DIR=""
PROCESS_ROWS_FILE=""
PID_COMMAND_FILE=""

usage() {
  cat <<'EOF'
Usage: clean-ai-orphans.sh [--dry-run] [--verbose] [--include-shells] [--aggressive] [--stale-codex-cohorts] [--stale-claude-helpers] [--stale-generic-helpers]

  --dry-run         Show matching orphan processes without sending signals.
  --verbose         Print detailed logs to stdout in addition to the log file.
  --include-shells  Also evaluate orphan zsh processes that have no TTY and no children.
  --aggressive      Also clean long-lived idle Chromium renderer helpers from known apps.
  --stale-codex-cohorts
                    Also dedupe old Codex app-server helper cohorts while preserving the
                    newest matching cohorts per helper family.
  --stale-claude-helpers
                    Also dedupe old Claude helper cohorts while preserving the
                    newest matching cohorts per helper family.
  --stale-generic-helpers
                    Also dedupe old idle generic helper cohorts such as stale
                    language servers and MCP launchers across apps.
  --help            Show this help message.
EOF
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_line() {
  local line
  line="$(timestamp) $*"
  printf '%s\n' "$line" >>"$LOG_FILE"
  if [ "$VERBOSE" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "$line"
  fi
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

matches_include() {
  case "$1" in
    *claude*|*codex*|*cursor*|*oh-my-codex*|*mcp*|*"uv tool uvx mcp-"*|*mcp-server.cjs*|*state-server.js*|*trace-server.js*|*memory-server.js*|*code-intel-server.js*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

matches_exclude() {
  case "$1" in
    */applications/codex.app/*|*/applications/cursor.app/*|*crashpad_handler*|*shipit*|*vite*|*turbo*|*esbuild*|*agent-browser*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

matches_browser_testing_cleanup() {
  case "$1" in
    *agent-browser-chrome-*"/google chrome for testing.app/contents/macos/google chrome for testing"*|*agent-browser-chrome-*"/google chrome for testing.app/contents/macos/google chrome for testing")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

parent_is_orphan_shell() {
  printf '%s\n' "$ORPHAN_SHELL_PIDS" | grep -qx "$1"
}

shell_has_no_tty() {
  case "$1" in
    "??"|"?"|"-"|"") return 0 ;;
    *) return 1 ;;
  esac
}

child_count() {
  awk -F '\t' -v target="$1" '$2 == target { count++ } END { print count + 0 }' "$PROCESS_ROWS_FILE"
}

etime_to_seconds() {
  awk -v etime="$1" '
    BEGIN {
      days = 0
      hours = 0
      minutes = 0
      seconds = 0
      split(etime, day_parts, "-")
      time_part = etime
      if (length(day_parts) == 2) {
        days = day_parts[1] + 0
        time_part = day_parts[2]
      }
      n = split(time_part, time_parts, ":")
      if (n == 3) {
        hours = time_parts[1] + 0
        minutes = time_parts[2] + 0
        seconds = time_parts[3] + 0
      } else if (n == 2) {
        minutes = time_parts[1] + 0
        seconds = time_parts[2] + 0
      } else if (n == 1) {
        seconds = time_parts[1] + 0
      }
      print (days * 86400) + (hours * 3600) + (minutes * 60) + seconds
    }
  '
}

cpu_to_tenths() {
  awk -v cpu="$1" 'BEGIN { print int((cpu * 10) + 0.5) }'
}

is_idle_enough() {
  local cpu_tenths="$1"
  local rss_kb="$2"
  local age_seconds="$3"

  [ "$cpu_tenths" -le "$AGGRESSIVE_MAX_CPU_TENTHS" ] || return 1
  [ "$rss_kb" -ge "$AGGRESSIVE_MIN_RSS_KB" ] || return 1
  [ "$age_seconds" -ge "$AGGRESSIVE_MIN_AGE_SECONDS" ] || return 1

  return 0
}

is_stale_helper_idle_enough() {
  local cpu_tenths="$1"
  local age_seconds="$2"
  local min_age_seconds="$3"

  [ "$cpu_tenths" -le "$STALE_HELPER_MAX_CPU_TENTHS" ] || return 1
  [ "$age_seconds" -ge "$min_age_seconds" ] || return 1

  return 0
}

matches_aggressive_helper_cleanup() {
  case "$1" in
    */applications/dia.app/*"browser helper (renderer)"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

process_rows() {
  cat "$PROCESS_ROWS_FILE"
}

pid_command_rows() {
  cat "$PID_COMMAND_FILE"
}

is_codex_app_server() {
  case "$1" in
    */applications/codex.app/*"/codex app-server"|*/applications/codex.app/*"/codex app-server "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_claude_app() {
  case "$1" in
    */applications/claude.app/contents/macos/claude|*/applications/claude.app/contents/macos/claude\ *)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

codex_helper_family() {
  local args_lc="$1"

  case "$args_lc" in
    *dist/mcp/trace-server.js*)
      printf 'codex-mcp-trace'
      return 0
      ;;
    *dist/mcp/wiki-server.js*)
      printf 'codex-mcp-wiki'
      return 0
      ;;
    *dist/mcp/state-server.js*)
      printf 'codex-mcp-state'
      return 0
      ;;
    *dist/mcp/memory-server.js*)
      printf 'codex-mcp-memory'
      return 0
      ;;
    *dist/mcp/code-intel-server.js*)
      printf 'codex-mcp-code-intel'
      return 0
      ;;
    *"serena start-mcp-server"*)
      printf 'codex-mcp-serena-launch'
      return 0
      ;;
    *"@upstash/context7-mcp"*)
      printf 'codex-mcp-context7-launch'
      return 0
      ;;
    *"@playwright/mcp"*)
      printf 'codex-mcp-playwright-launch'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

claude_helper_family() {
  local args_lc="$1"
  local parent_cmd_lc="$2"

  case "$parent_cmd_lc" in
    */applications/claude.app/contents/macos/claude*)
      case "$args_lc" in
        *"claude extensions/"*chrome-control/server/index.js*)
          printf 'claude-extension-chrome-control'
          return 0
          ;;
        *"claude extensions/"*osascript/server/index.js*)
          printf 'claude-extension-osascript'
          return 0
          ;;
        *kmsg-mcp.py*)
          printf 'claude-kmsg'
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}

generic_helper_family() {
  local args_lc="$1"

  case "$args_lc" in
    *typescript-language-server|*typescript-language-server\ *)
      printf 'generic-typescript-language-server'
      return 0
      ;;
    */typescript/lib/tsserver.js*)
      printf 'generic-tsserver'
      return 0
      ;;
    */typescript/lib/typingsinstaller.js*)
      printf 'generic-typings-installer'
      return 0
      ;;
    *"@upstash/context7-mcp"*)
      printf 'generic-context7-launch'
      return 0
      ;;
    *"@playwright/mcp"*)
      printf 'generic-playwright-launch'
      return 0
      ;;
    *"serena start-mcp-server"*)
      printf 'generic-serena-launch'
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

build_process_cache() {
  PROCESS_CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clean-ai-orphans.XXXXXX")"
  PROCESS_ROWS_FILE="${PROCESS_CACHE_DIR}/rows.tsv"
  PID_COMMAND_FILE="${PROCESS_CACHE_DIR}/pid-command.tsv"

  if [ -n "$PROCESS_FIXTURE" ]; then
    awk -F '\t' '
      function etime_to_seconds_local(etime,    day_parts, time_parts, days, hours, minutes, seconds, time_part, n) {
        days = 0
        hours = 0
        minutes = 0
        seconds = 0
        split(etime, day_parts, "-")
        time_part = etime
        if (length(day_parts) == 2) {
          days = day_parts[1] + 0
          time_part = day_parts[2]
        }
        n = split(time_part, time_parts, ":")
        if (n == 3) {
          hours = time_parts[1] + 0
          minutes = time_parts[2] + 0
          seconds = time_parts[3] + 0
        } else if (n == 2) {
          minutes = time_parts[1] + 0
          seconds = time_parts[2] + 0
        } else if (n == 1) {
          seconds = time_parts[1] + 0
        }
        return (days * 86400) + (hours * 3600) + (minutes * 60) + seconds
      }
      {
        cpu = $3 + 0
        age_seconds = etime_to_seconds_local($5)
        cpu_tenths = int((cpu * 10) + 0.5)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, age_seconds, cpu_tenths, tolower($7)
      }
    ' "$PROCESS_FIXTURE" >"$PROCESS_ROWS_FILE"
  else
    ps -ax -o pid= -o ppid= -o %cpu= -o rss= -o etime= -o tty= -o command= | awk '
      function etime_to_seconds_local(etime,    day_parts, time_parts, days, hours, minutes, seconds, time_part, n) {
        days = 0
        hours = 0
        minutes = 0
        seconds = 0
        split(etime, day_parts, "-")
        time_part = etime
        if (length(day_parts) == 2) {
          days = day_parts[1] + 0
          time_part = day_parts[2]
        }
        n = split(time_part, time_parts, ":")
        if (n == 3) {
          hours = time_parts[1] + 0
          minutes = time_parts[2] + 0
          seconds = time_parts[3] + 0
        } else if (n == 2) {
          minutes = time_parts[1] + 0
          seconds = time_parts[2] + 0
        } else if (n == 1) {
          seconds = time_parts[1] + 0
        }
        return (days * 86400) + (hours * 3600) + (minutes * 60) + seconds
      }
      {
        pid=$1
        ppid=$2
        cpu=$3
        rss=$4
        etime=$5
        tty=$6
        cmd=""
        for (i=7; i<=NF; i++) {
          cmd = cmd (i == 7 ? "" : " ") $i
        }
        age_seconds = etime_to_seconds_local(etime)
        cpu_tenths = int((cpu * 10) + 0.5)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, cpu, rss, etime, tty, cmd, age_seconds, cpu_tenths, tolower(cmd)
      }
    ' >"$PROCESS_ROWS_FILE"
  fi

  awk -F '\t' '{ print $1 "\t" $7 }' "$PROCESS_ROWS_FILE" >"$PID_COMMAND_FILE"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --include-shells)
      INCLUDE_SHELLS=1
      ;;
    --aggressive)
      AGGRESSIVE=1
      ;;
    --stale-codex-cohorts)
      STALE_CODEX_COHORTS=1
      ;;
    --stale-claude-helpers)
      STALE_CLAUDE_HELPERS=1
      ;;
    --stale-generic-helpers)
      STALE_GENERIC_HELPERS=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p "${HOME}/bin" "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
build_process_cache
trap 'if [ -n "$PROCESS_CACHE_DIR" ] && [ -d "$PROCESS_CACHE_DIR" ]; then rm -rf "$PROCESS_CACHE_DIR"; fi' EXIT

log_line "scan start dry_run=${DRY_RUN} verbose=${VERBOSE} include_shells=${INCLUDE_SHELLS} aggressive=${AGGRESSIVE} stale_codex_cohorts=${STALE_CODEX_COHORTS} stale_claude_helpers=${STALE_CLAUDE_HELPERS} stale_generic_helpers=${STALE_GENERIC_HELPERS}"

ORPHAN_SHELL_PIDS="$(
  process_rows | awk -F '\t' '
    {
      pid=$1
      ppid=$2
      tty=$6
      cmd=$7
      if (ppid == 1 && tty != "??" && cmd ~ /zsh$/) {
        print pid
      }
    }
  '
)"

CODEX_APP_SERVER_PIDS="$(
  pid_command_rows | while IFS=$'\t' read -r pid cmd; do
    cmd_lc="$(to_lower "$cmd")"
    if is_codex_app_server "$cmd_lc"; then
      printf '%s\n' "$pid"
    fi
  done
)"

CLAUDE_APP_PIDS="$(
  pid_command_rows | while IFS=$'\t' read -r pid cmd; do
    cmd_lc="$(to_lower "$cmd")"
    if is_claude_app "$cmd_lc"; then
      printf '%s\n' "$pid"
    fi
  done
)"

candidate_count=0
candidate_pids=()
candidate_desc=()

while IFS=$'\t' read -r pid ppid cpu rss etime tty args age_seconds cpu_tenths args_lc; do
  [ -n "$pid" ] || continue

  exe_path="${args%% *}"
  exe_base="${exe_path##*/}"
  exe_name="$(to_lower "${exe_base#-}")"

  if printf '%s\n' "$args_lc" | grep -Eqi 'gitstatusd-darwin-arm64'; then
    if parent_is_orphan_shell "$ppid"; then
      candidate_pids+=("$pid")
      candidate_desc+=("type=gitstatusd cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
      candidate_count=$((candidate_count + 1))
    fi
    continue
  fi

  if [ "$AGGRESSIVE" -eq 1 ] && matches_aggressive_helper_cleanup "$args_lc"; then
    if is_idle_enough "$cpu_tenths" "$rss" "$age_seconds"; then
      candidate_pids+=("$pid")
      candidate_desc+=("type=aggressive-idle-helper cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
      candidate_count=$((candidate_count + 1))
    fi
    continue
  fi

  [ "$ppid" = "1" ] || continue

  if matches_browser_testing_cleanup "$args_lc"; then
    candidate_pids+=("$pid")
    candidate_desc+=("type=browser-testing cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
    candidate_count=$((candidate_count + 1))
    continue
  fi

  if [ "$INCLUDE_SHELLS" -eq 1 ] && [ "$exe_name" = "zsh" ]; then
    if shell_has_no_tty "$tty" && [ "$(child_count "$pid")" = "0" ]; then
      candidate_pids+=("$pid")
      candidate_desc+=("type=shell cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
      candidate_count=$((candidate_count + 1))
    fi
    continue
  fi

  case "$exe_name" in
    node|python|python3|uv) ;;
    *) continue ;;
  esac

  if ! matches_include "$args_lc"; then
    continue
  fi

  if matches_exclude "$args_lc"; then
    continue
  fi

  candidate_pids+=("$pid")
  candidate_desc+=("type=helper cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
  candidate_count=$((candidate_count + 1))
done < <(process_rows)

if [ "$STALE_CODEX_COHORTS" -eq 1 ] && [ -n "$CODEX_APP_SERVER_PIDS" ]; then
  stale_rows="$(process_rows)"

  stale_candidates="$(
    while IFS=$'\t' read -r pid ppid cpu rss etime tty args age_seconds cpu_tenths args_lc; do
      [ -n "$pid" ] || continue

      if ! printf '%s\n' "$CODEX_APP_SERVER_PIDS" | grep -qx "$ppid"; then
        continue
      fi

      family="$(codex_helper_family "$args_lc")" || continue

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$family" "$age_seconds" "$pid" "$ppid" "$cpu" "$rss" "$etime" "$tty" "$args"
    done <<EOF
$stale_rows
EOF
  )"

  if [ -n "$stale_candidates" ]; then
    stale_dedupe="$(
      printf '%s\n' "$stale_candidates" | sort -t $'\t' -k1,1 -k2,2n | awk -F '\t' -v keep="$STALE_CODEX_KEEP_PER_FAMILY" -v min_age="$STALE_CODEX_MIN_AGE_SECONDS" '
        {
          family = $1
          count[family]++
          line[family, count[family]] = $0
        }
        END {
          for (family in count) {
            for (i = keep + 1; i <= count[family]; i++) {
              split(line[family, i], fields, "\t")
              age = fields[2] + 0
              if (age >= min_age) {
                print line[family, i]
              }
            }
          }
        }
      '
    )"

    while IFS=$'\t' read -r family age_seconds pid ppid cpu rss etime tty args; do
      [ -n "$family" ] || continue
      cpu_tenths="$(cpu_to_tenths "$cpu")"
      if ! is_stale_helper_idle_enough "$cpu_tenths" "$age_seconds" "$STALE_CODEX_MIN_AGE_SECONDS"; then
        continue
      fi
      candidate_pids+=("$pid")
      candidate_desc+=("type=stale-codex-cohort family=${family} cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
      candidate_count=$((candidate_count + 1))
    done <<EOF
$stale_dedupe
EOF
  fi
fi

if [ "$STALE_GENERIC_HELPERS" -eq 1 ]; then
  stale_generic_rows="$(process_rows)"

  stale_generic_candidates="$(
    while IFS=$'\t' read -r pid ppid cpu rss etime tty args age_seconds cpu_tenths args_lc; do
      [ -n "$pid" ] || continue

      if printf '%s\n' "$CODEX_APP_SERVER_PIDS" | grep -qx "$ppid"; then
        continue
      fi
      if printf '%s\n' "$CLAUDE_APP_PIDS" | grep -qx "$ppid"; then
        continue
      fi

      family="$(generic_helper_family "$args_lc" || true)"
      [ -n "$family" ] || continue

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$family" "$age_seconds" "$pid" "$ppid" "$cpu" "$rss" "$etime" "$tty" "$args"
    done <<EOF
$stale_generic_rows
EOF
  )"

  if [ -n "$stale_generic_candidates" ]; then
    stale_generic_dedupe="$(
      printf '%s\n' "$stale_generic_candidates" | sort -t $'\t' -k1,1 -k2,2n | awk -F '\t' -v keep="$STALE_GENERIC_KEEP_PER_FAMILY" -v min_age="$STALE_GENERIC_MIN_AGE_SECONDS" '
        {
          family = $1
          count[family]++
          line[family, count[family]] = $0
        }
        END {
          for (family in count) {
            for (i = keep + 1; i <= count[family]; i++) {
              split(line[family, i], fields, "\t")
              age = fields[2] + 0
              if (age >= min_age) {
                print line[family, i]
              }
            }
          }
        }
      '
    )"

    while IFS=$'\t' read -r family age_seconds pid ppid cpu rss etime tty args; do
      [ -n "$family" ] || continue
      cpu_tenths="$(cpu_to_tenths "$cpu")"
      if ! is_stale_helper_idle_enough "$cpu_tenths" "$age_seconds" "$STALE_GENERIC_MIN_AGE_SECONDS"; then
        continue
      fi
      candidate_pids+=("$pid")
      candidate_desc+=("type=stale-generic-helper family=${family} cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
      candidate_count=$((candidate_count + 1))
    done <<EOF
$stale_generic_dedupe
EOF
  fi
fi

if [ "$STALE_CLAUDE_HELPERS" -eq 1 ] && [ -n "$CLAUDE_APP_PIDS" ]; then
  stale_claude_rows="$(process_rows)"

  stale_claude_candidates="$(
    while IFS=$'\t' read -r pid ppid cpu rss etime tty args age_seconds cpu_tenths args_lc; do
      [ -n "$pid" ] || continue

      if ! printf '%s\n' "$CLAUDE_APP_PIDS" | grep -qx "$ppid"; then
        continue
      fi

      family="$(claude_helper_family "$args_lc" '/applications/claude.app/contents/macos/claude' || true)"
      [ -n "$family" ] || continue

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$family" "$age_seconds" "$pid" "$ppid" "$cpu" "$rss" "$etime" "$tty" "$args"
    done <<EOF
$stale_claude_rows
EOF
  )"

  if [ -n "$stale_claude_candidates" ]; then
    stale_claude_dedupe="$(
      printf '%s\n' "$stale_claude_candidates" | sort -t $'\t' -k1,1 -k2,2n | awk -F '\t' -v keep="$STALE_CLAUDE_KEEP_PER_FAMILY" -v min_age="$STALE_CLAUDE_MIN_AGE_SECONDS" '
        {
          family = $1
          count[family]++
          line[family, count[family]] = $0
        }
        END {
          for (family in count) {
            for (i = keep + 1; i <= count[family]; i++) {
              split(line[family, i], fields, "\t")
              age = fields[2] + 0
              if (age >= min_age) {
                print line[family, i]
              }
            }
          }
        }
      '
    )"

    while IFS=$'\t' read -r family age_seconds pid ppid cpu rss etime tty args; do
      [ -n "$family" ] || continue
      cpu_tenths="$(cpu_to_tenths "$cpu")"
      if ! is_stale_helper_idle_enough "$cpu_tenths" "$age_seconds" "$STALE_CLAUDE_MIN_AGE_SECONDS"; then
        continue
      fi
      candidate_pids+=("$pid")
      candidate_desc+=("type=stale-claude-helper family=${family} cpu=${cpu} rss=${rss} etime=${etime} tty=${tty:-none} cmd=$args")
      candidate_count=$((candidate_count + 1))
    done <<EOF
$stale_claude_dedupe
EOF
  fi
fi

if [ "$candidate_count" -eq 0 ]; then
  log_line "scan complete candidates=0"
  exit 0
fi

i=0
while [ "$i" -lt "$candidate_count" ]; do
  log_line "candidate pid=${candidate_pids[$i]} ${candidate_desc[$i]}"
  i=$((i + 1))
done

if [ "$DRY_RUN" -eq 1 ]; then
  log_line "dry-run complete candidates=${candidate_count}"
  exit 0
fi

i=0
while [ "$i" -lt "$candidate_count" ]; do
  pid="${candidate_pids[$i]}"
  if kill -0 "$pid" 2>/dev/null; then
    if kill -TERM "$pid" 2>/dev/null; then
      log_line "signal=TERM pid=${pid} result=sent"
    else
      log_line "signal=TERM pid=${pid} result=failed"
    fi
  else
    log_line "signal=TERM pid=${pid} result=already-exited"
  fi
  i=$((i + 1))
done

sleep 3

i=0
while [ "$i" -lt "$candidate_count" ]; do
  pid="${candidate_pids[$i]}"
  if kill -0 "$pid" 2>/dev/null; then
    if kill -KILL "$pid" 2>/dev/null; then
      log_line "signal=KILL pid=${pid} result=sent"
    else
      log_line "signal=KILL pid=${pid} result=failed"
    fi
  else
    log_line "signal=TERM pid=${pid} result=exited-after-term"
  fi
  i=$((i + 1))
done

log_line "scan complete candidates=${candidate_count}"
