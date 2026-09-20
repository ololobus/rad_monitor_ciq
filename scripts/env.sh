#!/bin/bash
# Source this file from the repository root (build.sh does this for you).
set -euo pipefail
if [[ -z "${CIQ_SDK:-}" ]]; then
  cfg="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
  [[ -f "$cfg" ]] || { echo 'Install Connect IQ SDK using Garmin SDK Manager, or set CIQ_SDK.' >&2; exit 1; }
  CIQ_SDK="$(cat "$cfg")"
fi
if [[ -z "${JAVA_HOME:-}" ]]; then
  for runtime in "$PWD"/.tools/jdk-*/Contents/Home; do
    if [[ -x "$runtime/bin/java" ]]; then JAVA_HOME="$runtime"; break; fi
  done
fi
if [[ -n "${JAVA_HOME:-}" ]]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
export CIQ_SDK
export PATH="$CIQ_SDK/bin:$PATH"
java -version 2>&1 | head -1
