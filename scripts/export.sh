#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-}"
if [[ "$target" == all ]]; then
  for variant in app-production app-beta field-production field-beta; do
    "$0" "$variant"
  done
  exit 0
fi

case "$target" in
  app-production)
    jungle="monkey.jungle"
    output="dist/rad_monitor-app-production.iq"
    ;;
  app-beta)
    jungle="monkey-beta.jungle"
    output="dist/rad_monitor-app-beta.iq"
    ;;
  field-production)
    jungle="datafield/monkey.jungle"
    output="dist/rad_monitor-field-production.iq"
    ;;
  field-beta)
    jungle="datafield/monkey-beta.jungle"
    output="dist/rad_monitor-field-beta.iq"
    ;;
  *)
    echo "Usage: $0 {app-production|app-beta|field-production|field-beta|all}" >&2
    exit 2
    ;;
esac

./scripts/build.sh "$target"
source scripts/env.sh
mkdir -p dist
key="${CIQ_DEVELOPER_KEY:-$PWD/.keys/developer_key.der}"
monkeyc -e -r -f "$jungle" -y "$key" -o "$output" -w
echo "Exported $output"
