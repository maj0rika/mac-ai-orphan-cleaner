#!/bin/bash

set -u

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG_FILE="${HOME}/Library/Logs/clean-ai-orphans.log"
DRY_RUN=0
VERBOSE=0
INCLUDE_SHELLS=0
AGGRESSIVE=0
AGGRESSIVE_MIN_AGE_SECONDS=1200
AGGRESSIVE_MAX_CPU_TENTHS=2
AGGRESSIVE_MIN_RSS_KB=120000

usage() {
  cat <<'EOF'
Usage: clean-ai-orphans.sh [--dry-run] [--verbose] [--include-shells] [--aggressive]

  --dry-run         Show matching orphan processes without sending signals.
  --verbose         Print detailed logs to stdout in addition to the log file.
  --include-shells  Also evaluate orphan zsh processes that have no TTY and no children.
  --aggressive      Also clean long-lived idle Chromium renderer helpers from known apps.
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
  printf '%s\n' "$1" | grep -Eqi 'claude|codex|cursor|oh-my-codex|mcp|uv tool uvx mcp-|mcp-server\.cjs|state-server\.js|trace-server\.js|memory-server\.js|code-intel-server\.js'
}

matches_exclude() {
  printf '%s\n' "$1" | grep -Eqi '/applications/codex\.app/|/applications/cursor\.app/|crashpad_handler|shipit|vite|turbo|esbuild|agent-browser'
}

matches_browser_testing_cleanup() {
  printf '%s\n' "$1" | grep -Eqi 'agent-browser-chrome-' &&
    printf '%s\n' "$1" | grep -Eqi '/google chrome for testing\.app/contents/macos/google chrome for testing([[:space:]]|$)'
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
  pgrep -P "$1" 2>/dev/null | wc -l | tr -d ' '
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

matches_aggressive_helper_cleanup() {
  printf '%s\n' "$1" | grep -Eqi '/applications/dia\.app/.+browser helper \(renderer\)'
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

log_line "scan start dry_run=${DRY_RUN} verbose=${VERBOSE} include_shells=${INCLUDE_SHELLS} aggressive=${AGGRESSIVE}"

ORPHAN_SHELL_PIDS="$(
  ps -ax -o pid= -o ppid= -o tty= -o command= | awk '
    {
      pid=$1
      ppid=$2
      tty=$3
      cmd=$4
      if (ppid == 1 && tty != "??" && cmd ~ /zsh$/) {
        print pid
      }
    }
  '
)"

candidate_count=0
candidate_pids=()
candidate_desc=()

while IFS=$'\t' read -r pid ppid cpu rss etime tty args; do
  [ -n "$pid" ] || continue

  exe_path="${args%% *}"
  exe_base="${exe_path##*/}"
  exe_name="$(to_lower "${exe_base#-}")"
  args_lc="$(to_lower "$args")"
  cpu_tenths="$(cpu_to_tenths "$cpu")"
  age_seconds="$(etime_to_seconds "$etime")"

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
done < <(
  ps -ax -o pid= -o ppid= -o %cpu= -o rss= -o etime= -o tty= -o command= | awk '
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
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, cpu, rss, etime, tty, cmd
    }
  '
)

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
