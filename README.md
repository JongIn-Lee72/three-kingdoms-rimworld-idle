# Three Kingdoms × RimWorld Shared-World Idle Game (Godot 4)

삼국지 난세에 떨어진 내가 장수(`재야/관원/태수/도독`) 혹은 군주(`군주`)로서 개인 장원(`32×32`)과 가신단을 **림월드식 간접 자동화(7대 업무 우선순위 `1~4`, 십이지시 일과표, 상시 교전 수칙)**로 경영하며, 모든 플레이어가 **하나의 공유 월드(권위 서버)**에서 상호작용하는 **Godot 4 방치형 전략 게임** 및 **AI 에이전트 개발·검증 하네스**입니다.

---

## 핵심 아키텍처

- **3계층 코드 우선(Code-First) Godot 4 구조**:
  - **Layer 1 (`src/core/`, `src/micro/`, `src/macro/`, `src/faction/`, `src/net/`, `src/persistence/`)**: 순수 `RefCounted` 기반 헤드리스 결정론적 정수(`int64` permille/bp) 시뮬레이션 + `SplitMix64` 무상태 난수(`DeterministicRNG`) + `CRC32`/`SHA-256` 상태 해싱.
  - **Layer 2 (`data/`, `assets/`)**: 순수 UTF-8 JSON 데이터 8종(CC0 에셋 매니페스트 `data/assets_manifest.json` 포함) 및 10테이블 SQLite 스키마(`data/schemas/world_state_schema.sql`), `itch.io` / `Kenney.nl` / `OpenGameArt.org`에서 리서치·확보한 **100% CC0 1.0 그래픽·사운드 에셋 33종**(`assets/ASSETS_ATTRIBUTION.md`), 바이너리 `.tres` 0건.
  - **Layer 3 (`src/ui/`, `scenes/`)**: 30줄 미만의 최소 부트스트랩 씬(`main_client.tscn`, `headless_server.tscn`) + 프로그래밍 방식 4대 통합 UI 뷰(2D `32×32` Kenney 타일맵 장원 캔버스, OpenGameArt CC0 양피지 천하 전략도 캔버스, Kenney 9-Slice 테마, `AssetRegistry` & `AudioManager` 동양풍 BGM/16종 SFX).
- **2계층 결합 시뮬레이션 (`Micro LOD 0/1` ↔ `Macro Graph G=(V,E)`)**:
  - 개인 장원(`32×32`, 8구역, 10시설, 5대 능력치·열정 불꽃, 5대 욕구, 10대 기질, 심리 붕괴/심기일전/영웅적 각성, 비상 지하창고 및 오프라인 불사 보호).
  - 삼국지 9주 15거점 22간선 전략도, 랜체스터 $N^{0.85}$ 자동 전투·5합 일기토·계략/기후, 지역 지정가 거래소 + AMM, 천명 감독관 스토리텔러(`사마천/동탁/문경지치`).
  - 장수↔군주 이중 정치(구품 관직/봉록, 정청 임무 자동 수주, 태수/도독 위임, 이간/회유/내응/태수 독립/재야 거병, 다중 군단 연합 공성전, 도원결의 의형제, 사계절 외교 조약, 시즌 천하통일 결산 및 가문 계승).
- **하이브리드 캐릭터 생성 & `AI_PERSONA_TOKEN_V2` (`TK3K2`) 보안**:
  - 선택지 서사 인터뷰(`천명 문답`) + 외부 AI 페르소나 봉인 토큰(`TK3K2`: 세션별 `HMAC-SHA256` Fisher-Yates 치환표 + Base-31 + Fletcher-31 체크섬, 평문 JSON 차단, `R0..R3` 조작 탐지, 고정 예산 `320` 정규화).
- **권위 서버·6단계 안티치트 & 하이브리드 WAL + SQLite 영속성**:
  - `Loopback` / `WebSocket` / `ENet` 플러그형 트랜스포트, 4채널 관심 영역 델타 압축, 6단계 명령 검증 및 토큰 버킷 속도 제한, JSONL WAL + 원자적 스냅샷 + 10테이블 `/usr/bin/sqlite3` 동기화(`PRAGMA foreign_keys = ON;`).

---

## 빠른 시작 및 4단계 헤드리스 검증

```bash
# 1. Godot 4.4.1-stable 사용자 공간 설치 (SHA-512 검증)
bash scripts/setup_godot.sh
export PATH="${HOME}/.local/bin:${PATH}"

# 2. M0 청사진, 52개 기능 매핑, SQLite DDL 및 TK3K2 보안 자가 검증
python3 scripts/harness/verify_blueprint.py

# 3. Stage 1: 정적 문법, 엄격 타입(=2), JSON 데이터(--strict --require-all, CC0 매니페스트 포함) & SQLite 검증
bash scripts/harness/check_syntax.sh
godot --headless --path . -s res://tools/harness/validate_data.gd -- --strict --require-all

# 4. Stage 2: 헤드리스 유닛 & 통합 테스트 스위트 (113 tests / 5,054 assertions)
bash scripts/harness/run_tests.sh

# 5. Stage 3: 10,000틱 결정론 리플레이 & LOD 0/1 오프라인 동치성 검증
bash scripts/harness/run_sim.sh --seed=18401 --scenario=res://data/scenarios/yellow_turban_fief_start.json --ticks=10000 --checkpoint-interval=1000 --verify-determinism --verify-offline-equivalence

# 6. Stage 4: 멀티클라이언트(루프백 + 실제 localhost WebSocket) 공유 월드 스모크 & 10테이블 SQLite 감사
python3 scripts/harness/run_net_smoke.py
python3 tools/harness/audit_verifier.py --db saves/world_state.db
```

---

## 주요 문서

- [PROJECT.md](PROJECT.md) — 전체 아키텍처, 52개 기능 인벤토리, `M0`~`M6` 로드맵 및 인터페이스 계약
- [docs/01_AI_AGENT_HARNESS_SPEC.md](docs/01_AI_AGENT_HARNESS_SPEC.md) — AI 에이전트 개발·검증 하네스, 포렌식 반칙 방지 규칙 및 모델 티어 라우팅 정책
- [docs/02_GAME_DESIGN_DOCUMENT.md](docs/02_GAME_DESIGN_DOCUMENT.md) — 상세 게임 기획서(GDD) 및 `TK3K2` 하이브리드 캐릭터 생성 명세
- [docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md](docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md) — 공유 월드 멀티플레이어 아키텍처, 프로토콜, 보안 및 영속성 명세
- [docs/04_USER_CONFIRMATION_CHECKLIST.md](docs/04_USER_CONFIRMATION_CHECKLIST.md) — 설계 결정 체크리스트 (`D-01`~`D-06`)
