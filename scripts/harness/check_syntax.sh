#!/usr/bin/env bash
# File: scripts/harness/check_syntax.sh
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

echo "=== [Stage 1.1] Refreshing Godot 4 Global Class Cache ==="
timeout 30s godot --headless --path . --import --quit

echo "=== [Stage 1.2] Static GDScript Syntax & Strict Type Checking ==="
FAIL=0
CHECKED_COUNT=0
SEARCH_DIRS=()
for d in ./src ./tests ./tools; do
    if [[ -d "${d}" ]]; then
        SEARCH_DIRS+=("${d}")
    fi
done

if [[ ${#SEARCH_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: None of ./src, ./tests, ./tools directories exist." >&2
    exit 1
fi

while IFS= read -r -d '' gd_file; do
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
    rel_path="res://${gd_file#./}"
    OUTPUT=$(timeout 15s godot --headless --path . --check-only -s "${rel_path}" 2>&1) || {
        echo "SYNTAX/TYPE FAIL in ${rel_path}:"
        echo "${OUTPUT}"
        FAIL=1
        continue
    }
    if echo "${OUTPUT}" | grep -E "SCRIPT ERROR:|Parse Error:|USER ERROR:" >/dev/null; then
        echo "ERROR DETECTED in ${rel_path}:"
        echo "${OUTPUT}"
        FAIL=1
    fi
done < <(find "${SEARCH_DIRS[@]}" -name "*.gd" -print0 | sort -z)

if [[ "${CHECKED_COUNT}" -eq 0 ]]; then
    echo "ERROR: No .gd files found to check." >&2
    exit 1
fi
echo "Checked ${CHECKED_COUNT} GDScript file(s)."

echo "=== [Stage 1.3] Validating JSON Data & SQLite Schema ==="
timeout 20s godot --headless --path . -s res://tools/harness/validate_data.gd -- --strict || FAIL=1
/usr/bin/sqlite3 :memory: < data/schemas/world_state_schema.sql || FAIL=1

if [[ "${FAIL}" -ne 0 ]]; then
    echo "STAGE 1 FAILED: Static syntax, type, or schema errors detected."
    exit 1
fi
echo "STAGE 1 PASSED: All ${CHECKED_COUNT} GDScript files, JSON data, and SQLite schemas valid."
