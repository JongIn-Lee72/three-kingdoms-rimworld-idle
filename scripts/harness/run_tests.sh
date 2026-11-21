#!/usr/bin/env bash
# File: scripts/harness/run_tests.sh
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

mkdir -p reports

if [[ $# -eq 0 ]]; then
    timeout 60s godot --headless --path . -s res://tools/harness/test_runner.gd -- \
        --dir=res://tests \
        --out=reports/test_report.json
else
    HAS_OUT=0
    for arg in "$@"; do
        if [[ "${arg}" == --out=* ]]; then
            HAS_OUT=1
            break
        fi
    done
    if [[ "${HAS_OUT}" -eq 0 ]]; then
        timeout 60s godot --headless --path . -s res://tools/harness/test_runner.gd -- \
            "$@" \
            --out=reports/test_report.json
    else
        timeout 60s godot --headless --path . -s res://tools/harness/test_runner.gd -- "$@"
    fi
fi
