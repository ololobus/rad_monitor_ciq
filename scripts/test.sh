#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
./scripts/build.sh test
# SDK 9.2.0 on this Mac returns 1 even when its native report says PASSED.
# Require the explicit successful report; never swallow a failed/empty test run.
status=0
output="$(monkeydo bin/rad_monitor-tests.prg instinct3solar45mm -t 2>&1)" || status=$?
printf '%s\n' "$output"
if [[ "$output" =~ PASSED\ \(passed=[0-9]+,\ failed=0,\ errors=0\) ]] && [[ "$status" -le 1 ]]; then
  exit 0
fi
if [[ "$status" -eq 0 ]]; then exit 1; fi
exit "$status"
