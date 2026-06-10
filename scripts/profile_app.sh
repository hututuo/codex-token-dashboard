#!/usr/bin/env bash
set -euo pipefail

DURATION="${1:-10}"
INTERVAL_MS="${2:-2}"
COUNTDOWN="${PROFILE_COUNTDOWN:-3}"
APP_PROCESS="${PROFILE_APP_PROCESS:-CodexTokenBar}"
OPEN_RESULT="${PROFILE_OPEN_RESULT:-1}"
USE_XCTRACE="${PROFILE_XCTRACE:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$ROOT_DIR/runs/$(date +%Y%m%d-%H%M%S)_scroll-profile"
mkdir -p "$RUN_DIR"

PID="$(pgrep -x "$APP_PROCESS" | head -n 1 || true)"
if [[ -z "$PID" ]]; then
  echo "Could not find a running $APP_PROCESS process."
  echo "Run scripts/package_app.sh debug first, then rerun this profiler."
  exit 1
fi

SAMPLE_OUT="$RUN_DIR/sample.txt"
SUMMARY_OUT="$RUN_DIR/summary.md"
TRACE_OUT="$RUN_DIR/time-profiler.trace"

cat > "$RUN_DIR/metadata.txt" <<EOF
date: $(date '+%Y-%m-%d %H:%M:%S %Z')
process: $APP_PROCESS
pid: $PID
duration_seconds: $DURATION
sample_interval_ms: $INTERVAL_MS
xctrace: $USE_XCTRACE
EOF

ps -p "$PID" -o pid,ppid,stat,%cpu,%mem,etime,comm,args > "$RUN_DIR/ps-before.txt"

echo "Profiling $APP_PROCESS pid=$PID"
echo "In $COUNTDOWN seconds, scroll the first page until sampling finishes."
for ((remaining = COUNTDOWN; remaining > 0; remaining--)); do
  echo "  $remaining..."
  sleep 1
done

echo "Sampling for ${DURATION}s..."
/usr/bin/sample "$PID" "$DURATION" "$INTERVAL_MS" -mayDie -fullPaths -file "$SAMPLE_OUT"

if [[ "$USE_XCTRACE" == "1" ]]; then
  echo "Recording Time Profiler trace for ${DURATION}s..."
  if /usr/bin/xctrace record \
    --quiet \
    --no-prompt \
    --template "Time Profiler" \
    --attach "$PID" \
    --time-limit "${DURATION}s" \
    --output "$TRACE_OUT" > "$RUN_DIR/xctrace.log" 2>&1; then
    echo "xctrace saved to $TRACE_OUT"
  else
    echo "xctrace failed; see $RUN_DIR/xctrace.log" | tee -a "$RUN_DIR/metadata.txt"
  fi
fi

ps -p "$PID" -o pid,ppid,stat,%cpu,%mem,etime,comm,args > "$RUN_DIR/ps-after.txt" || true

{
  echo "# Codex Token Bar Scroll Profile"
  echo
  echo "- Captured: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "- PID: \`$PID\`"
  echo "- Duration: \`${DURATION}s\`"
  echo "- Sample interval: \`${INTERVAL_MS}ms\`"
  echo
  echo "## How To Read"
  echo
  echo "- If the hot stack is mostly \`NSHostingView.layout\`, \`ViewGraphRootValueUpdater\`, \`DisplayList.ViewUpdater\`, or \`AttributeGraph\`, the bottleneck is SwiftUI layout/display-list invalidation."
  echo "- If project frames such as \`TokenHeatmap\`, \`RecentUsageChart\`, \`LiveRateView\`, or \`AccountQuota\` appear high in the stack, that view is still doing work during scroll."
  echo "- If stacks are mostly \`sqlite3\`, \`JSONDecoder\`, or file I/O, the issue is data refresh leaking into the scroll path."
  echo
  echo "## Process Snapshot"
  echo
  echo '```'
  cat "$RUN_DIR/ps-before.txt"
  echo '```'
  echo
  echo "## Relevant Frames"
  echo
  echo '```'
  rg -n -C 2 "DashboardView|LiveRateView|TokenHeatmap|RecentUsageChart|CacheHitRanking|AccountQuota|TokenDisplay|SwiftUI|SwiftUICore|AppKit|QuartzCore|AttributeGraph|sqlite3|JSONDecoder" "$SAMPLE_OUT" | head -n 260 || true
  echo '```'
  echo
  echo "## Layout / Display Markers"
  echo
  echo '```'
  rg -n "NSHostingView\\.layout|ViewGraphRootValueUpdater|DisplayList\\.ViewUpdater|AttributeGraph|NSDisplayCycleFlush|layoutSubtree|CA::Transaction|draw|display" "$SAMPLE_OUT" | head -n 220 || true
  echo '```'
  echo
  echo "## Files"
  echo
  echo "- Raw sample: \`$SAMPLE_OUT\`"
  if [[ "$USE_XCTRACE" == "1" && -d "$TRACE_OUT" ]]; then
    echo "- Time Profiler trace: \`$TRACE_OUT\`"
  fi
} > "$SUMMARY_OUT"

echo
echo "Profile saved:"
echo "  $SUMMARY_OUT"
echo "  $SAMPLE_OUT"

if [[ "$OPEN_RESULT" == "1" ]]; then
  open "$RUN_DIR"
fi
