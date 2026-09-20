#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
monkeydo bin/rad_monitor.prg instinct3solar45mm
