# 01. AI 에이전트 기반 Godot 4 개발 및 4단계 헤드리스 검증 하네스 명세서 (AI Agent Harness Specification)

- **문서 버전**: `v1.0.0` (Milestone `M0` / Feature `FH-00`)
- **대상 프로젝트**: 삼국지 × 림월드 공유 월드 방치형 게임 (Three Kingdoms × RimWorld Shared-World Idle Game in Godot 4)
- **관련 기능 ID**: `FH-00`, `FH-01`, `FH-02`, `FH-03`, `FH-04`, `FH-05`, `FH-06`, `F-42`, `F-43`, `F-44`, `F-45`

---

## 1. 개요 및 설계 목적 (Executive Summary)

본 문서는 **삼국지(Romance of the Three Kingdoms) × 림월드(RimWorld) 공유 월드 멀티플레이어 방치형 게임**을 **Godot 4 엔진** 위에서 **100% 자율 AI 에이전트 협업(Orchestrator, Explorer, Worker, Test Writer, Reviewer, Challenger, Forensic Auditor)** 으로 개발·검증하기 위한 **기술 하네스(Harness) 표준 명세**를 정의한다.

GUI 에디터 의존성이나 `.tscn` 씬 파일 병합 충돌(Merge Conflict), 비결정론적 부동소수점/난수 드리프트, 혹은 거짓 통과(Vacuous/Hardcoded Test)를 원천 차단하기 위해 본 하네스는 다음 4대 원칙을 강제한다:

1. **사용자 공간(User-Space) 재현 가능 Godot 4 툴체인 부트스트랩 (`FH-01`)**: 루트(`sudo`) 권한 없이 `/home/antigravity/.local/bin/godot`에 공식 Linux `x86_64` 바이너리를 설치하고 `SHA-512` 해시를 검증한다.
2. **3계층 코드 우선 / 텍스트 안전 아키텍처 (3-Layer Code-First / Text-Safe Architecture)**:
   - **Layer 1**: `RefCounted` 기반 순수 헤드리스 시뮬레이션 및 프로토콜 커널 (`src/core/`, `src/micro/`, `src/macro/`, `src/faction/`, `src/net/`, `src/persistence/`)
   - **Layer 2**: 순수 UTF-8 선언형 데이터 및 스키마 (`data/*.json`, `data/schemas/world_state_schema.sql` — 바이너리 `.tres` 및 `uid://` 의존성 배제)
   - **Layer 3**: 30줄 미만의 최소 부트스트랩 씬 셸(`scenes/main_client.tscn`, `scenes/headless_server.tscn`) + 순수 GDScript 프로그래밍 방식 UI 뷰(`src/ui/`)
3. **4단계 헤드리스 CLI 자동 검증 파이프라인 (`FH-02`..`FH-06`)**:
   - **Stage 1 (`check_syntax.sh` & `validate_data.gd`)**: 글로벌 클래스 캐시 예열 + 엄격 정적 타입 검사(`--check-only`) + JSON/SQL 스키마 무결성 검증
   - **Stage 2 (`run_tests.sh`, `test_case.gd`, `test_runner.gd`)**: 무의미한 테스트(0-Assertion) 거부 기능을 갖춘 자체 내장형 `SceneTree` 유닛/통합 테스트 러너
   - **Stage 3 (`sim_harness.gd` & `run_sim.sh`)**: 시드 기반 결정론적 리플레이(`--verify-determinism`), `LOD 0` ↔ `LOD 1` 오프라인 동치성(`--verify-offline-equivalence`), 도메인 불변식(Invariants) 검증
   - **Stage 4 (`net_harness.gd`, `run_net_smoke.py`, `audit_verifier.py`)**: 1개 권위 서버 + $N$개 자율 군웅 봇 클라이언트 간 공유 월드 상호작용 및 `/usr/bin/sqlite3` 감사 DB 검증
4. **에이전트 역할 분리 및 포렌식 감사(Forensic Audit) 반칙 방지 게이트**: 모듈별 배타적 쓰기 권한(Disjoint Write-Ownership)과 정규식/시드 교란(Adversarial Seed Perturbation) 검사를 통해 하드코딩 및 치팅을 완벽히 적발한다.

---

## 2. 실행 환경 및 툴체인 베이스라인 (Environment & Toolchain Baseline — `FH-01`)

### 2.1 호스트 하드웨어 및 OS 검증 사양

Step 0 환경 실사(`survey_1`, `survey_3`)를 통해 검증된 개발 컨테이너 사양은 다음과 같다:

| 구분 | 검증된 환경 값 | 검증 명령어 | 비고 |
|---|---|---|---|
| **운영체제 (OS)** | `Debian GNU/Linux 12 (bookworm)` | `cat /etc/os-release` | `x86_64` 아키텍처 |
| **커널 (Kernel)** | `Linux 6.12.105+ #1 SMP x86_64 GNU/Linux` | `uname -a` | POSIX 소켓 및 프로세스 격리 지원 |
| **사용자 권한** | `uid=1000(antigravity) gid=1000(antigravity)` | `id && sudo -n true` | Passwordless `sudo` 없음 (User-Space 설치 필수) |
| **CPU** | `2 vCPUs` (`Intel(R) Xeon(R) Platinum 8481C`) | `nproc && lscpu` | 헤드리스 틱 연산 및 멀티프로세스 테스트 적합 |
| **메모리 (RAM)** | `7.8 GiB` Total (`~7.0 GiB` Available) | `free -h` | 인메모리 시뮬레이션 및 SQLite WAL 충분 |
| **워크스페이스 디스크** | `/home/antigravity` — `20 GiB` (`19.5 GiB` Free) | `df -h /home/antigravity` | 영구 볼륨 (`/dev/mapper/ace_vg-persist_lv`) |
| **사전 설치 런타임** | `python3 3.11.2`, `sqlite3 3.40.1`, `node v24.22.3`, `rustc 1.100.0`, `gcc 12.2.0`, `jq 1.6`, `curl 7.88.1`, `xvfb-run` | `python3 --version && sqlite3 --version` | 외부 C++ GDExtension 없이 `/usr/bin/sqlite3` 직접 연동 |
| **Godot 필수 공유 라이브러리** | `libX11.so.6`, `libXcursor.so.1`, `libXinerama.so.1`, `libXrandr.so.2`, `libXi.so.6`, `libGL.so.1`, `libvulkan.so.1`, `libasound.so.2`, `libpulse.so.0`, `libfontconfig.so.1` | `ldconfig -p` | Godot 4 공식 바이너리 즉시 실행 가능 (100% 충족) |
| **로컬호스트 네트워킹** | `127.0.0.1` TCP 및 UDP 에페메랄 포트 바인딩 성공 | `python3 -c 'import socket...'` | `WebSocketMultiplayerPeer` 및 `ENetMultiplayerPeer` 구동 가능 |

### 2.2 Godot 4 공식 바이너리 부트스트랩 스크립트 (`scripts/setup_godot.sh`)

루트 권한 없이 사용자 공간(`/home/antigravity/.local/bin/godot`)에 공식 Godot 4 Linux `x86_64` 바이너리를 설치하고 `SHA-512` 체크섬을 검증한다. 안정성이 검증된 LTS 기준선 **`4.4.1-stable`** 과 최신 **`4.7.2-stable`** 을 모두 지원한다.

- **`4.4.1-stable` SHA-512**:
  `ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e`
- **`4.7.2-stable` SHA-512**:
  `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`

```bash
#!/usr/bin/env bash
# File: scripts/setup_godot.sh
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4.1-stable}"
INSTALL_DIR="${HOME}/.local/bin"
CACHE_DIR="${HOME}/.cache/godot_downloads"

mkdir -p "${INSTALL_DIR}" "${CACHE_DIR}"

if [[ "${GODOT_VERSION}" == "4.4.1-stable" ]]; then
    EXPECTED_SHA512="ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e"
elif [[ "${GODOT_VERSION}" == "4.7.2-stable" ]]; then
    EXPECTED_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
else
    echo "ERROR: Unsupported GODOT_VERSION=${GODOT_VERSION}" >&2
    exit 1
fi

ZIP_NAME="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
BIN_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
ZIP_PATH="${CACHE_DIR}/${ZIP_NAME}"
DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ZIP_NAME}"

if [[ ! -x "${INSTALL_DIR}/godot" ]] || ! "${INSTALL_DIR}/godot" --version 2>/dev/null | grep -q "^${GODOT_VERSION%-stable}"; then
    echo "[setup_godot] Downloading ${DOWNLOAD_URL} ..."
    curl -fsSL "${DOWNLOAD_URL}" -o "${ZIP_PATH}"
    echo "${EXPECTED_SHA512}  ${ZIP_PATH}" | sha512sum -c -
    unzip -q -o "${ZIP_PATH}" -d "${CACHE_DIR}"
    chmod +x "${CACHE_DIR}/${BIN_NAME}"
    mv "${CACHE_DIR}/${BIN_NAME}" "${INSTALL_DIR}/godot"
    ln -sf "${INSTALL_DIR}/godot" "${INSTALL_DIR}/godot4"
    rm -f "${ZIP_PATH}"
fi

export PATH="${INSTALL_DIR}:${PATH}"
echo "[setup_godot] Installed Godot version: $(godot --version)"
```

### 2.3 엄격한 GDScript 정적 타입 강제 설정 (`project.godot`)

AI 에이전트가 작성한 코드에서 런타임 `Nil` 참조나 오타로 인한 속성 접근 오류를 컴파일 타임(`--check-only`)에 100% 잡아내기 위해, `project.godot`의 `[debug]` 섹션에 다음 경고-에러 격상(`=2`, Treat as Error) 플래그를 의무화한다:

```ini
; File: project.godot
config_version=5

[application]
config/name="Three Kingdoms x RimWorld Shared-World Idle"
run/main_scene="res://scenes/main_client.tscn"
config/features=PackedStringArray("4.4", "Forward Plus")

[debug]
gdscript/warnings/enable=true
gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=0
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_cast=2
gdscript/warnings/unsafe_call_argument=2
gdscript/warnings/return_value_discarded=1
```

---

## 3. 3계층 코드 우선 / 텍스트 안전 아키텍처 (3-Layer Code-First / Text-Safe Architecture)

다수의 AI 에이전트가 병렬로 작업할 때 `.tscn` 및 `.tres` 파일 내부의 직렬화된 서브 리소스와 임의 생성 `uid://` 식별자는 심각한 병합 충돌과 참조 깨짐을 유발한다. 이를 방지하기 위해 전체 코드베이스를 다음 3계층으로 분리한다:

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ LAYER 3: 씬 셸 및 프로그래밍 방식 UI 뷰 (src/ui/, scenes/)                    │
│ - scenes/main_client.tscn, scenes/headless_server.tscn (각 30줄 미만 정적 셸) │
│ - 모든 UI 위젯(32x32 장원 그리드, 우선순위 매트릭스, 천하 전략도, 조보 모달)은 │
│   순수 GDScript(src/ui/*.gd)에서 코드로 생성 및 바인딩                         │
│ - UI 스크립트 내부에서 시뮬레이션 상태 직접 변경 절대 금지 (Intent 명령만 전송)│
└───────────────────────────────────────┬───────────────────────────────────────┘
                                        │ 선언형 Intent 명령 / 읽기 전용 Snapshot
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ LAYER 1: 순수 헤드리스 시뮬레이션 및 프로토콜 커널                            │
│ (src/core/, src/micro/, src/macro/, src/faction/, src/net/, src/persistence/) │
│ - 모든 도메인 상태 및 틱 프로세서는 RefCounted 상속 (Node 상속 금지)          │
│ - int64 퍼밀/베이시스 포인트(1000 = 1.000) 고정소수점 연산 + SplitMix64 PRNG  │
│ - 정규 정렬 키(Canonical Sorted-Key) to_dict() / from_dict() 및 state_crc32   │
│ - 클라이언트, 헤드리스 서버, 유닛 테스트, sim_harness에서 100% 동일하게 실행  │
└───────────────────────────────────────┬───────────────────────────────────────┘
                                        │ 부팅 시 로드 및 스키마 검증
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│ LAYER 2: 선언형 정적 데이터 및 관계형 스키마 (data/)                          │
│ - 순수 UTF-8 JSON 데이터: data/macro_map_3k.json, data/officers_catalog.json, │
│   data/items_buildings.json, data/storytellers.json, data/scenarios/*.json    │
│ - 순수 SQL 스키마: data/schemas/world_state_schema.sql (10개 정규 테이블)     │
│ - 바이너리 .tres 또는 에디터 전용 리소스 직렬화 사용 금지                     │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 핵심 아키텍처 불변 규칙 (Mandatory Code-First Rules)

1. **`RefCounted` 순수 도메인 커널**:
   `src/core/`, `src/micro/`, `src/macro/`, `src/faction/` 내의 모든 클래스는 반드시 `extends RefCounted`를 선언하고 명시적 `class_name`을 가져야 하며, `to_dict() -> Dictionary` 및 `static func from_dict(data: Dictionary)`를 구현해야 한다.
2. **결정론적 정수 스케일링 (`int64` Permille / Basis Points)**:
   IEEE-754 `float` 누적 오차를 막기 위해 모든 자원량, 욕구(`0..10000`), 충성도(`0..10000`), 작업 진행도(`0..1000`), 시장 가격(`price_bp`)은 64비트 정수(`int`)로 저장하고 계산한다.
3. **시드 고정 결정론적 난수 (`DeterministicRNG`)**:
   시뮬레이션 모듈 내부에서 `randf()`, `randi()`, `randomize()` 호출을 엄격히 금지한다. 모든 확률 판정은 `(world_seed, tick_id, entity_id, salt)` 4-튜플을 입력받는 무상태 SplitMix64 함수 `DeterministicRNG.roll_range()`를 통과해야 한다.
4. **벽시계(Wall-Clock) 의존성 금지 및 세션 TTL 경계**:
   시뮬레이션 틱 로직(`src/micro/`, `src/macro/`, `src/faction/`) 내부에서 `Time.get_ticks_msec()`, `Time.get_unix_time_from_system()` 호출을 절대 금지한다. 모든 시뮬레이션 시간은 `SimClock`의 정수 `tick_id`로만 전진한다. 단, 네트워크/인증 경계(`src/net/`)의 일회성 Track B 챌린지(`persona_import_challenges`) 만료 검사는 라이브 서버에서는 벽시계 `900s`(`15분`) 또는 `SimClock` 틱을, 헤드리스 검증 하네스(`sim_harness` / `net_harness`)에서는 순수 `SimClock` 기반 `CHALLENGE_TTL_TICKS = 900` 마이크로 틱을 사용하여 결정론적 리플레이 순수성을 100% 보존한다.

---

## 4. 4단계 헤드리스 CLI 자동 검증 파이프라인 (4-Stage Headless CLI Verification Pipeline)

모든 코드 변경은 GUI 창 없이 `--headless` 모드로 동작하는 4단계 검증 파이프라인을 통과해야 하며, 각 단계는 POSIX 종료 코드(`0` = 성공, `1+` = 실패)와 구조화된 JSON 리포트를 출력한다.

### 4.1 Stage 1: 정적 문법, 엄격 타입 및 데이터 스키마 게이트 (`FH-02`)

- **구성 파일**: `scripts/harness/check_syntax.sh`, `tools/harness/validate_data.gd`
- **핵심 동작**:
  1. **글로벌 클래스 캐시 예열 (`--import --quit`)**: 클린 체크아웃 상태에서 파일 간 `class_name` 참조가 해석되도록 `.godot/global_script_class_cache.cfg`를 먼저 갱신한다.
  2. **엄격 정적 타입 및 문법 검사 (`--check-only`)**: `src/`, `tests/`, `tools/` 하위의 모든 `.gd` 파일에 대해 `godot --headless --path . --check-only -s <script>`를 실행하고 `SCRIPT ERROR:`, `Parse Error:`, `USER ERROR:` 출력을 검사한다.
  3. **정적 데이터 및 SQLite DDL 검증**: `validate_data.gd` 및 `/usr/bin/sqlite3 :memory: < data/schemas/world_state_schema.sql`을 실행하여 JSON 데이터 참조 무결성과 SQL 스키마 유효성을 검증한다.

```bash
#!/usr/bin/env bash
# File: scripts/harness/check_syntax.sh
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

echo "=== [Stage 1.1] Refreshing Godot 4 Global Class Cache ==="
timeout 30s godot --headless --path . --import --quit

echo "=== [Stage 1.2] Static GDScript Syntax & Strict Type Checking ==="
FAIL=0
while IFS= read -r -d '' gd_file; do
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
done < <(find ./src ./tests ./tools -name "*.gd" -print0)

echo "=== [Stage 1.3] Validating JSON Data & SQLite Schema ==="
timeout 20s godot --headless --path . -s res://tools/harness/validate_data.gd -- --strict || FAIL=1
/usr/bin/sqlite3 :memory: < data/schemas/world_state_schema.sql || FAIL=1

if [[ "${FAIL}" -ne 0 ]]; then
    echo "STAGE 1 FAILED: Static syntax, type, or schema errors detected."
    exit 1
fi
echo "STAGE 1 PASSED: All GDScript files, JSON data, and SQLite schemas valid."
```

### 4.2 Stage 2: 헤드리스 유닛 및 통합 테스트 러너 (`FH-03`)

- **구성 파일**: `scripts/harness/run_tests.sh`, `tools/harness/test_case.gd`, `tools/harness/test_runner.gd`
- **외부 애드온(GUT/GdUnit4) 대비 자체 러너 채택 이유**:
  - 외부 플러그인 다운로드나 `.godot` 플러그인 활성화 메타데이터 없이 100% 자체 완결적으로 동작한다.
  - 실패 시 확실한 `quit(1)` 종료 코드 전파와 JSON 리포트(`reports/test_report.json`) 생성을 보장한다.
- **무의미한 테스트 거부 규칙 (Zero-Assertion Rejection Rule)**:
  - 모든 테스트 클래스는 `class_name HarnessTestCase extends RefCounted`(`tools/harness/test_case.gd`)를 상속한다.
  - 각 `test_*()` 메서드 실행 시 `assertions_run: int` 카운터를 추적하며, 만약 `assertions_run == 0`인 상태로 테스트 메서드가 종료되면 즉시 **`"Vacuous test forbidden: 0 assertions executed"`** 실패로 처리하여 빈 껍데기 테스트 통과를 원천 차단한다.

```gdscript
# File: tools/harness/test_case.gd
class_name HarnessTestCase
extends RefCounted

var assertions_run: int = 0
var failures: Array[Dictionary] = []

func assert_eq(actual: Variant, expected: Variant, context: String = "") -> void:
    assertions_run += 1
    if actual != expected:
        failures.append({
            "type": "assert_eq",
            "actual": str(actual),
            "expected": str(expected),
            "context": context
        })

func assert_true(condition: bool, context: String = "") -> void:
    assertions_run += 1
    if not condition:
        failures.append({
            "type": "assert_true",
            "actual": "false",
            "expected": "true",
            "context": context
        })

func assert_in_range(val: int, min_val: int, max_val: int, context: String = "") -> void:
    assertions_run += 1
    if val < min_val or val > max_val:
        failures.append({
            "type": "assert_in_range",
            "actual": str(val),
            "expected": "[%d, %d]" % [min_val, max_val],
            "context": context
        })
```

```bash
#!/usr/bin/env bash
# File: scripts/harness/run_tests.sh
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"

mkdir -p reports
timeout 60s godot --headless --path . -s res://tools/harness/test_runner.gd -- \
    --dir=res://tests \
    --out=reports/test_report.json
```

### 4.3 Stage 3: 결정론적 시뮬레이션 및 오프라인 동치성 하네스 (`FH-05`)

- **구성 파일**: `tools/harness/sim_harness.gd`, `scripts/harness/run_sim.sh`
- **실행 명령어**:
  ```bash
  timeout 60s godot --headless --path . -s res://tools/harness/sim_harness.gd -- \
      --seed=18401 \
      --scenario=res://data/scenarios/yellow_turban_fief_start.json \
      --ticks=10000 \
      --checkpoint-interval=1000 \
      --verify-determinism \
      --verify-offline-equivalence \
      --out=reports/sim_snapshot_18401.json
  ```
- **Stage 3 자동 검증 항목**:
  1. **리플레이 결정론 검증 (`--verify-determinism`)**: 동일한 시드(`seed=18401`)와 초기 시나리오로 두 개의 독립된 시뮬레이션 유니버스를 $N$ 틱 동안 실행하고, 매 체크포인트마다 정규 직렬화된 `state_crc32` 및 `SHA-256` 해시가 100% 일치(`hash_run_1 == hash_run_2`)하는지 검증한다.
  2. **동적 마이크로 LOD (`LOD 0` ↔ `LOD 1`) 및 오프라인 동치성 검증 (`--verify-offline-equivalence`)**:
     - `LOD 0` (매 1초 마이크로 틱마다 타일/작업 단계별 시뮬레이션)으로 3,600틱을 실행한 결과와, `LOD 1` (매 6초 매크로 틱마다 1–4 업무 우선순위 가중치 $\alpha_{p,j}$ 및 이동 효율 $\eta_{\text{walk}}(j)$를 적용한 비율 적분 시뮬레이션)으로 동일 시간을 실행한 결과의 자원 산출량 편차가 허용 오차 이내이며 자원 음수 언더플로나 장수 사망 루프가 발생하지 않음을 검증한다.
  3. **도메인 불변식 (Domain Invariants) 상시 감시**:
     - `INV-PAWN-BOUNDS`: 모든 장수/가신의 5대 욕구(`FOOD`, `REST`, `MORALE`, `LOYALTY`, `AMBITION`)가 `[0, 10000]` 범위 내에 있고 기분(`Mood`)이 `[0, 100]` 범위 내에 존재함.
     - `INV-RESOURCE-NONNEG`: 장원 및 도시의 8대 자원 재고가 모두 `0` 이상의 정수(`int64 >= 0`)임.
     - `INV-JOB-PROGRESS`: 10,000틱 실행 동안 자율 업무 우선순위 매트릭스에 의해 완료된 작업 수(`jobs_completed`)가 양수이며 실제 자원 총량이 변화함(No-op 스텁 감지).
     - `INV-WORLD-CONSERVATION`: 출진 부대나 상단이 매크로 그래프 간선($E$)으로 이동할 때 출발 장원/도시에서 병력과 군량, 화물이 원자적(Atomically)으로 차감됨.

### 4.4 Stage 4: 헤드리스 공유 월드 멀티플레이어 스모크 하네스 및 포렌식 감사 (`FH-06`)

- **구성 파일**: `tools/harness/net_harness.gd`, `scripts/harness/run_net_smoke.py`, `tools/harness/audit_verifier.py`
- **실행 모드**:
  1. **인프로세스 루프백 모드 (`LoopbackMemoryTransport`)**: 단일 헤드리스 프로세스 내에서 1개의 `AuthoritativeServer`와 4~16개의 자율 봇 클라이언트를 초당 1,000틱 이상의 속도로 동기 실행하여 멀티플레이어 프로토콜을 고속 검증한다.
  2. **멀티프로세스 실제 소켓 모드 (`run_net_smoke.py`)**: `127.0.0.1` 에페메랄 포트 위에서 1개의 권위 서버 프로세스와 3개 이상의 봇 클라이언트 프로세스(군주 `lord_A`, 태수/동맹 `lord_B`, 경쟁자/약탈자 `lord_C`)를 각각 격리된 `--user-dir`로 구동한다.
- **검증 시나리오 및 SQLite 포렌식 감사 (`audit_verifier.py`)**:
  - **협동/경제 상호작용**: `lord_A`가 지역 거래소에 군량 매도 주문을 등록하거나 보급 상단을 파견하면 `lord_B`의 도시/장원 상태와 지역 시세가 실제로 변동하는지 확인.
  - **경쟁/군사 상호작용**: `lord_A`와 `lord_B`가 연합 공성전(`CMD_CREATE_COALITION_RALLY`)을 발동하여 거점을 점령하고 전공(`war_merit`)을 분배받는지 확인.
  - **적대적 안티치트 거부 증명**: `lord_C`가 권한 없는 타 플레이어 부대 조작, 보유량 초과 자원 사용, 혹은 비인가 명령을 전송했을 때 6단계 `CommandValidator`가 이를 거부하고 `saves/world_state.db`의 `command_audit_log` 테이블에 `status = 'REJECTED'` 레코드를 남기는지 `audit_verifier.py`로 검증.

---

## 5. 멀티 에이전트 역할 분리, 배타적 쓰기 권한 및 포렌식 감사 체크리스트

### 5.1 에이전트 역할별 배타적 쓰기 권한 매트릭스 (Disjoint Write-Ownership Matrix)

| 에이전트 역할 (Role) | 허용된 쓰기 경로 (Permitted Write Scope) | 엄격한 금지 사항 (Explicit Prohibitions) |
|---|---|---|
| **Orchestrator / Architect** | `PROJECT.md`, `project.godot`, `.agents/teamwork/orchestrator_*/**` | 프로덕션 구현 코드나 테스트 결과를 임의로 조작 금지 |
| **Worker (Core & Harness `M0`/`M1`)** | `docs/**`, `scripts/**`, `tools/harness/**`, `src/core/**` (`src/core/sealed_token_codec.gd` 포함), `data/schemas/**`, `data/persona_seal_rules.json` | `tests/**` 내부의 검증 어설션 약화 금지 |
| **Worker (Micro Sim `M2`)** | `src/micro/**`, `data/items_buildings.json`, `data/officers_catalog.json`, `data/interview_questions.json` | `src/core/**`, `tests/**`, `tools/harness/**` 수정 금지 |
| **Worker (Macro Sim `M3`)** | `src/macro/**`, `data/macro_map_3k.json`, `data/storytellers.json` | `src/core/**`, `src/micro/**`, `tests/**` 수정 금지 |
| **Worker (Faction & Politics `M4`)** | `src/faction/**`, `src/macro/siege_battle_resolver.gd` | `src/core/**`, `tests/**` 수정 금지 |
| **Worker (Net & Persistence `M5`)** | `src/net/**`, `src/persistence/**` | `src/core/**`, `data/schemas/world_state_schema.sql` 제약 조건 및 `Stage 5` 봉인 토큰/강압·예산 게이트 완화 금지 |
| **Worker (Client UI `M6`)** | `src/ui/**`, `scenes/*.tscn` (< 30 lines) | UI 코드 내에서 시뮬레이션 상태를 직접 변경(Mutation)하거나 평문 JSON 편집기 노출 금지 |
| **Test Writer** | `tests/**`, `data/scenarios/**` | 테스트 통과를 위해 `src/**` 프로덕션 로직 수정 절대 금지 |
| **Reviewer / Challenger / Forensic Auditor** | 자신의 `.agents/teamwork/<agent_folder>/` 상태 폴더만 쓰기 가능 (레포지토리 전체 읽기 전용) | 프로덕션 코드 대리 수정 금지; 오직 독립 검증 및 결함 보고만 수행 |

### 5.2 포렌식 감사관 반칙 방지 체크리스트 (Forensic Auditor Anti-Cheating Checklist)

포렌식 감사관(`Forensic Auditor`)과 챌린저(`Challenger`)는 매 마일스톤 종료 시 다음 7가지 자동 감사를 실행하여 어떠한 형태의 하드코딩이나 속임수도 허용하지 않는다:

1. **엄격 타입 검사 우회 여부 확인**:
   `grep -E "untyped_declaration=2|unsafe_property_access=2|unsafe_method_access=2|unsafe_cast=2|unsafe_call_argument=2" project.godot` 결과 5개 항목이 모두 `=2`로 유지되는지 확인.
2. **비시드 난수(Unseeded RNG) 사용 전수 스캔**:
   `grep -rnE "\brand(f|i|f_range|i_range)\s*\(|\brandomize\s*\(" src/micro/ src/macro/ src/faction/` 결과가 **0건**인지 확인.
3. **벽시계(Wall-Clock) 누수 전수 스캔**:
   `grep -rnE "get_ticks_msec|get_ticks_usec|get_unix_time" src/micro/ src/macro/ src/faction/` 결과가 **0건**인지 확인.
4. **바이너리 리소스 및 거대 `.tscn` 금지 감사**:
   `find . -name "*.tres"` 결과가 **0건**이고, `scenes/*.tscn` 파일의 줄 수가 각각 **30줄 미만**인지 확인.
5. **무의미한 테스트(0-Assertion) 및 스킵 감사**:
   `reports/test_report.json`에서 `total_tests > 0`, `failed_tests == 0`, `min_assertions_per_test >= 1`인지 검증.
6. **적대적 시드 교란 검증 (Adversarial Seed Perturbation Check)**:
   Worker가 알지 못하는 3개의 무작위 시드(예: `--seed=99103`, `--seed=44217`, `--seed=77812`)로 `sim_harness.gd`를 실행하여:
   - 서로 다른 시드 간에는 최종 `state_crc32` / `final_state_hash`가 **반드시 달라야 함**(고정된 스냅샷을 반환하는 하드코딩 적발).
   - 동일한 시드를 2회 반복 실행했을 때는 최종 해시가 **100% 일치해야 함**(완전 결정론 증명).
7. **Track B 봉인 토큰 및 안티치트 불변식 감사 (Character Creation Security Audit)**:
   - `src/net/`, `src/micro/`, `src/ui/`에 평문 JSON(`AI_PERSONA_EXPORT_V1`, raw `persona_weights`)을 허용하거나 `SealedTokenCodec` + `Stage 5` Point-Buy 정규화를 우회하는 경로가 **0건**인지 검증.
   - `OptionalGeminiAPIProvider` (`gemini-4-hydrogen`)가 `ClipboardSealedTokenProvider`와 100% 동일한 `AI_PERSONA_TOKEN_V2` (`TK3K2`) 챌린지·Fletcher-31·`R0..R3`·`H1..H4` 게이트를 통과하는지 확인.
   - `tests/`에 1문자 변조(`ERR_TOKEN_TAMPERED`), 평문 JSON 거부(`ERR_PLAINTEXT_JSON_FORBIDDEN`), 만료/리플레이 챌린지(`ERR_CHALLENGE_EXPIRED`/`ERR_CHALLENGE_REPLAYED`), `R1/R2/R3` 강압 플래그, 극단 이분화/평탄 상한(`H1/H2`), 전-빛 기질 대체(`H3`), 서사 살균(`H4`) 적대적 테스트가 포함되어 있는지 검증.

### 5.3 모델 티어 라우팅 및 비용 최적화 정책 (Model Tier Routing & Cost-Optimization Policy)

할당량(Quota) 고갈을 방지하고 비용 대비 작업 효율을 극대화하기 위해, 멀티 에이전트(`Teamwork` 및 하위 에이전트 호출) 운영 시 **오케스트레이터 역할만 현재 최상위 모델(`inherit`)이 직접 수행**하고, 모든 하위 에이전트는 **작업의 역할·난이도·비용**에 따라 **`Gemini 4 Hydrogen (gemini-4-hydrogen)` / `flash` / `flash_lite`** 등 저비용·고효율 모델로 배정하는 것을 영구 원칙으로 강제한다.

| 에이전트 역할 (Role) | 지정 모델 티어 (`Model` / API ID) | 배정 기준 (역할·난이도·비용) |
|---|---|---|
| **Orchestrator / Architect** | **`inherit` (현재 상위 모델 단독 수행)** | 전체 아키텍처 설계, 마일스톤 분해, 인터페이스 계약 관리, 하위 에이전트 지휘 및 최종 게이트 통합 판정 |
| **Worker (핵심 로직/네트워크/UI 구현)** | **`Gemini 4 Hydrogen` (`gemini-4-hydrogen`, `thinking: medium/high`) / `flash`** | 결정론 시뮬레이션(`src/micro`, `src/macro`, `src/faction`), 네트워크/영속성(`src/net`, `src/persistence`), UI(`src/ui`) 구현 등 중·상 난이도 에이전트 코딩 |
| **Test Writer / Reviewer / Challenger** | **`Gemini 4 Hydrogen` (`gemini-4-hydrogen`, `thinking: high`) / `flash`** | 독립 테스트 작성(`tests/**`), 코드/계약 리뷰, 경계값 및 적대적 시드 교란 검증 |
| **Explorer (심층 리서치/구조 분석)** | **`Gemini 4 Hydrogen` (`gemini-4-hydrogen`, `thinking: low/medium`) / `flash`** | 멀티 파일 교차 분석, 외부 스펙·프로토콜 조사, 병렬 코드베이스 탐색 |
| **Worker (단순 데이터/보일러플레이트)** | **`flash_lite`** (또는 `gemini-4-hydrogen` `thinking: low`) | 정형화된 JSON 데이터 추가, 단순 스크립트/문서 포맷팅, 반복 수정 |
| **Explorer (단순 조회) / Forensic Auditor / Sentinel** | **`flash_lite`** | 단일 파일/디렉터리 조회, 체크리스트·정규식 기반 포렌식 스캔, 진행 상태 모니터링 및 경량 중계 |

- **강제 지침 및 플랫폼 매핑**:
  1. 오케스트레이터 외의 하위 에이전트에 `pro` 또는 `inherit` 모델을 기본 배정하지 않는다.
  2. `Teamwork` 또는 하위 에이전트를 기동할 때 위 모델 티어 라우팅 정책(`Orchestrator = inherit`, `Subagents = Gemini 4 Hydrogen / flash / flash_lite`)을 항상 프롬프트 지시사항에 명시한다.
  3. Antigravity `invoke_subagent` 도구의 `Model` 파라미터 스키마가 `inherit | flash_lite | flash | pro` 열거형으로 매핑되는 구간에서는 역할 난이도에 따라 `flash`(Hydrogen/고속 코딩 티어 매핑) 또는 `flash_lite`(초경량 티어)를 명시적으로 선택하며, 직접 모델 ID 지정이 가능한 워크플로우 및 선택적 외부 AI 연동(예: 캐릭터 생성 `OptionalGeminiAPIProvider`)에서는 **`gemini-4-hydrogen`**을 기본 고속 실행 모델로 사용한다. 단, `OptionalGeminiAPIProvider` (`gemini-4-hydrogen`)는 **제로 트러스트 신뢰 불가 외부 생성기(Zero-Trust Untrusted External Producer)** 로 엄격히 분류되며, 생성 결과는 반드시 `ClipboardSealedTokenProvider`와 동일한 `AI_PERSONA_TOKEN_V2` (`TK3K2`) · Stage 5 강압/이상치 게이트(`R0..R3`, `H1..H4`) · Point-Buy 정규화(`sum=320`, `[35,85]`, `5 빛+1/5 그림자-1`)를 통과해야 한다.
  4. 하위 에이전트가 `Gemini 4 Hydrogen` / `flash` 티어로 2회 이상 해결하지 못하는 고난도 설계/통합 병목이 발생할 경우, 하위 모델을 상향하는 대신 오케스트레이터가 직접 원인을 진단·분해하여 재지시한다.

---

## 6. 하네스 기능 인벤토리 매핑 (`FH-00` ~ `FH-06`)

| Feature ID | 기능 명칭 | 목표 마일스톤 | 핵심 산출물 경로 | 검증 명령어 |
|---|---|---|---|---|
| `FH-00` | **AI Agent Harness & GDD/Architecture Blueprint Suite** | **M0** | `docs/01_*.md`..`04_*.md`, `data/schemas/world_state_schema.sql`, `scripts/harness/verify_blueprint.py` | `python3 scripts/harness/verify_blueprint.py` |
| `FH-01` | **Godot 4 Toolchain Bootstrap & Strict Project Config** | **M1** | `scripts/setup_godot.sh`, `project.godot` | `bash scripts/setup_godot.sh && godot --headless --version` |
| `FH-02` | **Stage 1 Static Syntax, Type & JSON Schema Gate** | **M1** | `scripts/harness/check_syntax.sh`, `tools/harness/validate_data.gd` | `bash scripts/harness/check_syntax.sh` |
| `FH-03` | **Stage 2 Headless Unit & Integration Test Runner** | **M1** | `tools/harness/test_case.gd`, `tools/harness/test_runner.gd`, `scripts/harness/run_tests.sh` | `bash scripts/harness/run_tests.sh` |
| `FH-04` | **Deterministic Core Contracts (`SimClock`, `DeterministicRNG`, `StateHasher`, `SimEventBus`)** | **M1** | `src/core/sim_clock.gd`, `src/core/deterministic_rng.gd`, `src/core/state_hasher.gd`, `src/core/sim_event_bus.gd`, `src/core/dto_schemas.gd` | `bash scripts/harness/run_tests.sh` |
| `FH-05` | **Stage 3 Deterministic Simulation & Offline Equivalence Harness (`sim_harness`)** | **M2** | `tools/harness/sim_harness.gd`, `scripts/harness/run_sim.sh` | `bash scripts/harness/run_sim.sh` |
| `FH-06` | **Stage 4 Headless Shared-World Multiplayer Smoke Harness (`net_harness`)** | **M6** | `tools/harness/net_harness.gd`, `scripts/harness/run_net_smoke.py`, `tools/harness/audit_verifier.py` | `python3 scripts/harness/run_net_smoke.py` |
