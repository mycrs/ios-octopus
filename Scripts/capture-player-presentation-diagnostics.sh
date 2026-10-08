#!/usr/bin/env bash
# Only the fixed, content-free player UIKit state messages enter CI artifacts.
set -eu
task_device="$1"
task_output="$2"
if [ -f "$task_output" ]; then
  exit 0
fi
task_predicate='process == "Octopus" AND subsystem == "com.octopus.iptv" AND category == "ui" AND (eventMessage BEGINSWITH "Player dismissal +2s" OR eventMessage BEGINSWITH "Player dismissal tabSelection" OR eventMessage BEGINSWITH "Player orientation request failed")'
if xcrun simctl spawn "$task_device" log show --last 20m --style compact --info --debug \
  --predicate "$task_predicate" > "$task_output.tmp"; then
  mv "$task_output.tmp" "$task_output"
else
  rm -f "$task_output.tmp"
  echo "Player UIKit diagnostics unavailable for this simulator."
fi
