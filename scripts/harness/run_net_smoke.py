#!/usr/bin/env python3
"""Stage 4 End-to-End Multiplayer Smoke Orchestrator (FH-06)."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import time
from typing import Any, Dict, List


REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT_BIN = shutil.which("godot") or os.path.expanduser("~/.local/bin/godot")
NET_HARNESS_RES = "res://tools/harness/net_harness.gd"
AUDIT_VERIFIER_PY = os.path.join(REPO_ROOT, "tools", "harness", "audit_verifier.py")


def allocate_ephemeral_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def remove_file_set(base_path: str) -> None:
    for suffix in ("", "-wal", "-shm", ".tmp"):
        p = base_path + suffix
        if os.path.exists(p):
            os.remove(p)


def run_step(cmd: List[str], timeout_sec: int, label: str) -> subprocess.CompletedProcess[str]:
    print(f"[run_net_smoke] >>> {label}: {' '.join(cmd)}", flush=True)
    proc = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=timeout_sec,
        check=False,
    )
    if proc.stdout:
        print(proc.stdout.rstrip(), flush=True)
    if proc.stderr:
        print(proc.stderr.rstrip(), file=sys.stderr, flush=True)
    return proc


def main() -> int:
    if not os.path.isfile(GODOT_BIN) and not shutil.which(GODOT_BIN):
        print(f"[run_net_smoke] ERROR: Godot binary not found at {GODOT_BIN}", file=sys.stderr)
        return 1

    os.makedirs(os.path.join(REPO_ROOT, "saves"), exist_ok=True)
    os.makedirs(os.path.join(REPO_ROOT, "reports"), exist_ok=True)

    loopback_db = "saves/world_state.db"
    loopback_wal = "saves/wal_commands.jsonl"
    loopback_snap = "saves/world_snapshot.json"
    loopback_report = "reports/net_loopback_report.json"

    # Step 1: In-process loopback smoke harness (48+ ticks, full shared-world + anti-cheat + F-38/F-39)
    p1 = run_step(
        [
            GODOT_BIN,
            "--headless",
            "--path",
            ".",
            "-s",
            NET_HARNESS_RES,
            "--",
            "--mode=loopback",
            "--seed=18401",
            "--ticks=48",
            f"--db={loopback_db}",
            f"--wal={loopback_wal}",
            f"--snapshot={loopback_snap}",
            f"--out={loopback_report}",
        ],
        timeout_sec=60,
        label="Step 1: Loopback Harness",
    )
    if p1.returncode != 0:
        print(f"[run_net_smoke] FAIL: Step 1 loopback exited with {p1.returncode}", file=sys.stderr)
        return p1.returncode

    # Step 2: Forensic SQLite audit on loopback DB
    p2 = run_step(
        [
            sys.executable,
            AUDIT_VERIFIER_PY,
            "--db",
            os.path.join(REPO_ROOT, loopback_db),
            "--out",
            os.path.join(REPO_ROOT, "reports", "audit_loopback_report.json"),
        ],
        timeout_sec=30,
        label="Step 2: Loopback SQLite Forensic Audit",
    )
    if p2.returncode != 0:
        print(f"[run_net_smoke] FAIL: Step 2 audit_verifier exited with {p2.returncode}", file=sys.stderr)
        return p2.returncode

    # Step 3: Real localhost WebSocket multi-process server + 3 isolated bot clients
    port = allocate_ephemeral_port()
    ws_db = "/tmp/ws_smoke_world.db"
    ws_wal = "/tmp/ws_smoke_wal.jsonl"
    ws_snap = "/tmp/ws_smoke_snapshot.json"
    ws_srv_report = "/tmp/ws_smoke_server_report.json"
    ws_audit_report = "/tmp/ws_smoke_audit_report.json"
    bot_ids = ["lord_A", "ally_B", "raider_C"]
    bot_user_dirs = [f"/tmp/godot_bot_{bid}" for bid in bot_ids]
    bot_reports = {bid: f"/tmp/ws_smoke_bot_{bid}.json" for bid in bot_ids}
    srv_user_dir = "/tmp/godot_ws_server"

    remove_file_set(ws_db)
    remove_file_set(ws_wal)
    remove_file_set(ws_snap)
    for p in [ws_srv_report, ws_audit_report] + list(bot_reports.values()):
        if os.path.exists(p):
            os.remove(p)

    for udir in [srv_user_dir] + bot_user_dirs:
        shutil.rmtree(udir, ignore_errors=True)
        os.makedirs(udir, exist_ok=True)

    srv_proc: subprocess.Popen[str] | None = None
    bot_procs: Dict[str, subprocess.Popen[str]] = {}

    try:
        print(f"[run_net_smoke] >>> Step 3: Launching WebSocket Server on 127.0.0.1:{port}", flush=True)
        srv_cmd = [
            GODOT_BIN,
            "--headless",
            "--user-data-dir",
            srv_user_dir,
            "--path",
            ".",
            "-s",
            NET_HARNESS_RES,
            "--",
            "--mode=server",
            "--seed=18401",
            "--ticks=24",
            f"--port={port}",
            "--expected-clients=3",
            f"--db={ws_db}",
            f"--wal={ws_wal}",
            f"--snapshot={ws_snap}",
            f"--out={ws_srv_report}",
        ]
        srv_proc = subprocess.Popen(
            srv_cmd,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # Wait briefly until TCP socket is listening on 127.0.0.1:port
        deadline = time.monotonic() + 10.0
        listening = False
        while time.monotonic() < deadline:
            if srv_proc.poll() is not None:
                break
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                probe.settimeout(0.2)
                if probe.connect_ex(("127.0.0.1", port)) == 0:
                    listening = True
                    break
            time.sleep(0.1)

        if not listening:
            out_s, err_s = srv_proc.communicate(timeout=5)
            print(out_s, flush=True)
            print(err_s, file=sys.stderr, flush=True)
            print("[run_net_smoke] FAIL: WebSocket server did not start listening in time", file=sys.stderr)
            return 1

        # Launch 3 isolated bot client processes
        for bid, udir in zip(bot_ids, bot_user_dirs):
            bot_cmd = [
                GODOT_BIN,
                "--headless",
                "--user-data-dir",
                udir,
                "--path",
                ".",
                "-s",
                NET_HARNESS_RES,
                "--",
                "--mode=client",
                f"--port={port}",
                f"--bot={bid}",
                f"--out={bot_reports[bid]}",
            ]
            print(f"[run_net_smoke] >>> Launching bot client {bid} (user-data-dir={udir})", flush=True)
            bot_procs[bid] = subprocess.Popen(
                bot_cmd,
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

        all_ok = True
        for bid, bproc in bot_procs.items():
            b_out, b_err = bproc.communicate(timeout=30)
            if b_out:
                print(b_out.rstrip(), flush=True)
            if b_err:
                print(b_err.rstrip(), file=sys.stderr, flush=True)
            if bproc.returncode != 0:
                print(f"[run_net_smoke] FAIL: Bot {bid} exited with {bproc.returncode}", file=sys.stderr)
                all_ok = False

        s_out, s_err = srv_proc.communicate(timeout=30)
        if s_out:
            print(s_out.rstrip(), flush=True)
        if s_err:
            print(s_err.rstrip(), file=sys.stderr, flush=True)
        if srv_proc.returncode != 0:
            print(f"[run_net_smoke] FAIL: WebSocket server exited with {srv_proc.returncode}", file=sys.stderr)
            all_ok = False

        if not all_ok:
            return 1

        # Audit the WebSocket multi-process DB
        p_ws_audit = run_step(
            [
                sys.executable,
                AUDIT_VERIFIER_PY,
                "--db",
                ws_db,
                "--out",
                ws_audit_report,
            ],
            timeout_sec=30,
            label="Step 3b: WebSocket DB Forensic Audit",
        )
        if p_ws_audit.returncode != 0:
            print(f"[run_net_smoke] FAIL: WebSocket DB audit exited with {p_ws_audit.returncode}", file=sys.stderr)
            return p_ws_audit.returncode

        summary: Dict[str, Any] = {
            "schema_version": "1.0",
            "step1_loopback_passed": True,
            "step2_loopback_audit_passed": True,
            "step3_websocket_multiprocess_passed": True,
            "ws_port": port,
            "loopback_db": os.path.join(REPO_ROOT, loopback_db),
            "overall_passed": True,
        }
        summary_path = os.path.join(REPO_ROOT, "reports", "net_smoke_summary.json")
        with open(summary_path, "w", encoding="utf-8") as sf:
            json.dump(summary, sf, indent=2)
            sf.write("\n")

        print("[run_net_smoke] ALL STAGE 4 CHECKS PASSED.")
        return 0
    finally:
        for bproc in bot_procs.values():
            if bproc.poll() is None:
                bproc.kill()
        if srv_proc is not None and srv_proc.poll() is None:
            srv_proc.kill()
        for udir in [srv_user_dir] + bot_user_dirs:
            shutil.rmtree(udir, ignore_errors=True)
        remove_file_set(ws_db)
        remove_file_set(ws_wal)
        remove_file_set(ws_snap)
        for p in [ws_srv_report, ws_audit_report] + list(bot_reports.values()):
            if os.path.exists(p):
                os.remove(p)


if __name__ == "__main__":
    sys.exit(main())
