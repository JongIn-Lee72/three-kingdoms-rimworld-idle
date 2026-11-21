#!/usr/bin/env bash
# File: scripts/harness/run_sim.sh
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

mkdir -p reports
timeout 60s godot --headless --path . -s res://tools/harness/sim_harness.gd -- "$@"
