#!/usr/bin/env python3
"""Stage 4 SQLite Forensic Audit Verifier (FH-06)."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from typing import Any, Dict, List

CANONICAL_TABLES: List[str] = [
    "world_meta",
    "factions",
    "macro_nodes",
    "persona_import_challenges",
    "players",
    "manors",
    "pawns_officers",
    "armies_caravans",
    "market_orders",
    "command_audit_log",
]


def add_check(
    checks: List[Dict[str, Any]],
    failures: List[str],
    name: str,
    passed: bool,
    details: Any = None,
) -> None:
    checks.append({"name": name, "passed": bool(passed), "details": details})
    if not passed:
        failures.append(f"{name}: {details}")


def verify_db(db_path: str) -> Dict[str, Any]:
    checks: List[Dict[str, Any]] = []
    failures: List[str] = []
    table_counts: Dict[str, int] = {}

    if not os.path.isfile(db_path):
        add_check(checks, failures, "db_file_exists", False, f"Missing DB file: {db_path}")
        return {
            "schema_version": "1.0",
            "db_path": os.path.abspath(db_path),
            "checks": checks,
            "failures": failures,
            "overall_passed": False,
        }

    add_check(checks, failures, "db_file_exists", True, os.path.abspath(db_path))

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute("PRAGMA foreign_keys = ON;")

        # 1. Foreign key check & SQLite integrity check
        fk_rows = [tuple(r) for r in cur.execute("PRAGMA foreign_key_check;").fetchall()]
        add_check(
            checks,
            failures,
            "pragma_foreign_key_check",
            len(fk_rows) == 0,
            {"violations": fk_rows},
        )

        int_rows = [str(r[0]) for r in cur.execute("PRAGMA integrity_check;").fetchall()]
        add_check(
            checks,
            failures,
            "pragma_integrity_check",
            int_rows == ["ok"],
            {"output": int_rows},
        )

        # 2. All 10 canonical tables exist
        existing_tables = {
            str(r[0])
            for r in cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table';"
            ).fetchall()
        }
        missing_tables = [t for t in CANONICAL_TABLES if t not in existing_tables]
        add_check(
            checks,
            failures,
            "canonical_tables_exist",
            len(missing_tables) == 0,
            {"missing": missing_tables, "expected": len(CANONICAL_TABLES)},
        )
        if missing_tables:
            return {
                "schema_version": "1.0",
                "db_path": os.path.abspath(db_path),
                "checks": checks,
                "failures": failures,
                "overall_passed": False,
            }

        for tbl in CANONICAL_TABLES:
            table_counts[tbl] = int(cur.execute(f"SELECT COUNT(*) FROM {tbl};").fetchone()[0])

        # 3. world_meta: 1 row, current_tick_id >= 24, state_crc32 != 0
        wm_rows = cur.execute("SELECT * FROM world_meta;").fetchall()
        wm_ok = (
            len(wm_rows) == 1
            and int(wm_rows[0]["current_tick_id"]) >= 24
            and int(wm_rows[0]["state_crc32"]) != 0
        )
        wm_detail = (
            {
                "row_count": len(wm_rows),
                "current_tick_id": int(wm_rows[0]["current_tick_id"]) if wm_rows else None,
                "state_crc32": int(wm_rows[0]["state_crc32"]) if wm_rows else None,
            }
            if wm_rows
            else {"row_count": 0}
        )
        add_check(checks, failures, "world_meta_valid", wm_ok, wm_detail)

        # 4. players & persona_import_challenges
        players_cnt = table_counts["players"]
        add_check(checks, failures, "players_min_count", players_cnt >= 3, {"count": players_cnt})

        fusion_rows = cur.execute(
            """
            SELECT p.player_id, p.persona_challenge_id, c.status AS challenge_status
            FROM players p
            JOIN persona_import_challenges c ON p.persona_challenge_id = c.challenge_id
            WHERE p.creation_mode = 'FUSION_INTERVIEW'
              AND p.persona_challenge_id IS NOT NULL
              AND c.status = 'CONSUMED';
            """
        ).fetchall()
        add_check(
            checks,
            failures,
            "fusion_interview_consumed_challenge",
            len(fusion_rows) >= 1,
            {"matched_count": len(fusion_rows)},
        )

        # Zero plaintext JSON leaks in players / persona_import_challenges
        leak_rows = cur.execute(
            """
            SELECT player_id, persona_profile_json
            FROM players
            WHERE persona_profile_json LIKE '%AI_PERSONA_EXPORT_V1%'
               OR persona_profile_json LIKE '%persona_weights%';
            """
        ).fetchall()
        chal_leak_rows = cur.execute(
            """
            SELECT challenge_id
            FROM persona_import_challenges
            WHERE COALESCE(last_reject_reason, '') LIKE '%AI_PERSONA_EXPORT_V1%'
               OR COALESCE(last_reject_reason, '') LIKE '%persona_weights%';
            """
        ).fetchall()
        add_check(
            checks,
            failures,
            "zero_plaintext_json_leaks",
            len(leak_rows) == 0 and len(chal_leak_rows) == 0,
            {"player_leaks": len(leak_rows), "challenge_leaks": len(chal_leak_rows)},
        )

        # 5. manors: stockpiles >= 0, vault_protected_bp BETWEEN 4000 AND 6500
        bad_manors = cur.execute(
            """
            SELECT manor_id
            FROM manors
            WHERE grain_stock < 0 OR coin_stock < 0 OR iron_stock < 0
               OR wood_stock < 0 OR horse_stock < 0 OR herbs_wine_stock < 0
               OR weapon_stock < 0 OR household_troops < 0 OR wall_hp < 0
               OR vault_protected_bp < 4000 OR vault_protected_bp > 6500;
            """
        ).fetchall()
        add_check(
            checks,
            failures,
            "manors_invariants",
            table_counts["manors"] >= 3 and len(bad_manors) == 0,
            {"manors_count": table_counts["manors"], "violations": len(bad_manors)},
        )

        # 6. pawns_officers: 5 needs in [0, 10000], mood in [0, 100], 5 stats in [1, 120]
        bad_pawns = cur.execute(
            """
            SELECT pawn_id
            FROM pawns_officers
            WHERE food_need_bp NOT BETWEEN 0 AND 10000
               OR rest_need_bp NOT BETWEEN 0 AND 10000
               OR morale_bp NOT BETWEEN 0 AND 10000
               OR loyalty_bp NOT BETWEEN 0 AND 10000
               OR ambition_bp NOT BETWEEN 0 AND 10000
               OR mood NOT BETWEEN 0 AND 100
               OR leadership NOT BETWEEN 1 AND 120
               OR martial NOT BETWEEN 1 AND 120
               OR intelligence NOT BETWEEN 1 AND 120
               OR politics NOT BETWEEN 1 AND 120
               OR charisma NOT BETWEEN 1 AND 120;
            """
        ).fetchall()
        add_check(
            checks,
            failures,
            "pawns_officers_bounds",
            table_counts["pawns_officers"] >= 3 and len(bad_pawns) == 0,
            {"pawns_count": table_counts["pawns_officers"], "violations": len(bad_pawns)},
        )

        # 7. market_orders: at least 1 FILLED order
        filled_orders = int(
            cur.execute("SELECT COUNT(*) FROM market_orders WHERE status = 'FILLED';").fetchone()[0]
        )
        add_check(
            checks,
            failures,
            "market_orders_filled",
            filled_orders >= 1,
            {"total_orders": table_counts["market_orders"], "filled_orders": filled_orders},
        )

        # 8. command_audit_log: ACCEPTED >= 5 AND REJECTED >= 2
        accepted_cnt = int(
            cur.execute("SELECT COUNT(*) FROM command_audit_log WHERE status = 'ACCEPTED';").fetchone()[0]
        )
        rejected_cnt = int(
            cur.execute("SELECT COUNT(*) FROM command_audit_log WHERE status = 'REJECTED';").fetchone()[0]
        )
        add_check(
            checks,
            failures,
            "command_audit_log_accepted_and_rejected",
            accepted_cnt >= 5 and rejected_cnt >= 2,
            {"accepted": accepted_cnt, "rejected": rejected_cnt},
        )
    finally:
        conn.close()

    return {
        "schema_version": "1.0",
        "db_path": os.path.abspath(db_path),
        "table_counts": table_counts,
        "checks": checks,
        "failures": failures,
        "overall_passed": len(failures) == 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify SQLite world_state.db forensic audit invariants.")
    parser.add_argument("--db", default="saves/world_state.db", help="Path to SQLite database file")
    parser.add_argument("--out", default="", help="Optional path to write JSON audit report")
    args = parser.parse_args()

    report = verify_db(args.db)
    rendered = json.dumps(report, indent=2, ensure_ascii=False)
    print(rendered)

    if args.out:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(rendered + "\n")

    return 0 if report.get("overall_passed", False) else 1


if __name__ == "__main__":
    sys.exit(main())
