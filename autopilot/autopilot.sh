#!/usr/bin/env bash
#
# autopilot.sh  —  unattended Claude Code driver loop for Replog
#
# What it does:
#   * Re-invokes `claude -p` fresh each iteration (durable state lives in
#     autopilot/PROGRESS.md + autopilot/BACKLOG.md, NOT in a single session).
#   * Runs on a dedicated autopilot branch so `development` is never touched.
#   * Uses Fable 5 as primary; on a usage/rate limit it switches to Opus 4.8,
#     and if that is also exhausted it stops cleanly.
#   * Times out each iteration so a stuck run cannot hang forever.
#   * Logs every iteration to autopilot/logs/ for you to review later.
#
# Before first run:
#   1. Open an interactive `claude` in the repo, type /model, and note the
#      EXACT model names available on your plan. Put them in PRIMARY_MODEL /
#      FALLBACK_MODEL below (aliases like `opus` may work; confirm first).
#   2. macOS has no `timeout` by default: `brew install coreutils` (gives
#      gtimeout), which this script auto-detects.
#   3. Set PROJECT_DIR to your Replog package root.
#   4. chmod +x autopilot.sh
#
# Launch:  ./autopilot.sh        (then close the lid settings so the Mac stays awake)
# Stop early: create the file autopilot/STOP in the repo, or Ctrl-C.

set -uo pipefail

# ---- config (edit these) --------------------------------------------------
PROJECT_DIR="/Volumes/mac-ssd/Projects/Project-Replog/Replog"
PRIMARY_MODEL="claude-fable-5"      # Fable 5 (verified: this session's model ID)
FALLBACK_MODEL="claude-opus-4-8"    # Opus 4.8 (verified model ID)
MAX_HOURS=4                 # wall-clock budget for the whole run
ITER_TIMEOUT="30m"          # hard cap per iteration
BACKOFF_SECONDS=60          # pause after a non-zero, non-limit exit
# ---------------------------------------------------------------------------

BRIEF="${PROJECT_DIR}/autopilot/AUTOPILOT.md"
LOG_DIR="${PROJECT_DIR}/autopilot/logs"
STOP_FILE="${PROJECT_DIR}/autopilot/STOP"
BRANCH="autopilot/$(date +%Y%m%d-%H%M)"

# pick timeout or gtimeout, tolerate neither
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

cd "${PROJECT_DIR}" || { echo "[autopilot] bad PROJECT_DIR"; exit 1; }
mkdir -p "${LOG_DIR}"
[ -f "${BRIEF}" ] || { echo "[autopilot] missing ${BRIEF}"; exit 1; }
rm -f "${STOP_FILE}"

# start from a clean, up-to-date development branch, then branch off it
git checkout development           || { echo "[autopilot] cannot checkout development"; exit 1; }
git pull --ff-only 2>/dev/null || true
git checkout -b "${BRANCH}"        || { echo "[autopilot] cannot create ${BRANCH}"; exit 1; }
echo "[autopilot] working on branch ${BRANCH}"

MODEL="${PRIMARY_MODEL}"
END=$(( $(date +%s) + MAX_HOURS * 3600 ))
i=0

run_claude () {
  # $1 = logfile
  if [ -n "${TIMEOUT_BIN}" ]; then
    "${TIMEOUT_BIN}" "${ITER_TIMEOUT}" \
      claude -p "$(cat "${BRIEF}")" \
        --model "${MODEL}" \
        --dangerously-skip-permissions \
        --output-format stream-json --verbose \
        > "$1" 2>&1
  else
    claude -p "$(cat "${BRIEF}")" \
      --model "${MODEL}" \
      --dangerously-skip-permissions \
      --output-format stream-json --verbose \
      > "$1" 2>&1
  fi
}

while [ "$(date +%s)" -lt "${END}" ]; do
  [ -f "${STOP_FILE}" ] && { echo "[autopilot] STOP file found, exiting"; break; }

  i=$(( i + 1 ))
  ts="$(date +%Y%m%d-%H%M%S)"
  log="${LOG_DIR}/iter-${i}-${ts}.jsonl"
  echo "[autopilot] iter ${i}  model=${MODEL}  ${ts}"

  run_claude "${log}"
  code=$?

  # timeout
  if [ "${code}" -eq 124 ]; then
    echo "[autopilot] iter ${i} timed out; continuing"
    continue
  fi

  # usage / rate limit -> fall back once, then stop
  if grep -qiE "rate_limit_error|overloaded_error|usage limit reached|limit reached|out of credit|credit balance" "${log}"; then
    if [ "${MODEL}" = "${PRIMARY_MODEL}" ]; then
      echo "[autopilot] ${PRIMARY_MODEL} limit hit -> switching to ${FALLBACK_MODEL}"
      MODEL="${FALLBACK_MODEL}"
      sleep 30
      continue
    else
      echo "[autopilot] ${FALLBACK_MODEL} limit also hit -> stopping"
      break
    fi
  fi

  # other failure -> back off, keep going
  if [ "${code}" -ne 0 ]; then
    echo "[autopilot] iter ${i} exit ${code}; backing off ${BACKOFF_SECONDS}s"
    sleep "${BACKOFF_SECONDS}"
  fi
done

echo "[autopilot] done. review with:  git -C '${PROJECT_DIR}' log --oneline ${BRANCH}"
echo "[autopilot] diff vs development: git -C '${PROJECT_DIR}' diff development..${BRANCH}"
