# Three Kingdoms × RimWorld Shared-World Idle Game (Godot 4)

> **🌐 라이브 브라우저 시연 (GitHub Pages · 설치 불필요)**:  
> **https://jongin-lee72.github.io/three-kingdoms-rimworld-idle/**  
> 별도 설치 없이 브라우저에서 즉시 `player_01` + AI 경쟁/동맹 군주 2인(`lord_wei`, `ally_shu`)이 실시간으로 상호작용하는 **삼국지 × 림월드 로컬 시연**을 플레이할 수 있습니다. (매 `main` 푸시마다 `.github/workflows/deploy-pages.yml`이 Godot 4.4.1 HTML5/WASM 빌드를 자동 배포합니다.)

삼국지 난세에 떨어진 내가 장수(`재야/관원/태수/도독`) 혹은 군주(`군주`)로서 개인 장원(`32×32`)과 가신단을 **림월드식 간접 자동화(7대 업무 우선순위 `1~4`, 십이지시 일과표, 상시 교전 수칙)**로 경영하며, 모든 플레이어가 **하나의 공유 월드(권위 서버)**에서 상호작용하는 **Godot 4 방치형 전략 게임** 및 **AI 에이전트 개발·검증 하네스**입니다.

---

## 핵심 아키텍처

- **3계층 코드 우선(Code-First) Godot 4 구조**:
  - **Layer 1 (`src/core/`, `src/micro/`, `src/macro/`, `src/faction/`, `src/net/`, `src/persistence/`)**: 순수 `RefCounted` 기반 헤드리스 결정론적 정수(`int64` permille/bp) 시뮬레이션 + `SplitMix64` 무상태 난수(`DeterministicRNG`) + `CRC32`/`SHA-256` 상태 해싱.
  - **Layer 2 (`data/`, `assets/`)**: 순수 UTF-8 JSON 데이터 8종(CC0 에셋 매니페스트 `data/assets_manifest.json` 포함) 및 10테이블 SQLite 스키마(`data/schemas/world_state_schema.sql`), `itch.io` / `Kenney.nl` / `OpenGameArt.org`에서 리서치·확보한 **100% CC0 1.0 그래픽·사운드 에셋 33종**(`assets/ASSETS_ATTRIBUTION.md`), 웹 한글 렌더링용 SIL OFL 1.1 `NotoSansKR-Subset.otf`, 바이너리 `.tres` 0건.
  - **Layer 3 (`src/ui/`, `scenes/`)**: 30줄 미만의 최소 부트스트랩 씬(`main_client.tscn`, `headless_server.tscn`) + 프로그래밍 방식 4대 통합 UI 뷰(2D `32×32` Kenney 타일맵 장원 캔버스, OpenGameArt CC0 양피지 천하 전략도 캔버스, Kenney 9-Slice 테마, `AssetRegistry` & `AudioManager` 동양풍 BGM/16종 SFX, `LiveSessionDriver` 실시간 로컬 시연/원격 WebSocket 세션 드라이버).
- **2계층 결합 시뮬레이션 (`Micro LOD 0/1` ↔ `Macro Graph G=(V,E)`)**:
  - 개인 장원(`32×32`, 8구역, 10시설, 5대 능력치·열정 불꽃, 5대 욕구, 10대 기질, 심리 붕괴/심기일전/영웅적 각성, 비상 지하창고 및 오프라인 불사 보호).
  - 삼국지 9주 15거점 22간선 전략도, 랜체스터 $N^{0.85}$ 자동 전투·5합 일기토·계략/기후, 지역 지정가 거래소 + AMM, 천명 감독관 스토리텔러(`사마천/동탁/문경지치`).
  - 장수↔군주 이중 정치(구품 관직/봉록, 정청 임무 자동 수주, 태수/도독 위임, 이간/회유/내응/태수 독립/재야 거병, 다중 군단 연합 공성전, 도원결의 의형제, 사계절 외교 조약, 시즌 천하통일 결산 및 가문 계승).
- **하이브리드 캐릭터 생성 & `AI_PERSONA_TOKEN_V2` (`TK3K2`) 보안**:
  - 선택지 서사 인터뷰(`천명 문답`) + 외부 AI 페르소나 봉인 토큰(`TK3K2`: 세션별 `HMAC-SHA256` Fisher-Yates 치환표 + Base-31 + Fletcher-31 체크섬, 평문 JSON 차단, `R0..R3` 조작 탐지, 고정 예산 `320` 정규화).
- **권위 서버·6단계 안티치트 & 하이브리드 WAL + SQLite 영속성**:
  - `Loopback` / `WebSocket` / `ENet` 플러그형 트랜스포트, 4채널 관심 영역 델타 압축, 6단계 명령 검증 및 토큰 버킷 속도 제한, JSONL WAL + 원자적 스냅샷 + 10테이블 `/usr/bin/sqlite3` 동기화(`PRAGMA foreign_keys = ON;`).

---

## 즉시 플레이 (브라우저 데모 / `F5` 로컬 시연) 및 전용 멀티플레이 서버

### 0. 브라우저 라이브 데모 (`GitHub Pages` HTML5/WASM)
- **즉시 접속 URL**: https://jongin-lee72.github.io/three-kingdoms-rimworld-idle/
- 단일 스레드 WebGL 2.0 (`gl_compatibility`, `variant/thread_support=false`) + `coi-serviceworker.js` + 번들 한글 CJK 폰트(`NotoSansKR-Subset.otf`)로 구성되어 PC/모바일 브라우저에서 별도 설치 없이 바로 로컬 시연(`player_01` + `lord_wei` + `ally_shu`)을 체험할 수 있습니다.
- **로컬에서 직접 Web(HTML5/WASM) 빌드 내보내기**:
  ```bash
  export PATH="${HOME}/.local/bin:${PATH}"
  # (Godot 4.4.1-stable 웹 내보내기 템플릿이 ~/.local/share/godot/export_templates/4.4.1.stable/ 에 설치되어 있어야 합니다)
  mkdir -p build/web && touch build/.gdignore
  godot --headless --path . --import --quit
  godot --headless --path . --export-release "Web" build/web/index.html
  cp web/coi-serviceworker.js build/web/coi-serviceworker.js
  touch build/web/.nojekyll
  ```
- **CI/CD 자동 배포**: `main` 브랜치에 푸시할 때마다 `.github/workflows/deploy-pages.yml`이 Godot 4.4.1 Web 릴리즈 빌드를 생성하여 GitHub Pages에 자동 배포합니다.

### 1. Godot `F5` 로컬 즉시 플레이 (`scenes/main_client.tscn`)
1. 저장소를 클론한 뒤 Godot 4.4.1 에디터에서 `project.godot`을 열고 **`F5`**(또는 `godot --path . scenes/main_client.tscn`)를 실행합니다.
2. **로컬 시연 모드(`LiveSessionDriver`)**가 자동으로 부팅되어 플레이어(`player_01` · 허창 `한실 신흥군`)와 자율 AI 경쟁/동맹 군주 2명(`lord_wei` · 하비 `위(魏) 조조군`, `ally_shu` · 성도 `촉(蜀) 유비군`)이 실제 `AuthoritativeServer` + `LoopbackMemoryTransport` 위에서 즉시 동작합니다.
3. 상단 세션 바에서 **일시정지 / 재개**, 배속 전환(**`1x` / `2x` / `5x`**), 명령 영수증(`MSG_CMD_RECEIPT`) 피드백을 바로 제어할 수 있으며, 매 매크로 틱마다 AI 군주들의 지역 거래소 호가 체결 및 상단/군단 출진이 천하 전략도(`3번 탭`)와 정청/거래소(`4번 탭`)에 실시간 반영됩니다.

### 2. 전용 상시 헤드리스 서버 호스팅 (`scenes/headless_server.tscn`)
```bash
export PATH="${HOME}/.local/bin:${PATH}"

# 기본 설정(포트 9090, 1초 틱, WAL + 원자적 스냅샷 + SQLite 자동 체크포인트)으로 서버 기동
godot --headless --path . scenes/headless_server.tscn -- \
  --port=9090 \
  --bind=127.0.0.1 \
  --db=saves/world_state.db \
  --wal=saves/wal_commands.jsonl \
  --snapshot=saves/world_snapshot.json \
  --seed=18401 \
  --tick-sec=1.0 \
  --snapshot-interval=24
```
- 종료 시(`SIGTERM` / 창 닫기) 최종 원자적 스냅샷과 10테이블 SQLite 체크포인트를 자동 플러시하며, 재기동 시 기존 스냅샷 + WAL을 자동 복구합니다.

### 3. 원격 WebSocket 멀티플레이 접속
1. 위 헤드리스 서버를 먼저 실행한 뒤, `F5`로 실행한 클라이언트 상단 우측의 **WebSocket 접속 바**에 `ws://127.0.0.1:9090` (또는 원격 호스트 주소)을 입력하고 **`서버 접속`** 버튼을 누릅니다.
2. 연결이 열리면 클라이언트가 초기 채널 구독 핸드셰이크를 전송하여 서버에 피어를 자동 등록하고, 실시간 `MSG_TICK_DELTA` / `MSG_CMD_RECEIPT` / 재접속 `MSG_OFFLINE_CHRONICLE_DIGEST`(조보) / `MSG_PERSONA_CHALLENGE`를 송수신합니다.
3. **`로컬 시연`** 버튼을 누르면 언제든 임베디드 로컬 시연 모드로 전환할 수 있습니다.

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

# 4. Stage 2: 헤드리스 유닛 & 통합 테스트 스위트
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
