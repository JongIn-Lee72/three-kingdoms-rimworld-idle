#!/usr/bin/env python3
"""
Milestone M0 Automated Blueprint, Feature Coverage, SQLite Schema & Math Invariant Verifier
File: scripts/harness/verify_blueprint.py

Performs genuine empirical verification of the Phase 0 (M0 / FH-00) deliverables:
1. Existence, UTF-8 encoding, required structural tokens, and anti-stale-reference
   guards across PROJECT.md, docs/01_*.md..docs/04_*.md, and world_state_schema.sql.
2. Complete coverage and milestone mapping (M0..M6) of all 52 feature IDs
   (FH-00..FH-06 and F-01..F-45) across PROJECT.md and the docs/ suite.
3. Execution of data/schemas/world_state_schema.sql against both /usr/bin/sqlite3
   and Python's sqlite3 engine (asserting PRAGMA foreign_keys = 1), verifying all
   10 tables, >= 13 indexes, positive sample row insertions across all 10 tables,
   and 19 negative CHECK/FK/UNIQUE constraint rejections.
4. Deterministic mathematical reference invariants:
   - SplitMix64 64-bit integer PRNG determinism & uniform bounds check
   - Lanchester N^0.85 sub-linear combat scaling & tactical quality-over-quantity check
   - Mandate of Heaven Storyteller logarithmic Threat Score (T_i) & Adaptation Factor A_i in [0.4, 1.5]
   - LOD 0 (1s tick) vs LOD 1 (6s macro tick) rate-integrated equivalence formula check
   - Character Creation Point-Buy normalization (sum=320, [35, 85])
5. Track B Sealed Token (AI_PERSONA_TOKEN_V2 / TK3K2) reference decoder,
   Fletcher-31 integrity verification, coercion/anomaly gate (R0..R3, H1..H4),
   and 6-suite adversarial anti-tampering self-test.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import math
import pathlib
import re
import sqlite3
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = pathlib.Path(__file__).resolve().parents[2]

EXPECTED_FEATURE_IDS: List[str] = (
    [f"FH-0{i}" for i in range(7)]
    + [f"F-{i:02d}" for i in range(1, 46)]
)

EXPECTED_TABLES: List[str] = [
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

REQUIRED_DOCS: Dict[str, List[str]] = {
    "PROJECT.md": [
        "## Architecture",
        "## Feature Inventory",
        "## Milestones",
        "## Interface Contracts",
        "## Code Layout",
        "AI_PERSONA_TOKEN_V2",
        "TK3K2",
        "ClipboardSealedTokenProvider",
        "persona_import_challenges",
        "10 canonical tables",
    ],
    "docs/01_AI_AGENT_HARNESS_SPEC.md": [
        "scripts/setup_godot.sh",
        "4.4.1-stable",
        "4.7.2-stable",
        "untyped_declaration=2",
        "RefCounted",
        "check_syntax.sh",
        "validate_data.gd",
        "test_runner.gd",
        "sim_harness.gd",
        "net_harness.gd",
        "audit_verifier.py",
        "gemini-4-hydrogen",
        "10개 정규 테이블",
        "ClipboardSealedTokenProvider",
        "Zero-Trust Untrusted External Producer",
    ],
    "docs/02_GAME_DESIGN_DOCUMENT.md": [
        "LEA",
        "MAR",
        "INT",
        "POL",
        "CHA",
        "FOOD",
        "REST",
        "MORALE",
        "LOYALTY",
        "AMBITION",
        "SelectNextJob",
        "0.85",
        "사마천",
        "동탁",
        "문경지치",
        "일기토",
        "AI_PERSONA_TOKEN_V2",
        "TK3K2",
        "Fletcher-31",
        "ClipboardSealedTokenProvider",
        "ERR_PLAINTEXT_JSON_FORBIDDEN",
        "ERR_TOKEN_TAMPERED",
        "ERR_COERCION_REJECTED",
        "R0_CLEAN",
        "R3_PROMPT_INJECTION",
        "FUSION_INTERVIEW",
        "10테이블",
    ],
    "docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md": [
        "LOD 0",
        "LOD 1",
        "MICRO_TO_MACRO_EXPEDITION_DISPATCHED",
        "MACRO_TO_MICRO_RAID_INCOMING",
        "DeterministicRNG",
        "MSG_TICK_DELTA",
        "CHAN_GLOBAL_MACRO",
        "CHAN_FACTION",
        "CHAN_NODE",
        "CHAN_MANOR",
        "wal_commands.jsonl",
        "world_state.db",
        "CMD_REQUEST_PERSONA_CHALLENGE",
        "MSG_PERSONA_CHALLENGE",
        "CMD_CREATE_CHARACTER",
        "persona_import_challenges",
        "ERR_PLAINTEXT_JSON_FORBIDDEN",
        "ERR_TOKEN_TAMPERED",
        "ERR_CHALLENGE_UNKNOWN",
        "ERR_CHALLENGE_OWNERSHIP",
        "ERR_CHALLENGE_EXPIRED",
        "ERR_CHALLENGE_REPLAYED",
        "ERR_CHALLENGE_COOLDOWN",
        "ERR_COERCION_REJECTED",
        "10테이블",
    ],
    "docs/04_USER_CONFIRMATION_CHECKLIST.md": [
        "D-01",
        "D-02",
        "D-03",
        "D-04",
        "D-05",
        "D-06",
        "4.4.1-stable",
        "4.7.2-stable",
        "AI_PERSONA_TOKEN_V2",
        "TK3K2",
        "Fletcher-31",
        "ClipboardSealedTokenProvider",
        "R0_CLEAN",
        "R3_PROMPT_INJECTION",
        "10개 핵심 관계형 테이블",
        "10테이블",
    ],
}

STALE_PATTERN_CHECKS: List[Tuple[str, re.Pattern[str]]] = [
    (
        "stale_9_tables",
        re.compile(r"9 tables|9 relational|9 canonical|9테이블|9개 정규|9개 핵심|9대 테이블"),
    ),
    (
        "stale_clipboard_json_provider",
        re.compile(r"ClipboardJSONProvider"),
    ),
    (
        "stale_manual_json_edit_ux",
        re.compile(r"눈으로 검수·편집|직접\s*json을\s*수정|raw\s*JSON을\s*편집|JSON을\s*붙여넣고\s*내용을\s*직접"),
    ),
]


def verify_documents() -> Tuple[bool, Dict[str, Any]]:
    """ Step 1: Verify existence, UTF-8 encoding, required tokens, and zero stale references. """
    details: Dict[str, Any] = {}
    all_ok = True

    for rel_path, required_tokens in REQUIRED_DOCS.items():
        abs_path = ROOT_DIR / rel_path
        if not abs_path.is_file():
            details[rel_path] = {"exists": False, "error": "File does not exist"}
            all_ok = False
            continue

        try:
            content = abs_path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            details[rel_path] = {"exists": True, "utf8": False, "error": str(exc)}
            all_ok = False
            continue

        missing_tokens = [tok for tok in required_tokens if tok not in content]
        stale_hits = {
            name: pat.findall(content)
            for name, pat in STALE_PATTERN_CHECKS
            if pat.search(content)
        }
        line_count = len(content.splitlines())
        byte_size = len(content.encode("utf-8"))
        file_ok = len(missing_tokens) == 0 and len(stale_hits) == 0 and line_count >= 50

        if not file_ok:
            all_ok = False

        details[rel_path] = {
            "exists": True,
            "utf8": True,
            "lines": line_count,
            "bytes": byte_size,
            "missing_tokens": missing_tokens,
            "stale_hits": stale_hits,
            "passed": file_ok,
        }

    schema_rel = "data/schemas/world_state_schema.sql"
    schema_abs = ROOT_DIR / schema_rel
    if schema_abs.is_file():
        schema_text = schema_abs.read_text(encoding="utf-8")
        schema_stale = {
            name: pat.findall(schema_text)
            for name, pat in STALE_PATTERN_CHECKS
            if pat.search(schema_text)
        }
        if schema_stale:
            all_ok = False
        details[schema_rel] = {
            "exists": True,
            "stale_hits": schema_stale,
            "passed": len(schema_stale) == 0,
        }

    return all_ok, details


def verify_feature_coverage() -> Tuple[bool, Dict[str, Any]]:
    """ Step 2: Verify all 52 feature IDs (FH-00..FH-06, F-01..F-45) & milestone mappings. """
    project_md = (ROOT_DIR / "PROJECT.md").read_text(encoding="utf-8")
    doc_texts = {
        rel: (ROOT_DIR / rel).read_text(encoding="utf-8")
        for rel in [
            "docs/01_AI_AGENT_HARNESS_SPEC.md",
            "docs/02_GAME_DESIGN_DOCUMENT.md",
            "docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md",
            "docs/04_USER_CONFIRMATION_CHECKLIST.md",
        ]
    }
    combined_docs = "\n".join(doc_texts.values())

    # Parse feature rows in PROJECT.md table: | # | `ID` | ... | M0..M6 | ... |
    milestone_pattern = re.compile(
        r"\|\s*\d+\s*\|\s*`(FH-\d{2}|F-\d{2})`\s*\|[^|]+\|[^|]+\|\s*(M[0-6])\s*\|"
    )
    project_feature_milestones: Dict[str, str] = {}
    for match in milestone_pattern.finditer(project_md):
        fid, mstone = match.group(1), match.group(2)
        project_feature_milestones[fid] = mstone

    missing_in_project = [
        fid for fid in EXPECTED_FEATURE_IDS if fid not in project_feature_milestones
    ]
    missing_in_docs = [
        fid for fid in EXPECTED_FEATURE_IDS if fid not in combined_docs
    ]

    # Verify Specific Coverage:
    # FH-00..FH-06 in 01_AI_AGENT_HARNESS_SPEC.md
    missing_fh_in_doc01 = [
        f"FH-0{i}"
        for i in range(7)
        if f"FH-0{i}" not in doc_texts["docs/01_AI_AGENT_HARNESS_SPEC.md"]
    ]
    # All 52 features in 02_GAME_DESIGN_DOCUMENT.md
    missing_in_doc02 = [
        fid
        for fid in EXPECTED_FEATURE_IDS
        if fid not in doc_texts["docs/02_GAME_DESIGN_DOCUMENT.md"]
    ]
    # All 52 features in 03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md
    missing_in_doc03 = [
        fid
        for fid in EXPECTED_FEATURE_IDS
        if fid not in doc_texts["docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md"]
    ]

    passed = (
        len(missing_in_project) == 0
        and len(missing_in_docs) == 0
        and len(missing_fh_in_doc01) == 0
        and len(missing_in_doc02) == 0
        and len(missing_in_doc03) == 0
        and len(project_feature_milestones) == 52
    )

    milestone_counts: Dict[str, int] = {}
    for mstone in project_feature_milestones.values():
        milestone_counts[mstone] = milestone_counts.get(mstone, 0) + 1

    return passed, {
        "expected_total_features": len(EXPECTED_FEATURE_IDS),
        "found_in_project_md": len(project_feature_milestones),
        "milestone_distribution": milestone_counts,
        "missing_in_project_md": missing_in_project,
        "missing_in_docs_suite": missing_in_docs,
        "missing_fh_in_doc01": missing_fh_in_doc01,
        "missing_in_doc02": missing_in_doc02,
        "missing_in_doc03": missing_in_doc03,
        "passed": passed,
    }


def verify_sqlite_schema() -> Tuple[bool, Dict[str, Any]]:
    """ Step 3: Execute world_state_schema.sql in /usr/bin/sqlite3 and python sqlite3; test positive & negative constraints. """
    schema_path = ROOT_DIR / "data/schemas/world_state_schema.sql"
    if not schema_path.is_file():
        return False, {"error": f"Schema file missing: {schema_path}"}

    schema_sql = schema_path.read_text(encoding="utf-8")

    # 3.1 Verify with /usr/bin/sqlite3 CLI binary
    cli_proc = subprocess.run(
        ["/usr/bin/sqlite3", ":memory:"],
        input=schema_sql,
        text=True,
        capture_output=True,
        check=False,
    )
    cli_ok = cli_proc.returncode == 0

    # 3.2 Verify in-memory with Python sqlite3: FK pragma, table discovery, valid insertions, and negative constraint tests
    conn = sqlite3.connect(":memory:")
    conn.executescript(schema_sql)
    cur = conn.cursor()

    cur.execute("PRAGMA foreign_keys;")
    fk_row = cur.fetchone()
    fk_enabled = bool(fk_row and fk_row[0] == 1)

    cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
    )
    found_tables = [row[0] for row in cur.fetchall()]
    missing_tables = [t for t in EXPECTED_TABLES if t not in found_tables]

    cur.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
    )
    found_indexes = [row[0] for row in cur.fetchall()]

    # 3.3 Positive valid insertions across all 10 tables
    positive_insert_ok = True
    positive_error = ""
    try:
        cur.execute(
            """
            INSERT INTO world_meta (
                world_id, world_seed, current_tick_id, current_day_id,
                season, storyteller_id, state_crc32, updated_at_utc
            ) VALUES ('world_3k_01', 18401, 1440, 60, 'AUTUMN', 'SIMA_QIAN', 3491827412, '2026-11-20T12:00:00Z');
            """
        )
        cur.execute(
            """
            INSERT INTO factions (
                faction_id, name, lord_player_id, capital_node_id,
                royal_rank, treasury_grain, treasury_coin, imperial_edicts, prestige
            ) VALUES ('faction_shu', '촉한 (Shu Han)', 'player_liu', 'chengdu', 'KING', 120000, 85000, 2, 4500);
            """
        )
        cur.execute(
            """
            INSERT INTO macro_nodes (
                node_id, name, province, node_tier, owner_faction_id, governor_player_id,
                fortification_hp, max_fortification_hp, public_order_bp, bandit_pressure_bp,
                tax_rate_bp, treasury_grain, treasury_coin, grain_price_bp, iron_price_bp
            ) VALUES (
                'chengdu', '성도 (Chengdu)', '익주 (Yizhou)', 'CAPITAL_METROPOLIS', 'faction_shu', 'player_zhuge',
                9500, 10000, 9200, 400, 1500, 50000, 35000, 1050, 1400
            );
            """
        )
        cur.execute(
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, bound_player_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, consumed_at_tick, status,
                attempt_count, max_attempts, cooldown_until_tick, last_coercion_flag, last_reject_reason
            ) VALUES (
                '7R4M9P', 'acct_zhao', 'player_zhao', 'nonce_7R4M9P', 'salt_01', 'hint_01',
                1000, 1900, NULL, 'ISSUED',
                0, 3, 0, 'R0_CLEAN', NULL
            );
            """
        )
        cur.execute(
            """
            UPDATE persona_import_challenges
            SET status = 'CONSUMED', consumed_at_tick = 1440
            WHERE challenge_id = '7R4M9P';
            """
        )
        cur.execute(
            """
            INSERT INTO players (
                player_id, display_name, auth_token_hash, origin_archetype,
                creation_mode, persona_profile_json, persona_challenge_id,
                import_audit_status, coercion_flag,
                role_tier, faction_id, court_rank, war_merit, host_node_id, manor_id,
                is_online, last_seen_tick, truce_shield_until_tick, adaptation_factor_bp
            ) VALUES (
                'player_zhao', '조운 (Zhao Yun)', 'sha256_tok_zhao', 'ORIGIN_FRONTIER_OFFICER',
                'FUSION_INTERVIEW', '{"sealed_token_ref":"7R4M9P"}', '7R4M9P',
                'VERIFIED_CLEAN', 'R0_CLEAN',
                'FACTION_OFFICER', 'faction_shu', 'RANK_3', 22500, 'chengdu', 'manor_zhao',
                1, 1440, 0, 1000
            );
            """
        )
        # Verify UNIQUE on players.persona_challenge_id allows multiple NULLs for INTERVIEW_ONLY players
        cur.execute(
            """
            INSERT INTO players (
                player_id, display_name, auth_token_hash, origin_archetype,
                creation_mode, persona_profile_json, persona_challenge_id,
                import_audit_status, coercion_flag,
                role_tier, faction_id, court_rank, war_merit, host_node_id, manor_id,
                is_online, last_seen_tick, truce_shield_until_tick, adaptation_factor_bp
            ) VALUES (
                'player_iv_01', '강유 (Jiang Wei)', 'sha256_tok_iv1', 'ORIGIN_PURE_SCHOLAR',
                'INTERVIEW_ONLY', '{"mode":"INTERVIEW_ONLY"}', NULL,
                'NONE', 'R0_CLEAN',
                'FREE_OFFICER', NULL, 'NONE', 0, 'chengdu', 'manor_iv_01',
                0, 1440, 0, 1000
            );
            """
        )
        cur.execute(
            """
            INSERT INTO players (
                player_id, display_name, auth_token_hash, origin_archetype,
                creation_mode, persona_profile_json, persona_challenge_id,
                import_audit_status, coercion_flag,
                role_tier, faction_id, court_rank, war_merit, host_node_id, manor_id,
                is_online, last_seen_tick, truce_shield_until_tick, adaptation_factor_bp
            ) VALUES (
                'player_iv_02', '위연 (Wei Yan)', 'sha256_tok_iv2', 'ORIGIN_CHIVALROUS_HERO',
                'INTERVIEW_ONLY', '{"mode":"INTERVIEW_ONLY"}', NULL,
                'FALLBACK_INTERVIEW', 'R0_CLEAN',
                'FREE_OFFICER', NULL, 'NONE', 0, 'chengdu', 'manor_iv_02',
                0, 1440, 0, 1000
            );
            """
        )
        cur.execute(
            """
            INSERT INTO manors (
                manor_id, player_id, host_node_id, current_lod,
                grain_stock, coin_stock, iron_stock, wood_stock, horse_stock,
                herbs_wine_stock, weapon_stock, household_troops, vault_protected_bp,
                wall_hp, standing_doctrine_json, grid_zones_json
            ) VALUES (
                'manor_zhao', 'player_zhao', 'chengdu', 0,
                14500, 6200, 1800, 2400, 150,
                320, 400, 1200, 5000,
                3500, '{"stance":"HOLD_CHOKE"}', '{"zones":7}'
            );
            """
        )
        cur.execute(
            """
            INSERT INTO pawns_officers (
                pawn_id, owner_player_id, manor_id, name, is_avatar, state, health_state,
                leadership, martial, intelligence, politics, charisma,
                food_need_bp, rest_need_bp, morale_bp, loyalty_bp, ambition_bp, mood,
                mental_state, traits_json, work_priorities_json, daily_schedule_json
            ) VALUES (
                'pawn_zhao_main', 'player_zhao', 'manor_zhao', '조자룡', 1, 'IN_MANOR', 'HEALTHY',
                92, 97, 76, 65, 88,
                8800, 9000, 9200, 10000, 8500, 86,
                'AWAKENED_VALOR', '["T_CHIVALROUS","T_FIERCE"]',
                '{"LOGISTICS":3,"PATROL":1,"AGRICULTURE":0,"TRAINING":1,"CRAFTING":2,"RESEARCH":3,"DIPLOMACY":2}',
                '["SLEEP","SLEEP","DRILL","WORK","WORK","WORK","RECREATION","WORK","WORK","DRILL","RECREATION","SLEEP"]'
            );
            """
        )
        cur.execute(
            """
            INSERT INTO armies_caravans (
                entity_id, owner_player_id, faction_id, unit_type, current_node_id, current_edge_id,
                edge_progress_pm, troop_count, morale_bp, carried_grain, carried_coin,
                cargo_json, doctrine_json
            ) VALUES (
                'army_zhao_01', 'player_zhao', 'faction_shu', 'ARMY', NULL, 'edge_chengdu_hanzhong',
                450, 800, 9400, 3200, 500, '{"WEAPONS":100}', '{"formation":"ARROWHEAD"}'
            );
            """
        )
        cur.execute(
            """
            INSERT INTO market_orders (
                order_id, node_id, player_id, commodity, side, price_bp,
                quantity, filled_quantity, created_tick, status
            ) VALUES (
                'ord_9001', 'chengdu', 'player_zhao', 'GRAIN', 'BID', 1100,
                500, 100, 1420, 'OPEN'
            );
            """
        )
        cur.execute(
            """
            INSERT INTO command_audit_log (
                tick_id, player_id, cmd_type, status, reject_reason, payload_json
            ) VALUES (
                1440, 'player_zhao', 'CMD_SET_WORK_PRIORITY', 'ACCEPTED', NULL, '{"pawn_id":"pawn_zhao_main","PATROL":1}'
            );
            """
        )
        conn.commit()
    except sqlite3.Error as exc:
        positive_insert_ok = False
        positive_error = str(exc)

    # 3.4 Empirical Negative Constraint Tests (must raise sqlite3.IntegrityError)
    negative_tests = [
        (
            "reject_negative_grain_stock",
            """
            UPDATE manors SET grain_stock = -100 WHERE manor_id = 'manor_zhao';
            """,
        ),
        (
            "reject_invalid_lod_tier",
            """
            UPDATE manors SET current_lod = 2 WHERE manor_id = 'manor_zhao';
            """,
        ),
        (
            "reject_invalid_player_role_tier",
            """
            UPDATE players SET role_tier = 'GOD_EMPEROR_CHEAT' WHERE player_id = 'player_zhao';
            """,
        ),
        (
            "reject_out_of_bounds_loyalty_bp",
            """
            UPDATE pawns_officers SET loyalty_bp = 15000 WHERE pawn_id = 'pawn_zhao_main';
            """,
        ),
        (
            "reject_out_of_bounds_mood",
            """
            UPDATE pawns_officers SET mood = 120 WHERE pawn_id = 'pawn_zhao_main';
            """,
        ),
        (
            "reject_invalid_market_order_side",
            """
            UPDATE market_orders SET side = 'SHORT_SELL' WHERE order_id = 'ord_9001';
            """,
        ),
        (
            "reject_invalid_audit_status",
            """
            INSERT INTO command_audit_log (tick_id, player_id, cmd_type, status, reject_reason, payload_json)
            VALUES (1441, 'player_zhao', 'CMD_CHEAT', 'BYPASSED', NULL, '{}');
            """,
        ),
        (
            "reject_invalid_creation_mode",
            """
            UPDATE players SET creation_mode = 'RAW_STAT_INJECT' WHERE player_id = 'player_zhao';
            """,
        ),
        (
            "reject_challenge_ttl_not_after_issued",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, status
            ) VALUES ('BADTTL', 'acct_bad', 'nonce_bad1', 'salt_1', 'hint_1', 1000, 1000, 'ISSUED');
            """,
        ),
        (
            "reject_consumed_without_tick",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, consumed_at_tick, status
            ) VALUES ('BADCON', 'acct_bad', 'nonce_bad2', 'salt_1', 'hint_1', 1000, 1900, NULL, 'CONSUMED');
            """,
        ),
        (
            "reject_issued_with_consumed_tick",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, consumed_at_tick, status
            ) VALUES ('BADISS', 'acct_bad', 'nonce_bad3', 'salt_1', 'hint_1', 1000, 1900, 1445, 'ISSUED');
            """,
        ),
        (
            "reject_invalid_challenge_status",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, status
            ) VALUES ('BADSTA', 'acct_bad', 'nonce_bad4', 'salt_1', 'hint_1', 1000, 1900, 'BYPASSED');
            """,
        ),
        (
            "reject_excessive_attempt_count",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, status, attempt_count, max_attempts
            ) VALUES ('BADATT', 'acct_bad', 'nonce_bad5', 'salt_1', 'hint_1', 1000, 1900, 'ISSUED', 4, 3);
            """,
        ),
        (
            "reject_invalid_import_audit_status",
            """
            UPDATE players SET import_audit_status = 'ADMIN_OVERRIDE' WHERE player_id = 'player_zhao';
            """,
        ),
        (
            "reject_invalid_coercion_flag",
            """
            UPDATE players SET coercion_flag = 'R9_GODMODE' WHERE player_id = 'player_zhao';
            """,
        ),
        (
            "reject_unknown_persona_challenge_fk",
            """
            UPDATE players SET persona_challenge_id = 'nonexistent_challenge' WHERE player_id = 'player_zhao';
            """,
        ),
        (
            "reject_duplicate_player_persona_challenge_id",
            """
            INSERT INTO players (
                player_id, display_name, auth_token_hash, origin_archetype,
                creation_mode, persona_profile_json, persona_challenge_id,
                import_audit_status, coercion_flag,
                role_tier, faction_id, court_rank, war_merit, host_node_id, manor_id,
                is_online, last_seen_tick, truce_shield_until_tick, adaptation_factor_bp
            ) VALUES (
                'player_dup_chal', '중복시도자', 'sha256_tok_dup', 'ORIGIN_CHIVALROUS_HERO',
                'FUSION_INTERVIEW', '{"sealed_token_ref":"7R4M9P"}', '7R4M9P',
                'VERIFIED_CLEAN', 'R0_CLEAN',
                'FREE_OFFICER', NULL, 'NONE', 0, 'chengdu', 'manor_dup_chal',
                0, 1441, 0, 1000
            );
            """,
        ),
        (
            "reject_duplicate_challenge_nonce",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, status
            ) VALUES ('DUPNON', 'acct_dup', 'nonce_7R4M9P', 'salt_2', 'hint_2', 1001, 1901, 'ISSUED');
            """,
        ),
        (
            "reject_consumed_tick_before_issued",
            """
            INSERT INTO persona_import_challenges (
                challenge_id, account_id, nonce, session_salt, cipher_key_hint,
                issued_at_tick, ttl_expires_tick, consumed_at_tick, status
            ) VALUES ('BADTIM', 'acct_bad', 'nonce_bad6', 'salt_1', 'hint_1', 1000, 1900, 999, 'CONSUMED');
            """,
        ),
    ]

    negative_results: Dict[str, bool] = {}
    all_negative_rejected = True
    for test_name, bad_sql in negative_tests:
        try:
            cur.execute(bad_sql)
            conn.commit()
            # If we reach here, SQLite failed to reject the invalid data!
            negative_results[test_name] = False
            all_negative_rejected = False
        except sqlite3.IntegrityError:
            conn.rollback()
            negative_results[test_name] = True

    conn.close()

    passed = (
        cli_ok
        and fk_enabled
        and len(found_tables) == 10
        and len(missing_tables) == 0
        and len(found_indexes) >= 13
        and positive_insert_ok
        and all_negative_rejected
    )

    return passed, {
        "sqlite3_cli_exit_zero": cli_ok,
        "pragma_foreign_keys_enabled": fk_enabled,
        "found_tables": found_tables,
        "found_tables_count": len(found_tables),
        "missing_tables": missing_tables,
        "found_indexes_count": len(found_indexes),
        "positive_insertions_passed": positive_insert_ok,
        "positive_error": positive_error,
        "negative_constraint_rejections": negative_results,
        "passed": passed,
    }


def splitmix64_roll_range(
    world_seed: int,
    tick_id: int,
    entity_id: int,
    salt: int,
    min_val: int,
    max_val: int,
) -> int:
    """ Reference 64-bit two's-complement SplitMix64 implementation matching DeterministicRNG.roll_range. """
    if max_val <= min_val:
        return min_val
    mask64 = 0xFFFFFFFFFFFFFFFF
    z = (
        world_seed
        ^ ((tick_id * 0x9E3779B97F4A7C15) & mask64)
        ^ ((entity_id * 0xBF58476D1CE4E5B9) & mask64)
        ^ ((salt * 0x94D049BB133111EB) & mask64)
    ) & mask64
    z = (((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & mask64)
    z = (((z ^ (z >> 27)) * 0x94D049BB133111EB) & mask64)
    z = (z ^ (z >> 31)) & mask64
    span = (max_val - min_val) + 1
    pos_z = z & 0x7FFFFFFFFFFFFFFF
    return min_val + (pos_z % span)


def verify_math_invariants() -> Tuple[bool, Dict[str, Any]]:
    """ Step 4: Verify SplitMix64 determinism, Lanchester N^0.85 combat math, Storyteller Threat Score & LOD0/1 parity. """
    # 4.1 SplitMix64 Determinism & Seed Sensitivity Check
    seq_seed_a_run1 = [splitmix64_roll_range(18401, t, 101, 7, 1, 10000) for t in range(100)]
    seq_seed_a_run2 = [splitmix64_roll_range(18401, t, 101, 7, 1, 10000) for t in range(100)]
    seq_seed_b = [splitmix64_roll_range(99103, t, 101, 7, 1, 10000) for t in range(100)]

    rng_deterministic = (seq_seed_a_run1 == seq_seed_a_run2)
    rng_seed_sensitive = (seq_seed_a_run1 != seq_seed_b)
    rng_in_bounds = all(1 <= v <= 10000 for v in seq_seed_a_run1)

    # 4.2 Lanchester N^0.85 Combat Formula Invariant Check
    # Compare elite force (N_A = 1000, MAR=96, LEA=94, gear=1.5, morale_bp=9500)
    # vs larger militia force (N_B = 1800, MAR=55, LEA=50, gear=1.0, morale_bp=6000)
    def calc_atk(n: int, mar: int, lea: int, gear: float, morale_bp: int) -> float:
        return (
            (n ** 0.85)
            * 1.0
            * (1.0 + (mar + 0.5 * lea) / 100.0)
            * gear
            * (0.6 + 0.00004 * morale_bp)
        )

    atk_elite_1000 = calc_atk(1000, 96, 94, 1.5, 9500)
    atk_militia_1800 = calc_atk(1800, 55, 50, 1.0, 6000)
    atk_elite_2000 = calc_atk(2000, 96, 94, 1.5, 9500)

    # Elite 1000 troops with superior general & gear overcomes 1800 low-stat militia,
    # while increasing troop count monotonically increases attack power.
    lanchester_ok = (atk_elite_1000 > atk_militia_1800) and (atk_elite_2000 > atk_elite_1000)

    # 4.3 Storyteller Threat Score Logarithmic Scaling & Adaptation Factor Bounds [0.4, 1.5]
    def calc_threat_score(wealth: float, retainers: int, troops: int, adaptation: float) -> float:
        clamped_a = max(0.4, min(1.5, adaptation))
        return (100.0 * math.log(1.0 + wealth / 1000.0) + 25.0 * retainers + 0.15 * troops) * clamped_a

    t_low_wealth = calc_threat_score(10_000, 5, 500, 1.0)
    t_10x_wealth = calc_threat_score(100_000, 5, 500, 1.0)
    t_post_defeat = calc_threat_score(100_000, 5, 500, 1.0 - 0.25)

    # 10x wealth increase must produce < 3x threat increase (logarithmic dampening),
    # and post-defeat adaptation drop (-0.25) must strictly reduce threat score.
    storyteller_ok = (t_low_wealth < t_10x_wealth < 3.0 * t_low_wealth) and (t_post_defeat < t_10x_wealth)

    # 4.4 LOD 0 (6 micro-ticks) vs LOD 1 (1 macro-tick rate-integrated) Equivalence Check
    base_work_per_tick = 120  # scaled integer work units
    eta_walk = 850  # 0.850 in permille
    alpha_weight = 1000  # 1.000 full duty allocation
    lod0_6_ticks_yield = sum((base_work_per_tick * eta_walk) // 1000 for _ in range(6))
    lod1_1_macro_yield = (6 * base_work_per_tick * eta_walk * alpha_weight) // (1000 * 1000)
    lod_parity_ok = (lod0_6_ticks_yield == lod1_1_macro_yield)

    # 4.5 Character Creation Point-Buy Normalization Invariant (Anti-Cheat Fairness)
    # Any adversarial AI + Interview weights must normalize deterministically to sum=320, each stat in [35, 85].
    def normalize_stats(raw_weights: List[int]) -> List[int]:
        clamped = [max(1, min(1000, int(w))) for w in raw_weights]
        total_w = sum(clamped)
        variable_budget = 320 - 5 * 35  # 145
        stats = [35 + (w * variable_budget) // total_w for w in clamped]
        # Clamp individual cap 85 and redistribute remainder deterministically by (-weight, index)
        order = sorted(range(5), key=lambda idx: (-clamped[idx], idx))
        stats = [min(85, s) for s in stats]
        remaining = 320 - sum(stats)
        while remaining > 0:
            for idx in order:
                if remaining == 0:
                    break
                if stats[idx] < 85:
                    stats[idx] += 1
                    remaining -= 1
        return stats

    probe_vectors = [
        [9999, 9999, 9999, 9999, 9999],  # adversarial all-max AI weights
        [1000, 0, 0, 0, 0],              # adversarial single-stat min-max
        [0, 0, 0, 0, 0],                 # adversarial all-zero
        [74, 44, 98, 86, 62],            # realistic TK3K2 decoded raw weights
    ]
    normalized_probes = [normalize_stats(v) for v in probe_vectors]
    point_buy_ok = all(
        sum(s) == 320 and all(35 <= val <= 85 for val in s)
        for s in normalized_probes
    ) and (normalize_stats([74, 44, 98, 86, 62]) == [64, 52, 75, 70, 59])

    passed = (
        rng_deterministic
        and rng_seed_sensitive
        and rng_in_bounds
        and lanchester_ok
        and storyteller_ok
        and lod_parity_ok
        and point_buy_ok
    )

    return passed, {
        "splitmix64_deterministic": rng_deterministic,
        "splitmix64_seed_sensitive": rng_seed_sensitive,
        "splitmix64_bounds_valid": rng_in_bounds,
        "lanchester_n085_tactical_and_monotonic": lanchester_ok,
        "atk_elite_1000": round(atk_elite_1000, 2),
        "atk_militia_1800": round(atk_militia_1800, 2),
        "storyteller_log_scaling_and_adaptation": storyteller_ok,
        "lod0_vs_lod1_exact_integer_parity": lod_parity_ok,
        "character_creation_point_buy_normalization": point_buy_ok,
        "sample_normalized_persona_stats": normalized_probes[-1],
        "passed": passed,
    }


def verify_sealed_token_decoder() -> Tuple[bool, Dict[str, Any]]:
    """ Step 5: Genuine deterministic TK3K2 Base-31 / Fletcher-31 decoder + coercion/anomaly gate self-test. """
    alphabet_31 = "0123456789ABCDEFGHJKMNPQRSTVWXY"
    token_re = re.compile(
        r"^TK3K2-([0-9A-HJKMNP-TV-XY]{6})-([0-9A-HJKMNP-TV-XY]{6})-"
        r"([0-9A-HJKMNP-TV-XY]{6})-([0-9A-HJKMNP-TV-XY]{4})-([0-9A-HJKMNP-TV-XY]{2})$"
    )
    server_pepper = b"TK3K_DEV_PEPPER_REPLACE_IN_PROD_V2"
    challenge_ttl_ticks = 900

    # Canonical 5 Light (+1) / 5 Shadow (-1) Trait Partition
    trait_catalog: List[Tuple[str, int, str]] = [
        ("T_CHIVALROUS", +1, "LIGHT"),   # 0
        ("T_AMBITIOUS", -1, "SHADOW"),   # 1
        ("T_CAUTIOUS", -1, "SHADOW"),    # 2
        ("T_DRINKER", -1, "SHADOW"),     # 3
        ("T_MYSTIC", +1, "LIGHT"),       # 4
        ("T_UNSELFISH", +1, "LIGHT"),    # 5
        ("T_GREEDY", -1, "SHADOW"),      # 6
        ("T_FIERCE", -1, "SHADOW"),      # 7
        ("T_AGRARIAN", +1, "LIGHT"),     # 8
        ("T_SCHOLAR", +1, "LIGHT"),      # 9
    ]
    light_pool = [0, 4, 5, 8, 9]
    shadow_pool = [1, 2, 3, 6, 7]
    coercion_enum = {
        0: "R0_CLEAN",
        1: "R1_MILD_STEERING",
        2: "R2_STAT_COERCION",
        3: "R3_PROMPT_INJECTION",
    }

    def derive_session_cipher(challenge_id: str, player_id: str) -> Tuple[List[str], Dict[str, int], int, int]:
        digest = hmac.new(server_pepper, f"{challenge_id}:{player_id}".encode("utf-8"), hashlib.sha256).digest()
        chars = list(alphabet_31)
        stream = digest
        pos = 0
        for i in range(30, 0, -1):
            if pos >= len(stream):
                stream = hashlib.sha256(stream).digest()
                pos = 0
            j = stream[pos] % (i + 1)
            pos += 1
            chars[i], chars[j] = chars[j], chars[i]
        rev_map = {ch: idx for idx, ch in enumerate(chars)}
        init_s1 = stream[pos % len(stream)] % 31
        init_s2 = stream[(pos + 1) % len(stream)] % 31
        return chars, rev_map, init_s1, init_s2

    def encode_tk3k2(challenge_id: str, player_id: str, v: List[int]) -> str:
        assert len(v) == 16
        chars, _, init_s1, init_s2 = derive_session_cipher(challenge_id, player_id)
        s1, s2 = init_s1, init_s2
        for val in v:
            s1 = (s1 + val) % 31
            s2 = (s2 + s1) % 31
        seg1 = "".join(chars[x] for x in v[0:6])
        seg2 = "".join(chars[x] for x in v[6:12])
        seg3 = "".join(chars[x] for x in v[12:16])
        chk = chars[s1] + chars[s2]
        return f"TK3K2-{challenge_id}-{seg1}-{seg2}-{seg3}-{chk}"

    def normalize_weights_320(raw_weights: List[int]) -> List[int]:
        clamped = [max(1, min(1000, int(w))) for w in raw_weights]
        total_w = sum(clamped)
        stats = [35 + (w * 145) // total_w for w in clamped]
        order = sorted(range(5), key=lambda idx: (-clamped[idx], idx))
        stats = [min(85, s) for s in stats]
        rem = 320 - sum(stats)
        while rem > 0:
            for idx in order:
                if rem == 0:
                    break
                if stats[idx] < 85:
                    stats[idx] += 1
                    rem -= 1
        return stats

    def decode_and_verify(
        raw_input: str,
        player_id: str,
        requested_mode: str,
        current_tick: int,
        challenge_store: Dict[str, dict],
        account_cooldown_until: Dict[str, int],
        account_tamper_strikes: Optional[Dict[str, int]] = None,
    ) -> Tuple[bool, str, Optional[dict]]:
        # Stage 1 hard wire payload cap (<= 4096 UTF-8 bytes) BEFORE regex matching
        if len(raw_input.encode("utf-8")) > 4096:
            return False, "ERR_TOKEN_FORMAT", None

        text = raw_input.strip()
        if (
            "{" in text
            or "}" in text
            or "AI_PERSONA_EXPORT_V1" in text
            or "persona_weights" in text
            or re.search(r'(?i)"(?:lea|mar|int|pol|cha)"\s*:', text)
        ):
            return False, "ERR_PLAINTEXT_JSON_FORBIDDEN", None

        open_tag = "<<<TK3K_PERSONA_V2>>>"
        close_tag = "<<<END_TK3K_PERSONA_V2>>>"
        open_count = text.count(open_tag)
        close_count = text.count(close_tag)
        if open_count > 1 or close_count > 1 or (open_count != close_count):
            return False, "ERR_TOKEN_FORMAT", None

        m_env = re.search(r"<<<TK3K_PERSONA_V2>>>\s*(TK3K2-[^\s<]+)\s*<<<END_TK3K_PERSONA_V2>>>", text)
        if open_count == 1 and not m_env:
            return False, "ERR_TOKEN_FORMAT", None
        candidate = m_env.group(1) if m_env else text
        m_tok = token_re.match(candidate)
        if not m_tok:
            return False, "ERR_TOKEN_FORMAT", None

        cid, seg1, seg2, seg3, chk = m_tok.groups()
        if current_tick < account_cooldown_until.get(player_id, 0):
            return False, "ERR_CHALLENGE_COOLDOWN", None

        rec = challenge_store.get(cid)
        if rec is None:
            return False, "ERR_CHALLENGE_UNKNOWN", None
        if rec["player_id"] != player_id:
            return False, "ERR_CHALLENGE_OWNERSHIP", None
        # Check persisted status strictly BEFORE TTL tick comparison to prevent EXPIRED bypass
        if rec["status"] == "CONSUMED":
            return False, "ERR_CHALLENGE_REPLAYED", None
        if rec["status"] == "REVOKED_TAMPER" or current_tick < rec.get("cooldown_until_tick", 0):
            return False, "ERR_CHALLENGE_COOLDOWN", None
        if rec["status"] == "EXPIRED":
            return False, "ERR_CHALLENGE_EXPIRED", None
        if rec["status"] != "ISSUED":
            return False, "ERR_CHALLENGE_UNKNOWN", None
        if current_tick > rec["ttl_expires_tick"]:
            rec["status"] = "EXPIRED"
            return False, "ERR_CHALLENGE_EXPIRED", None

        _, rev_map, init_s1, init_s2 = derive_session_cipher(cid, player_id)
        body = seg1 + seg2 + seg3
        if any(ch not in rev_map for ch in body + chk):
            return False, "ERR_TOKEN_TAMPERED", None

        v = [rev_map[ch] for ch in body]
        c1, c2 = rev_map[chk[0]], rev_map[chk[1]]
        s1, s2 = init_s1, init_s2
        for val in v:
            s1 = (s1 + val) % 31
            s2 = (s2 + s1) % 31
        if (s1, s2) != (c1, c2):
            rec["attempt_count"] = rec.get("attempt_count", 0) + 1
            if rec["attempt_count"] >= rec.get("max_attempts", 3):
                rec["status"] = "REVOKED_TAMPER"
                rec["last_reject_reason"] = "ERR_TOKEN_TAMPERED"
                if account_tamper_strikes is not None:
                    strikes = account_tamper_strikes.get(player_id, 0) + 1
                    account_tamper_strikes[player_id] = strikes
                else:
                    strikes = 1
                cooldown_ticks = [300, 900, 3600][min(strikes - 1, 2)]
                rec["cooldown_until_tick"] = current_tick + cooldown_ticks
                account_cooldown_until[player_id] = current_tick + cooldown_ticks
            return False, "ERR_TOKEN_TAMPERED", None

        # Domain bounds check
        ai_src = v[0]
        weights_q = v[1:6]
        p1, p2, p3 = v[6], v[7], v[8]
        t1, t2, t_shadow = v[9], v[10], v[11]
        origin_code, rhythm_code, stance_code, risk_code = v[12], v[13], v[14], v[15]

        if not (0 <= ai_src <= 6):
            return False, "ERR_TOKEN_DOMAIN", None
        if not all(1 <= w <= 30 for w in weights_q):
            return False, "ERR_TOKEN_DOMAIN", None
        if not (0 <= p1 <= 4 and 0 <= p2 <= 4 and p1 != p2 and (p3 == 10 or (0 <= p3 <= 4 and p3 not in (p1, p2)))):
            return False, "ERR_TOKEN_DOMAIN", None
        if not (0 <= t1 <= 9 and (t2 == 10 or (0 <= t2 <= 9 and t2 != t1)) and 0 <= t_shadow <= 9 and t_shadow not in (t1, t2)):
            return False, "ERR_TOKEN_DOMAIN", None
        if not (0 <= origin_code <= 4 and 0 <= rhythm_code <= 3 and 0 <= stance_code <= 3 and 0 <= risk_code <= 3):
            return False, "ERR_TOKEN_DOMAIN", None

        coercion_flag = coercion_enum[risk_code]
        if risk_code >= 2:
            rec["status"] = "REVOKED_TAMPER"
            rec["last_coercion_flag"] = coercion_flag
            rec["last_reject_reason"] = f"ERR_COERCION_REJECTED:{coercion_flag}"
            if risk_code == 3:
                rec["cooldown_until_tick"] = current_tick + 1800
                account_cooldown_until[player_id] = current_tick + 1800
            return False, "ERR_COERCION_REJECTED", {
                "import_audit_status": "REJECTED_COERCION",
                "coercion_flag": coercion_flag,
                "forced_mode": "INTERVIEW_ONLY",
                "cooldown_applied": risk_code == 3,
            }

        # Atomic consumption for verified R0/R1 submissions
        rec["status"] = "CONSUMED"
        rec["consumed_at_tick"] = current_tick
        rec["last_coercion_flag"] = coercion_flag

        effective_mode = requested_mode
        beta_ai = 10000 if requested_mode == "AI_DIRECT_WITH_CONFIRM" else 4000
        audit_status = "VERIFIED_CLEAN"

        if risk_code == 1:
            effective_mode = "FUSION_INTERVIEW"
            beta_ai = 2000
            audit_status = "DOWNGRADED_ANOMALY"

        raw_weights = [20 + 3 * w for w in weights_q]

        # H1: Flat-Ceiling / Zero-Variance
        if all(w >= 28 for w in weights_q) or (max(weights_q) - min(weights_q) == 0):
            if effective_mode == "AI_DIRECT_WITH_CONFIRM":
                effective_mode = "FUSION_INTERVIEW"
            beta_ai = min(beta_ai, 2000)
            audit_status = "DOWNGRADED_ANOMALY"

        # H2: Extreme Bimodal Min-Max in AI_DIRECT_WITH_CONFIRM
        if sum(1 for w in weights_q if w >= 27) >= 2 and sum(1 for w in weights_q if w <= 4) >= 2:
            if requested_mode == "AI_DIRECT_WITH_CONFIRM":
                effective_mode = "FUSION_INTERVIEW"
                beta_ai = min(beta_ai, 4000)
                audit_status = "DOWNGRADED_ANOMALY"
                mean_w = sum(raw_weights) // 5
                raw_weights = [(850 * rw + 150 * mean_w) // 1000 for rw in raw_weights]

        # H3: Symmetric Trait Light/Shadow Invariant Enforcement (5 Light +1 / 5 Shadow -1)
        chosen = [t1] + ([t2] if t2 != 10 else []) + [t_shadow]
        shadow_count = sum(1 for idx in chosen if trait_catalog[idx][2] == "SHADOW")
        net_cost = sum(trait_catalog[idx][1] for idx in chosen)
        if t_shadow not in shadow_pool or shadow_count < 1 or not (-1 <= net_cost <= 1):
            audit_status = "DOWNGRADED_ANOMALY"
            # 1) Ensure t_shadow is in shadow_pool
            if t_shadow not in shadow_pool:
                for cand in shadow_pool:
                    if cand not in (t1, t2):
                        t_shadow = cand
                        break
            chosen = [t1] + ([t2] if t2 != 10 else []) + [t_shadow]
            shadow_count = sum(1 for idx in chosen if trait_catalog[idx][2] == "SHADOW")
            net_cost = sum(trait_catalog[idx][1] for idx in chosen)
            # 2) Excess Shadow (net_cost < -1: 2-trait -2 or 3-trait -3) -> replace t1 with Light (+1)
            if net_cost < -1:
                for cand in light_pool:
                    if cand not in chosen:
                        chosen[0] = cand
                        break
            # 3) Defensive check if net_cost > 1
            shadow_count = sum(1 for idx in chosen if trait_catalog[idx][2] == "SHADOW")
            net_cost = sum(trait_catalog[idx][1] for idx in chosen)
            if net_cost > 1:
                for cand in shadow_pool:
                    if cand not in chosen:
                        chosen[0] = cand
                        break
            shadow_count = sum(1 for idx in chosen if trait_catalog[idx][2] == "SHADOW")
            net_cost = sum(trait_catalog[idx][1] for idx in chosen)

        assert len(chosen) in (2, 3), f"H3 invariant failed len: {chosen}"
        assert len(set(chosen)) == len(chosen), f"H3 invariant failed unique: {chosen}"
        assert shadow_count >= 1, f"H3 invariant failed shadow_count: {chosen}"
        assert -1 <= net_cost <= 1, f"H3 invariant failed net_cost={net_cost}: {chosen}"

        stats = normalize_weights_320(raw_weights)
        passion_alloc: Dict[int, int] = {p1: 2, p2: 1} if p3 == 10 else {p1: 1, p2: 1, p3: 1}
        passion_points = sum(passion_alloc.values())
        assert passion_points == 3

        return True, "OK", {
            "effective_mode": effective_mode,
            "beta_ai": beta_ai,
            "import_audit_status": audit_status,
            "coercion_flag": coercion_flag,
            "normalized_stats": stats,
            "passion_alloc": passion_alloc,
            "passion_points": passion_points,
            "traits": [trait_catalog[i][0] for i in chosen],
            "shadow_count": shadow_count,
            "net_trait_cost": net_cost,
        }

    def make_store(cid: str, player_id: str, issued: int = 1000) -> Dict[str, dict]:
        return {
            cid: {
                "player_id": player_id,
                "issued_at_tick": issued,
                "ttl_expires_tick": issued + challenge_ttl_ticks,
                "status": "ISSUED",
                "attempt_count": 0,
                "max_attempts": 3,
                "cooldown_until_tick": 0,
            }
        }

    # (a) Valid worked example TK3K2-7R4M9P-ME1KPF-AMXAV0-A00G-N4
    worked_v = [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 0]
    worked_tok = encode_tk3k2("7R4M9P", "player_demo_01", worked_v)
    store_a = make_store("7R4M9P", "player_demo_01", 1000)
    ok_a, code_a, res_a = decode_and_verify(
        f"<<<TK3K_PERSONA_V2>>>\n{worked_tok}\n<<<END_TK3K_PERSONA_V2>>>",
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        store_a,
        {},
    )
    suite_a_ok = (
        worked_tok == "TK3K2-7R4M9P-ME1KPF-AMXAV0-A00G-N4"
        and ok_a
        and code_a == "OK"
        and res_a is not None
        and res_a["normalized_stats"] == [64, 52, 75, 70, 59]
        and sum(res_a["normalized_stats"]) == 320
        and all(35 <= s <= 85 for s in res_a["normalized_stats"])
        and res_a["passion_points"] == 3
        and res_a["passion_alloc"] == {2: 2, 3: 1}
        and res_a["shadow_count"] == 2
        and res_a["net_trait_cost"] == -1
        and store_a["7R4M9P"]["status"] == "CONSUMED"
    )

    # (b) Single-char mutation (K->J) & adjacent transposition rejected with ERR_TOKEN_TAMPERED
    store_b = make_store("7R4M9P", "player_demo_01", 1000)
    tok_mut = "TK3K2-7R4M9P-ME1JPF-AMXAV0-A00G-N4"
    tok_trans = "TK3K2-7R4M9P-EM1KPF-AMXAV0-A00G-N4"
    ok_b1, code_b1, _ = decode_and_verify(tok_mut, "player_demo_01", "FUSION_INTERVIEW", 1200, store_b, {})
    ok_b2, code_b2, _ = decode_and_verify(tok_trans, "player_demo_01", "FUSION_INTERVIEW", 1201, store_b, {})
    suite_b_ok = (
        (not ok_b1 and code_b1 == "ERR_TOKEN_TAMPERED")
        and (not ok_b2 and code_b2 == "ERR_TOKEN_TAMPERED")
        and store_b["7R4M9P"]["attempt_count"] == 2
    )

    # (c) Plaintext JSON, braceless KV smuggling, >4096B payload, and duplicate envelope blocks rejected
    ok_c1, code_c1, _ = decode_and_verify(
        '{"schema_version":"AI_PERSONA_EXPORT_V1","persona_weights":{"lea":99,"mar":99}}',
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("7R4M9P", "player_demo_01"),
        {},
    )
    ok_c2, code_c2, _ = decode_and_verify(
        f'"lea": 99, "mar": 99\n<<<TK3K_PERSONA_V2>>>\n{worked_tok}\n<<<END_TK3K_PERSONA_V2>>>',
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("7R4M9P", "player_demo_01"),
        {},
    )
    ok_c3, code_c3, _ = decode_and_verify(
        ("A" * 4100) + f"\n<<<TK3K_PERSONA_V2>>>\n{worked_tok}\n<<<END_TK3K_PERSONA_V2>>>",
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("7R4M9P", "player_demo_01"),
        {},
    )
    ok_c4, code_c4, _ = decode_and_verify(
        f"<<<TK3K_PERSONA_V2>>>\n{worked_tok}\n<<<END_TK3K_PERSONA_V2>>>\n"
        f"<<<TK3K_PERSONA_V2>>>\n{worked_tok}\n<<<END_TK3K_PERSONA_V2>>>",
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("7R4M9P", "player_demo_01"),
        {},
    )
    suite_c_ok = (
        (not ok_c1 and code_c1 == "ERR_PLAINTEXT_JSON_FORBIDDEN")
        and (not ok_c2 and code_c2 == "ERR_PLAINTEXT_JSON_FORBIDDEN")
        and (not ok_c3 and code_c3 == "ERR_TOKEN_FORMAT")
        and (not ok_c4 and code_c4 == "ERR_TOKEN_FORMAT")
    )

    # (d) Unknown / Ownership / Expired (including earlier-tick resubmission) / Replayed / Escalating Cooldown (300->900->3600)
    ok_d_unk, code_d_unk, _ = decode_and_verify(worked_tok, "player_demo_01", "FUSION_INTERVIEW", 1200, {}, {})
    ok_d_own, code_d_own, _ = decode_and_verify(
        worked_tok, "player_other", "FUSION_INTERVIEW", 1200, make_store("7R4M9P", "player_demo_01", 1000), {}
    )
    store_d_exp = make_store("7R4M9P", "player_demo_01", 1000)
    ok_d_exp, code_d_exp, _ = decode_and_verify(
        worked_tok, "player_demo_01", "FUSION_INTERVIEW", 1901, store_d_exp, {}
    )
    # Regression: once EXPIRED, resubmitting at an earlier tick (1800 <= 1900) MUST still return ERR_CHALLENGE_EXPIRED
    ok_d_exp_early, code_d_exp_early, _ = decode_and_verify(
        worked_tok, "player_demo_01", "FUSION_INTERVIEW", 1800, store_d_exp, {}
    )
    ok_d_rep, code_d_rep, _ = decode_and_verify(worked_tok, "player_demo_01", "FUSION_INTERVIEW", 1205, store_a, {})
    ok_d_cd, code_d_cd, _ = decode_and_verify(
        worked_tok,
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("7R4M9P", "player_demo_01", 1000),
        {"player_demo_01": 1500},
    )
    # Escalating tamper cooldown verification: 300 -> 900 -> 3600
    strikes_d: Dict[str, int] = {}
    cd_d_esc: Dict[str, int] = {}
    esc_observed: List[int] = []
    for idx_esc, (cid_esc, tick_esc) in enumerate([("CHESC1", 1000), ("CHESC2", 2000), ("CHESC3", 4000)]):
        st_esc = make_store(cid_esc, "player_esc", tick_esc)
        bad_tok_esc = encode_tk3k2(cid_esc, "player_esc", worked_v)[:-1] + (
            "0" if encode_tk3k2(cid_esc, "player_esc", worked_v)[-1] != "0" else "1"
        )
        for attempt_offset in range(3):
            decode_and_verify(
                bad_tok_esc,
                "player_esc",
                "FUSION_INTERVIEW",
                tick_esc + 10 + attempt_offset,
                st_esc,
                cd_d_esc,
                strikes_d,
            )
        esc_observed.append(cd_d_esc["player_esc"] - (tick_esc + 12))
    suite_d_ok = (
        not ok_d_unk and code_d_unk == "ERR_CHALLENGE_UNKNOWN"
        and not ok_d_own and code_d_own == "ERR_CHALLENGE_OWNERSHIP"
        and not ok_d_exp and code_d_exp == "ERR_CHALLENGE_EXPIRED"
        and not ok_d_exp_early and code_d_exp_early == "ERR_CHALLENGE_EXPIRED"
        and not ok_d_rep and code_d_rep == "ERR_CHALLENGE_REPLAYED"
        and not ok_d_cd and code_d_cd == "ERR_CHALLENGE_COOLDOWN"
        and esc_observed == [300, 900, 3600]
    )

    # (e) Coercion flags R0..R3
    v_r1 = [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 1]
    v_r2 = [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 2]
    v_r3 = [3, 18, 8, 26, 22, 14, 2, 3, 10, 2, 9, 1, 2, 1, 1, 3]
    ok_e1, code_e1, res_e1 = decode_and_verify(
        encode_tk3k2("CHR100", "player_demo_01", v_r1),
        "player_demo_01",
        "AI_DIRECT_WITH_CONFIRM",
        1200,
        make_store("CHR100", "player_demo_01", 1000),
        {},
    )
    store_e2 = make_store("CHR200", "player_demo_01", 1000)
    ok_e2, code_e2, res_e2 = decode_and_verify(
        encode_tk3k2("CHR200", "player_demo_01", v_r2),
        "player_demo_01",
        "AI_DIRECT_WITH_CONFIRM",
        1200,
        store_e2,
        {},
    )
    cd_e3: Dict[str, int] = {}
    store_e3 = make_store("CHR300", "player_demo_01", 1000)
    ok_e3, code_e3, res_e3 = decode_and_verify(
        encode_tk3k2("CHR300", "player_demo_01", v_r3),
        "player_demo_01",
        "AI_DIRECT_WITH_CONFIRM",
        1200,
        store_e3,
        cd_e3,
    )
    suite_e_ok = (
        ok_e1 and code_e1 == "OK" and res_e1 is not None
        and res_e1["import_audit_status"] == "DOWNGRADED_ANOMALY"
        and res_e1["effective_mode"] == "FUSION_INTERVIEW"
        and res_e1["beta_ai"] == 2000
        and not ok_e2 and code_e2 == "ERR_COERCION_REJECTED"
        and store_e2["CHR200"]["status"] == "REVOKED_TAMPER"
        and store_e2["CHR200"].get("last_reject_reason") == "ERR_COERCION_REJECTED:R2_STAT_COERCION"
        and not ok_e3 and code_e3 == "ERR_COERCION_REJECTED"
        and store_e3["CHR300"]["status"] == "REVOKED_TAMPER"
        and store_e3["CHR300"].get("last_reject_reason") == "ERR_COERCION_REJECTED:R3_PROMPT_INJECTION"
        and cd_e3.get("player_demo_01") == 3000
        and res_e2 is not None and res_e3 is not None and res_e3["cooldown_applied"]
    )

    # (f) Zero-trust anomalies with R0_CLEAN: flat [30]*5, extreme bimodal [30,30,1,1,1],
    # explicit all-Light (0,5,9), 3-Shadow (1,2,3), 2-Shadow (1,10,2), plus exhaustive ALL 1,100 trait triples
    v_flat = [3, 30, 30, 30, 30, 30, 0, 1, 10, 2, 9, 1, 2, 1, 1, 0]
    v_bimo = [3, 30, 30, 1, 1, 1, 0, 1, 10, 2, 9, 1, 1, 0, 0, 0]
    v_all_light = [3, 18, 8, 26, 22, 14, 2, 3, 10, 0, 5, 9, 2, 1, 1, 0]
    v_all_shadow_3 = [3, 18, 8, 26, 22, 14, 2, 3, 10, 1, 2, 3, 2, 1, 1, 0]
    v_all_shadow_2 = [3, 18, 8, 26, 22, 14, 2, 3, 10, 1, 10, 2, 2, 1, 1, 0]

    ok_f1, _, res_f1 = decode_and_verify(
        encode_tk3k2("CHF100", "player_demo_01", v_flat),
        "player_demo_01",
        "AI_DIRECT_WITH_CONFIRM",
        1200,
        make_store("CHF100", "player_demo_01", 1000),
        {},
    )
    ok_f2, _, res_f2 = decode_and_verify(
        encode_tk3k2("CHF200", "player_demo_01", v_bimo),
        "player_demo_01",
        "AI_DIRECT_WITH_CONFIRM",
        1200,
        make_store("CHF200", "player_demo_01", 1000),
        {},
    )
    ok_f3, _, res_f3 = decode_and_verify(
        encode_tk3k2("CHF300", "player_demo_01", v_all_light),
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("CHF300", "player_demo_01", 1000),
        {},
    )
    ok_f4, _, res_f4 = decode_and_verify(
        encode_tk3k2("CHF400", "player_demo_01", v_all_shadow_3),
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("CHF400", "player_demo_01", 1000),
        {},
    )
    ok_f5, _, res_f5 = decode_and_verify(
        encode_tk3k2("CHF500", "player_demo_01", v_all_shadow_2),
        "player_demo_01",
        "FUSION_INTERVIEW",
        1200,
        make_store("CHF500", "player_demo_01", 1000),
        {},
    )

    # Exhaustive test across ALL 10 x 11 x 10 = 1,100 (t1, t2, t_shadow) triples
    exhaustive_invalid_domain = 0
    exhaustive_valid_domain = 0
    exhaustive_failures = 0
    for t1_val in range(10):
        for t2_val in range(11):
            for ts_val in range(10):
                vec_t = [3, 18, 8, 26, 22, 14, 2, 3, 10, t1_val, t2_val, ts_val, 2, 1, 1, 0]
                tok_t = encode_tk3k2("CHEXH1", "player_demo_01", vec_t)
                ok_t, code_t, res_t = decode_and_verify(
                    tok_t,
                    "player_demo_01",
                    "FUSION_INTERVIEW",
                    1200,
                    make_store("CHEXH1", "player_demo_01", 1000),
                    {},
                )
                is_valid_domain = (t2_val == 10 or t2_val != t1_val) and (ts_val not in (t1_val, t2_val))
                if not is_valid_domain:
                    if not ok_t and code_t == "ERR_TOKEN_DOMAIN":
                        exhaustive_invalid_domain += 1
                    else:
                        exhaustive_failures += 1
                else:
                    if (
                        ok_t
                        and res_t is not None
                        and len(res_t["traits"]) in (2, 3)
                        and len(set(res_t["traits"])) == len(res_t["traits"])
                        and res_t["shadow_count"] >= 1
                        and -1 <= res_t["net_trait_cost"] <= 1
                    ):
                        exhaustive_valid_domain += 1
                    else:
                        exhaustive_failures += 1

    exhaustive_1100_ok = (
        exhaustive_invalid_domain == 290
        and exhaustive_valid_domain == 810
        and exhaustive_failures == 0
    )

    suite_f_ok = (
        ok_f1 and res_f1 is not None
        and res_f1["import_audit_status"] == "DOWNGRADED_ANOMALY"
        and res_f1["normalized_stats"] == [64, 64, 64, 64, 64]
        and ok_f2 and res_f2 is not None
        and res_f2["import_audit_status"] == "DOWNGRADED_ANOMALY"
        and res_f2["effective_mode"] == "FUSION_INTERVIEW"
        and sum(res_f2["normalized_stats"]) == 320
        and all(35 <= s <= 85 for s in res_f2["normalized_stats"])
        and ok_f3 and res_f3 is not None
        and res_f3["import_audit_status"] == "DOWNGRADED_ANOMALY"
        and res_f3["shadow_count"] >= 1
        and -1 <= res_f3["net_trait_cost"] <= 1
        and ok_f4 and res_f4 is not None
        and res_f4["import_audit_status"] == "DOWNGRADED_ANOMALY"
        and res_f4["shadow_count"] == 2
        and res_f4["net_trait_cost"] == -1
        and len(res_f4["traits"]) == 3
        and ok_f5 and res_f5 is not None
        and res_f5["import_audit_status"] == "DOWNGRADED_ANOMALY"
        and res_f5["shadow_count"] == 1
        and res_f5["net_trait_cost"] == 0
        and len(res_f5["traits"]) == 2
        and exhaustive_1100_ok
    )

    passed = suite_a_ok and suite_b_ok and suite_c_ok and suite_d_ok and suite_e_ok and suite_f_ok
    return passed, {
        "suite_a_valid_worked_example": suite_a_ok,
        "suite_b_tamper_and_transposition_rejected": suite_b_ok,
        "suite_c_plaintext_json_and_envelope_rejected": suite_c_ok,
        "suite_d_challenge_lifecycle_and_escalation_enforced": suite_d_ok,
        "suite_e_coercion_r0_r3_policy": suite_e_ok,
        "suite_f_zero_trust_anomalies_and_exhaustive_1100_traits": suite_f_ok,
        "exhaustive_1100_triples_summary": {
            "invalid_domain_rejected": exhaustive_invalid_domain,
            "valid_domain_verified": exhaustive_valid_domain,
            "failures": exhaustive_failures,
        },
        "worked_token": worked_tok,
        "worked_normalized_stats": res_a["normalized_stats"] if res_a else None,
        "passed": passed,
    }


def main() -> int:
    docs_ok, docs_report = verify_documents()
    feat_ok, feat_report = verify_feature_coverage()
    sql_ok, sql_report = verify_sqlite_schema()
    math_ok, math_report = verify_math_invariants()
    seal_ok, seal_report = verify_sealed_token_decoder()

    overall_passed = docs_ok and feat_ok and sql_ok and math_ok and seal_ok

    summary = {
        "milestone": "M0",
        "feature_id": "FH-00",
        "overall_passed": overall_passed,
        "checks": {
            "1_documents_completeness": docs_report,
            "2_feature_inventory_coverage": feat_report,
            "3_sqlite_world_state_schema": sql_report,
            "4_deterministic_math_invariants": math_report,
            "5_sealed_token_decoder_security": seal_report,
        },
    }

    print(json.dumps(summary, indent=2, ensure_ascii=False))
    if not overall_passed:
        print("\n[VERIFY_BLUEPRINT] FAILED: One or more M0 blueprint checks failed.", file=sys.stderr)
        return 1

    print(
        "\n[VERIFY_BLUEPRINT] PASSED (100%): All 5 blueprint docs, 52 features (FH-00..FH-06, F-01..F-45), "
        "10 SQLite tables (+ negative CHECK/FK constraints), 5 deterministic math invariants, and 6 TK3K2 sealed-token security suites verified."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
