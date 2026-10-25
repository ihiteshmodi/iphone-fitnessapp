#!/bin/bash
# Runs the simulator UI tests in YOUR terminal with a live progress bar.
#
#   scripts/run-ui-tests.sh                      # all three classes, one after another
#   scripts/run-ui-tests.sh WorkoutFlowUITests   # a single class
#
# The bottom line redraws every 2 seconds, so you can tell it is alive:
#   [██████░░░░░░░░░░░░░░░░░░] 3/11 tests  testing  running: testOpenExercise  02:41 ⠹
# Every finished test prints a ✓ or ✗ line above it. If the log goes quiet for a minute a warning appears.
# Press Ctrl-C at any time: it stops xcodebuild and shuts the simulator down.
# Gentle on the Mac: low CPU priority, one class at a time, hard per-test and per-class time limits.
set -u
cd "$(dirname "$0")/.."

UDID="${SIM_UDID:-8DD81A59-E276-47FB-9BA4-86566EC0972B}"   # iPhone 17
CLASS_LIMIT_SECONDS="${CLASS_LIMIT_SECONDS:-600}"
QUIET_WARNING_SECONDS=60
BAR_WIDTH=24
LOGS=".uitest-logs"
mkdir -p "$LOGS"

# The simulator cannot read ~/Desktop, so the seed database is staged in /Users/Shared (see appUITests/UITestSeed.swift).
cp output/fitness.sqlite /Users/Shared/fitness-ui-seed.sqlite

build_pid=""
stop_everything() {
  [ -n "$build_pid" ] && kill "$build_pid" 2>/dev/null
  xcrun simctl shutdown all >/dev/null 2>&1
  printf '\r\033[K\nstopped. simulator shut down.\n'
}
trap 'stop_everything; exit 130' INT TERM
trap 'xcrun simctl shutdown all >/dev/null 2>&1' EXIT

classes=(WorkoutFlowUITests BodyProgressUITests MorePlanDataUITests)
[ $# -gt 0 ] && classes=("$1")

total=0
for name in "${classes[@]}"; do total=$((total + $(grep -cE '^\s*func test' "appUITests/$name.swift"))); done
done_count=0
failed_count=0
failed_names=""
current_test=""
phase="building"
spinner=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
tick=0

bar() {
  local filled=0 i out=""
  [ "$total" -gt 0 ] && filled=$((done_count * BAR_WIDTH / total))
  for ((i = 0; i < BAR_WIDTH; i++)); do
    if [ "$i" -lt "$filled" ]; then out+="█"; else out+="░"; fi
  done
  printf '%s' "$out"
}

clock() { printf '%02d:%02d' $(($1 / 60)) $(($1 % 60)); }

draw() {  # $1 = seconds since start, $2 = seconds the log has been quiet
  local line
  line=$(printf '[%s] %d/%d tests  %s' "$(bar)" "$done_count" "$total" "$phase")
  [ -n "$current_test" ] && line+="  running: $current_test"
  line+=$(printf '  %s %s' "$(clock "$1")" "${spinner[$((tick % 10))]}")
  [ "$failed_count" -gt 0 ] && line+="  ✗$failed_count"
  [ "$2" -ge "$QUIET_WARNING_SECONDS" ] && line+="  ⚠ no output for $(clock "$2"), Ctrl-C to stop"
  printf '\r\033[K%s' "$line"
}

handle_line() {  # prints finished tests above the progress line
  local line="$1"
  if [[ "$line" =~ Test\ Case\ \'-\[FitnessAppUITests\.[A-Za-z]+\ ([A-Za-z0-9_]+)\]\'\ (started|passed|failed)(\ \(([0-9.]+)\ seconds\))? ]]; then
    local test="${BASH_REMATCH[1]}" state="${BASH_REMATCH[2]}" secs="${BASH_REMATCH[4]:-}"
    phase="testing"
    case "$state" in
      started) current_test="$test" ;;
      passed)  done_count=$((done_count + 1)); current_test=""; printf '\r\033[K  ✓ %s (%ss)\n' "$test" "$secs" ;;
      failed)  done_count=$((done_count + 1)); failed_count=$((failed_count + 1)); failed_names+=" $test"; current_test=""
               printf '\r\033[K  ✗ %s (%ss)\n' "$test" "$secs" ;;
    esac
  elif [[ "$line" == *"error:"* ]]; then
    printf '\r\033[K  ! %s\n' "$(printf '%s' "$line" | cut -c1-160)"
  fi
}

overall_start=$(date +%s)
status=0
echo "UI tests: $total tests in ${#classes[@]} class(es). Ctrl-C stops everything."

for name in "${classes[@]}"; do
  log="$LOGS/$name.log"
  rm -rf "$LOGS/$name.xcresult"; : >"$log"
  printf '\n== %s   started %s   (full log: %s)\n' "$name" "$(date +%H:%M:%S)" "$log"
  phase="building"; current_test=""

  nice -n 10 xcodebuild test -project FitnessApp.xcodeproj -scheme FitnessApp \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath .derived \
    -only-testing:"FitnessAppUITests/$name" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 180 \
    -resultBundlePath "$LOGS/$name.xcresult" >"$log" 2>&1 &
  build_pid=$!

  class_start=$(date +%s); seen=0; last_size=0; last_growth=$class_start
  while kill -0 "$build_pid" 2>/dev/null; do
    sleep 2
    tick=$((tick + 1))
    now=$(date +%s)

    size=$(stat -f%z "$log" 2>/dev/null || echo 0)
    if [ "$size" -ne "$last_size" ]; then last_size=$size; last_growth=$now; fi

    total_lines=$(wc -l <"$log")
    if [ "$total_lines" -gt "$seen" ]; then
      while IFS= read -r line; do handle_line "$line"; done < <(tail -n +"$((seen + 1))" "$log")
      seen=$total_lines
    fi

    draw $((now - overall_start)) $((now - last_growth))

    if [ $((now - class_start)) -ge "$CLASS_LIMIT_SECONDS" ]; then
      printf '\r\033[K  TIMED OUT after %ss, stopping this class\n' "$CLASS_LIMIT_SECONDS"
      kill "$build_pid" 2>/dev/null
      failed_count=$((failed_count + 1)); failed_names+=" (timeout:$name)"
      break
    fi
  done

  wait "$build_pid" 2>/dev/null; code=$?
  build_pid=""
  # Pick up any lines written between the last poll and the process exiting.
  total_lines=$(wc -l <"$log")
  if [ "$total_lines" -gt "$seen" ]; then
    while IFS= read -r line; do handle_line "$line"; done < <(tail -n +"$((seen + 1))" "$log")
  fi
  [ "$code" -ne 0 ] && status=1
  printf '\r\033[K== %s finished in %s, exit code %s\n' "$name" "$(clock $(($(date +%s) - class_start)))" "$code"
done

printf '\n'
if [ "$status" -eq 0 ] && [ "$failed_count" -eq 0 ]; then
  echo "ALL $done_count UI TESTS PASSED  ($(clock $(($(date +%s) - overall_start))))"
else
  echo "FAILED: $failed_count  (${failed_names# })   details: $LOGS/"
  status=1
fi
exit $status
