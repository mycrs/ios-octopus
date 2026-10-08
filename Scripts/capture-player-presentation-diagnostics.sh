#!/usr/bin/env bash
# Diagnostic collection must never change the app test result.
set -eu
python3 "$(dirname "$0")/capture-player-presentation-diagnostics.py" "$@" || \
  echo "Player UIKit diagnostics unavailable; collector could not complete."
