# Project: 삼국지 × 림월드 공유 월드 방치형 게임 (Three Kingdoms × RimWorld Shared-World Idle Game in Godot 4)

## Architecture

### 1. System Overview & Core Paradigm
This project implements a **Shared-World Multiplayer Idle Game in Godot 4** where every player lives in the Three Kingdoms era as an **Officer (`장수/재야/태수/도독`)** or **Sovereign Lord (`군주`)**, referencing **RimWorld's** emergent pawn autonomy, indirect priority control, and AI Storyteller while coexisting on a **single persistent authoritative server world**.

To support both RimWorld-depth colony life simulation and hundreds of concurrent players on a shared Three Kingdoms strategic map—and to allow 100% headless autonomous AI agent development and verification—the architecture enforces two foundational separations:

1. **3-Layer Code-First / Text-Safe Godot 4 Architecture (For Multi-Agent Development)**:
   - **Layer 1 — Pure Headless Simulation & Protocol Kernel (`src/core/`, `src/micro/`, `src/macro/`, `src/faction/`, `src/net/`, `src/persistence/`)**: All domain models and tick processors extend `RefCounted` (never `Node`), use deterministic integer-scaled (`int64` permille/basis-point, `1000 = 1.000`) arithmetic and stateless SplitMix64 seeded RNG (`DeterministicRNG`), and implement canonical `to_dict()` / `from_dict()` serialization plus `state_crc32` hashing.
   - **Layer 2 — Declarative Static Data & Schemas (`data/`)**: All historical/procedural officers, traits, buildings, items, crafting recipes, macro map nodes/edges, storytellers, and SQLite persistence schemas live in pure UTF-8 `.json` and `.sql` files (zero binary `.tres` or fragile `uid://` cross-references).
   - **Layer 3 — Thin Programmatic Views & Minimal Scene Shells (`src/ui/`, `scenes/`)**: `.tscn` files are restricted to minimal (<30 lines) static bootstrapper shells (`scenes/main_client.tscn`, `scenes/headless_server.tscn`). All UI views (Manor 32×32 grid, Work Priority Matrix, Three Kingdoms Strategic Map, Court/Market HUD, Morning Gazette `조보`) are built programmatically in GDScript (`src/ui/`) and communicate with the simulation solely via read-only state snapshots and declarative intent commands.

2. **Two-Layer Coupled Simulation Engine (Micro RimWorld Manor ↔ Macro Shared Three Kingdoms Map)**:
   - **Micro Layer (Layer 1 — `장원/본영` / RimWorld Manor & Encampment Simulation)**: Each player owns an indestructible personal Manor (`32×32` logical tile & 7-zone grid) anchored at a host County/City node on the shared world map. Inside the Manor, the player's Main Character, 1–12 Sworn Retainers (`가신/문객`), and Household Troops (`사병/부곡`) autonomously eat, sleep, farm (`둔전`), forge gear, drill, research stratagems, host banquets, and repel raids according to the player's **7-Domain 1–4 Work Priority Matrix**, **12-ShiChen Daily Schedule (`십이지시 일과표`)**, and **Standing Tactical Doctrines (`상시 교전 수칙`)**.
     - *Dynamic Simulation LOD*: Active, inspected, or raided Manors simulate at **`LOD 0`** (every `Micro-Tick = 1.0s`, step-by-step tile/job execution). Unobserved peaceful Manors simulate at **`LOD 1`** (every `Macro-Tick = 6.0s`, deterministic rate-integrated equations derived from the exact same priority matrix and schedule) and instantly promote to `LOD 0` upon inspection or incoming raid.
   - **Macro Layer (Layer 2 — `천하 전략도` / Shared Three Kingdoms Strategic Graph $G=(V,E)$)**: A single server-wide directed multigraph of Commanderies, Cities, Counties, and Passes ($V$: 주/군/성/현/관문) linked by Highways, Mountain Paths, and Waterways ($E$: 가도/산길/수운). Marching armies, supply caravans, regional market order books (`BID`/`ASK` + AMM reserve), coalition sieges, espionage, faction diplomacy, and the **Mandate of Heaven AI Storyteller (`천명 감독관`: `사마천`, `동탁`, `문경지치`)** operate continuously on the shared server timeline.

### 2. Multi-Cadence Authoritative Tick Clock (`SimClock`)
- **`MICRO_TICK` (`1.0s` real-time in live server; `0ms` unthrottled in headless `sim_harness`)**: Drains validated client intent commands (`CommandEnvelope`), advances `LOD 0` Manor pawn jobs/needs/moods, and steps active tactical battles.
- **`MACRO_TICK` (`6 MICRO_TICKS = 6.0s` real-time)**: Steps `LOD 1` rate-integrated Manors, advances Macro Graph armies/caravans along edges $E$, resolves ambushes and multi-wave coalition sieges (including 5-bout 1v1 Officer Duels `일기토`), matches Regional Market Order Books, and computes authoritative `state_crc32`.
- **`DAILY_SETTLEMENT_TICK` (`24 MICRO_TICKS = 24.0s` real-time = 1 In-Game Day / 12 ShiChen)**: Collects County taxes, distributes Faction Stipends (`봉록`) by 9-Tier Court Rank (`구품 관직`), evaluates Loyalty/Ambition drift and Storyteller threat/opportunity rolls, and commits a persistence checkpoint (`wal_commands.jsonl` flush + atomic `world_snapshot.json` + `/usr/bin/sqlite3` `world_state.db` sync).

---

## Feature Inventory

Every feature identified during Step 0 Survey across all 3 Survey Explorers is cataloged below and assigned to a concrete milestone (`M0` through `M6`). Zero features are unassigned.

| # | Feature ID | Feature | Description | Milestone | Source |
|---|------------|---------|-------------|-----------|--------|
| 1 | `FH-00` | **AI Agent Harness & GDD/Architecture Blueprint Suite** | Concrete Korean GDD (`docs/02_GAME_DESIGN_DOCUMENT.md`), AI Agent Harness Spec (`docs/01_AI_AGENT_HARNESS_SPEC.md`), Shared-World Multiplayer Architecture Spec (`docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md`), User Confirmation Checklist (`docs/04_USER_CONFIRMATION_CHECKLIST.md`), SQLite Schema (`data/schemas/world_state_schema.sql`), and automated Blueprint/Schema Verifier (`scripts/harness/verify_blueprint.py`). | M0 | survey_1, survey_2, survey_3 |
| 2 | `FH-01` | **Godot 4 Toolchain Bootstrap & Strict Project Config** | User-space `scripts/setup_godot.sh` installing official Linux `x86_64` Godot 4 binary to `~/.local/bin/godot` with SHA-512 verification + `project.godot` with strict GDScript type warnings-as-errors (`=2`). | M1 | survey_1 |
| 3 | `FH-02` | **Stage 1 Static Syntax, Type & JSON Schema Gate** | `scripts/harness/check_syntax.sh` + `tools/harness/validate_data.gd` warming global class cache, checking all `.gd` scripts with `--check-only`, and validating `data/**/*.json`. | M1 | survey_1 |
| 4 | `FH-03` | **Stage 2 Headless Unit & Integration Test Runner** | Self-contained `tools/harness/test_case.gd` and `tools/harness/test_runner.gd` (`extends SceneTree`) enforcing non-zero exit on failure, zero-assertion test rejection, and JSON test reports. | M1 | survey_1 |
| 5 | `FH-04` | **Deterministic Core Contracts (`SimClock`, `DeterministicRNG`, `StateHasher`, `SimEventBus`)** | 3-cadence tick clock (`1s`/`6s`/`24s`), SplitMix64 `int64` seeded PRNG, canonical sorted-key `to_dict()`/`from_dict()`, CRC32/SHA-256 state hashing, and cross-layer event bus. | M1 | survey_1, survey_3 |
| 6 | `FH-05` | **Stage 3 Deterministic Simulation & Offline Equivalence Harness (`sim_harness`)** | `tools/harness/sim_harness.gd` + `scripts/harness/run_sim.sh` running $N$ headless ticks from a seed/scenario and asserting replay determinism, `LOD 0` vs `LOD 1` / offline equivalence, and domain invariants. | M2 | survey_1, survey_2, survey_3 |
| 7 | `FH-06` | **Stage 4 Headless Shared-World Multiplayer Smoke Harness (`net_harness`)** | `tools/harness/net_harness.gd`, `scripts/harness/run_net_smoke.py`, and `tools/harness/audit_verifier.py` launching 1 authoritative server + $N$ autonomous warlord bot clients and auditing `world_state.db`. | M6 | survey_1, survey_3 |
| 8 | `F-01` | **Hybrid Interview & AI Persona Character Creation + Origin Archetypes (`천명 문답·외부 AI 페르소나 임포트 및 출신 배경`)** | 3-mode character creation (`INTERVIEW_ONLY` 8-scene narrative interview, `FUSION_INTERVIEW` 40% sealed AI prior + 60% 5-scene tailored dilemma interview, `AI_DIRECT_WITH_CONFIRM`) with Zero-API-Key **`AI_PERSONA_TOKEN_V2` (`TK3K2`)** one-time challenge-bound Base-31 + Fletcher-31 sealed token import (**`ClipboardSealedTokenProvider`** paste-only UI banning raw JSON + Zero-Trust `OptionalGeminiAPIProvider` `gemini-4-hydrogen` adapter), hardened anti-manipulation/coercion prompt (`R0..R3`) & server anomaly gate (`H1..H4`), deterministic Point-Buy Normalization (`TOTAL_STAT_BUDGET=320`, `[35,85]`), 5 Light (`+1`) & 5 Shadow (`-1`) trait pairing (`net_cost ∈ [-1,+1]`), automatic initial Manor schedule/doctrine/complementary retainer seeding, and 5 Origin archetypes. | M2 | survey_2, user_upgrade |
| 9 | `F-02` | **5-Stat Allocation & Passion Flames (`오대 능력치 및 열정`)** | Three Kingdoms 5 core attributes (`LEA/통솔`, `MAR/무력`, `INT/지력`, `POL/정치`, `CHA/매력`) normalized from interview/AI weights (`sum=320`, `[35,85]` before origin bonus) with RimWorld passion flames (`불꽃` 1.25x, `쌍불꽃` 1.50x XP growth; fixed 3-point budget). | M2 | survey_2 |
| 10 | `F-03` | **Trait Draft & Personality Matrix (`성격 및 기질 특성`)** | 10 core traits (`의협`, `야심가`, `신중함`, `호주가`, `둔갑/기책`, `청렴`, `탐욕`, `맹장`, `둔전가`, `명사`) selected via interview/AI Light & Shadow Pairing (net cost `∈ [-1, +1]`), modifying work output, stipend demand, combat AI, and autonomous events. | M2 | survey_2 |
| 11 | `F-04` | **Starting Province & County Placement (`초기 거점 및 현 배치`)** | Select starting Province (`주`) and anchor Personal Manor (`장원`) in a low-threat starter County (`현`) on the shared world map. | M2 | survey_2, survey_3 |
| 12 | `F-05` | **Manor 32×32 Tile Grid, 7 Zones & 10 Buildings (`장원 그리드 및 시설`)** | `32×32` logical grid with 7 RimWorld zone types (`FARMLAND`, `STOCKPILE`, `HIDDEN_VAULT`, `BARRACKS`, `WORKSHOP`, `RESIDENCE`, `INFIRMARY`, `DEFENSE_LINE`) and 10 upgradable Manor structures. | M2 | survey_2, survey_3 |
| 13 | `F-06` | **7-Domain 1–4 Work Priority Matrix (`업무 우선순위 매트릭스`)** | RimWorld-style indirect control assigning each Pawn priorities `1..4` (or `0`) across `LOGISTICS`, `PATROL`, `AGRICULTURE`, `TRAINING`, `CRAFTING`, `RESEARCH`, `DIPLOMACY` (evaluated `1→4`, left-to-right). | M2 | survey_2, survey_3 |
| 14 | `F-07` | **12-ShiChen Daily Schedule (`십이지시 일과표`)** | 12 two-hour traditional time blocks (`자시`..`해시`) configurable per Pawn to `집무(Work)`, `연무(Drill)`, `연회/휴양(Recreation)`, `취침(Sleep)`, or `자율(Anything)`. | M2 | survey_2 |
| 15 | `F-08` | **Stockpile, Ration Quality & Wine Policy (`비축 및 배급 정책`)** | Configure ration tiers (`조식`, `일반식`, `특식/주찬`) and wine distribution rules balancing grain consumption against Pawn Mood and `호주가` needs. | M2 | survey_2 |
| 16 | `F-09` | **Manor Defense & Raid Auto-Repel (`장원 방어전`)** | Autonomous defense of Manor perimeter using Palisades/Walls, Watchtowers, Traps (`함정/녹각`), and `PATROL`-assigned pawns when raided while online or offline. | M2 | survey_2, survey_3 |
| 17 | `F-10` | **5-Need Tick Engine (`5대 욕구 시뮬레이터`)** | Continuous tick evaluation of `FOOD(군량)`, `REST(휴식)`, `MORALE(사기)`, `LOYALTY(충성)`, and `AMBITION(야망)` (`0..10000` basis points) with threshold modifiers. | M2 | survey_2, survey_3 |
| 18 | `F-11` | **Timed Thought & Mood Ledger (`사념 및 기분 장부`)** | Stackable positive/negative timed Thought modifiers feeding target Mood (`0..100`) with smooth interpolation. | M2 | survey_2 |
| 19 | `F-12` | **Mental Break State Machine & Catharsis (`심리 붕괴 및 심기일전`)** | Minor (`<35`: `폭음 난동`, `태업`), Major (`<20`: `독단 돌격`, `군자금 횡령`), and Extreme (`<10`: `하야`, `반란/내응`) breaks plus post-break `+35 Mood` Catharsis buffer. | M2 | survey_2 |
| 20 | `F-13` | **Heroic Awakening / Inspiration (`영웅적 각성`)** | High-Mood (`>85`) inspiration rolls granting temporary breakthroughs (`신묘한 기책`, `일기당천`, `명장 신기`, `민심 귀부`). | M2 | survey_2 |
| 21 | `F-14` | **Retainer Recruitment & Growth (`가신 등용 및 육성`)** | Recruit up to 12 personal sworn retainers from visiting talents, rescued villagers, or prisoners; train their 5 stats via work and drills. | M2 | survey_2 |
| 22 | `F-15` | **Health, Wounds & Herbal Medicine (`부상 및 의술/의막`)** | Health states (`정상`, `경상`, `중상`, `고질병/흉터`) treated in `ZONE_INFIRMARY` (`의막`) using Herbal Medicine (`탕약`) and Medical Care priority pawns. | M2 | survey_2, survey_3 |
| 23 | `F-16` | **8-Resource Economy Ledger (`8대 자원 체계`)** | Integer-scaled tracking of Grain (`군량`), Silver/Coin (`은전`), Timber (`목재`), Iron Ore (`철광`), Warhorses (`군마`), Herbs/Wine (`약재/주류`), Weapons/Armor (`병장기`), and Merit/Prestige (`공적/명망`). | M2 | survey_2, survey_3 |
| 24 | `F-17` | **Equipment Crafting & 6 Quality Tiers (`병장기 제작 및 6등급`)** | 3-tier crafting chains producing gear across 6 RimWorld quality tiers (`조악 0.8x` to `신물 1.8x`). | M2 | survey_2 |
| 25 | `F-18` | **Troop Equipment & Unit Promotion (`병종 무장 체계`)** | Combine conscripts with crafted gear/mounts to form specialized units (`창방병`, `장궁병`, `연노병`, `경기병`, `중장철기`, `충차/투석대`). | M3 | survey_2 |
| 26 | `F-19` | **Regional Caravan & Shared Market Order Book (`상단 무역 및 지역 거래소`)** | Per-node Hybrid Limit Order Book (`BID`/`ASK`) + AMM Baseline Reserve for strategic commodities, with physical caravan transport and arbitrage across edges. | M3 | survey_2, survey_3 |
| 27 | `F-20` | **Tech & Stratagem Research Tree (`병법 및 내정 기술도`)** | 3-branch research tree (`둔전/내정`, `진법/병종`, `기략/공성`) unlocked autonomously by `RESEARCH` priority pawns. | M2 | survey_2 |
| 28 | `F-21` | **Standing Tactical Doctrine Profile (`상시 교전 및 원정 수칙`)** | Declarative server-persisted combat rules (Engagement Stance, Formation, Supply Threshold, Retreat Condition, Duel Policy, Stratagem Usage, Prisoner Policy). | M3 | survey_2, survey_3 |
| 29 | `F-22` | **Deterministic Round-Based Auto-Battle (`랜체스터 전투 자동 연산`)** | Multi-round battle engine using Lanchester $N^{0.85}$ scaling across Archery/Skirmish → Duel/Stratagem → Melee Clash → Morale/Doctrine Retreat Check. | M3 | survey_2, survey_3 |
| 30 | `F-23` | **Officer 1v1 Duel Sub-Engine (`일기토 시뮬레이션`)** | 5-bout automated duel resolution using `MAR`, weapon quality, mount speed, and traits (`맹장`), shifting army Morale and risking injury/capture. | M3 | survey_2, survey_3 |
| 31 | `F-24` | **Battlefield Stratagems, Counter-Stratagems & Weather (`전장 계략/간파 및 기후`)** | `INT`-scaled execution and counter-detection (`간파 및 역계`) of Fire Attack (`화공`), Flood (`수공`), Ambush (`매복`), and Confusion (`혼란`) under dynamic weather. | M3 | survey_2 |
| 32 | `F-25` | **Multi-Army Coalition Siege & Supply Interdiction (`연합 공성전 및 보급 차단`)** | 3-phase siege resolution (Wall Bombardment → Gate Breach/Duel → Inner Keep Occupation) plus edge supply caravan raiding and escort bounties. | M4 | survey_2, survey_3 |
| 33 | `F-26` | **Structured Battle Replay & Telemetry Log (`전투 기록 및 리플레이`)** | Deterministic round-by-round JSON battle log allowing returning idle players to inspect casualties, duels, stratagems, and doctrine triggers. | M3 | survey_2 |
| 34 | `F-27` | **4-Tier Political Hierarchy & 9-Rank Court Merit Ladder (`신분 계층 및 구품 관직`)** | Progression across `Free Officer (재야)` → `Faction Officer (Rank 9..1)` → `City Governor (태수, Rank 5+)` → `Viceroy (도독, Rank 2+)` → `Sovereign Lord (군주)` with daily stipends (`봉록`). | M4 | survey_2, survey_3 |
| 35 | `F-28` | **Faction Mission Board & Idle Auto-Queue (`정청 임무판 및 자동 수주`)** | Officers configure Mission Auto-Queue preferences (`변경 수비`, `군량 호송`, `둔전 개간`, `치안 토벌`) to autonomously execute Lord/Governor tasks 24/7 for Merit and Silver. | M4 | survey_2 |
| 36 | `F-29` | **Retainer Proposal System (`헌책 및 건의`)** | Autonomous tactical and domestic proposals generated by subordinates based on traits (`신중함`, `둔전가`, `기책`); adoption boosts Loyalty and Ambition satisfaction. | M4 | survey_2 |
| 37 | `F-30` | **City Governor & Viceroy Delegation (`태수 및 도독 위임 통치`)** | Lords delegate cities exceeding direct governance capacity to Player or AI Governors (`태수`) and Viceroys (`도독`) who set local tax rates (`5%..25%`) and defense budgets. | M4 | survey_2, survey_3 |
| 38 | `F-31` | **Lord Macro Policy Sliders & Royal Rank (`군주 국정 정책 및 작위`)** | Faction-wide Tax/Levy, Conscription, and Stipend budget sliders plus Royal Rank ascension (`주자사` → `주목` → `공` → `왕` → `황제`). | M4 | survey_2 |
| 39 | `F-32` | **Espionage, Poaching, Defection & Independence Coup (`이간계, 회유, 하야 및 거병`)** | Covert `OP_SOW_DISCORD` (`이간계`), `OP_POACH_RETAINER` (`밀서 회유` when Loyalty `<60%`), Resignation (`하야`), Battlefield Turncoat (`전장 내응`), Governor Rebellion (`태수 독립`), and Free Officer Uprising (`재야 거병`). | M4 | survey_2, survey_3 |
| 40 | `F-33` | **Affinity & Social Relationship Graph (`인연 및 관계망`)** | Directed relationship graph (`-100..+100`) supporting Sworn Siblings (`도원결의 의형제` +15% joint attack), Spouse, Mentor, Benefactor, and Nemesis (`숙적`). | M4 | survey_2 |
| 41 | `F-34` | **Banquet & Social Hosting (`연회 및 문객 교류`)** | Automated or manual Banquets consuming Wine and Rations to restore Retainer Morale/Mood and recruit visiting wandering officers (`재야 기인`). | M4 | survey_2 |
| 42 | `F-35` | **Mandate of Heaven AI Storyteller (`천명 감독관 스토리텔러`)** | 3 Storyteller Personas (`사마천`, `동탁`, `문경지치`) driven by logarithmic Wealth + Force Threat Score ($T_i$) and RimWorld Adaptation Factor ($A_i \in [0.4, 1.5]$). | M3 | survey_2, survey_3 |
| 43 | `F-36` | **4-Season Cycle, Regional Chronicles & Treaties (`사계절, 천하 연표 및 외교 조약`)** | 4-Season cycle modifying farming/marching, server-enforced Treaties (`동맹`, `불가침`, `조공`, `통행권`) with `Oathbreaker (배신자)` penalties, and regional insurgency funding. | M4 | survey_2, survey_3 |
| 44 | `F-37` | **Season Era Hegemony & Lineage Succession (`시즌 천하통일 결산 및 가문 계승`)** | Season-end Hegemony scoring across Lord & Officer leaderboards plus optional Heir/Apprentice (`후계자`) mentorship inheritance. | M6 | survey_2 |
| 45 | `F-38` | **Reconnect Morning Court Gazette (`조보 / 지난 밤의 사기 브리핑`)** | Structured `MSG_OFFLINE_CHRONICLE_DIGEST` summarizing net offline resource yields, stipends, completed missions, mental breaks/awakenings, and battle replays on login. | M5 | survey_2, survey_3 |
| 46 | `F-39` | **Asynchronous Event Decision Queue (`결재 서신함 및 기본 수칙 폴백`)** | Non-blocking decision inbox (ransom offers, envoy bribes, appointments) with automatic Default Doctrine Fallback Timer so shared-world simulation never stalls. | M5 | survey_2 |
| 47 | `F-40` | **4-Pillar Offline Protection (`비상 지하창고, 가신 불사, 전령 경보, 휴전 보호막`)** | Hidden Vault (40–65% resource protection), Sworn Retainer non-permadeath injury recovery (`중상/요양`), 72h Novice Shield, Siege Encampment Warning delay, and Post-Raid Imperial Truce Shield. | M2 | survey_2, survey_3 |
| 48 | `F-41` | **Dynamic Micro LOD (`LOD 0` ↔ `LOD 1`) & Cross-Layer Graph Bridge** | Seamless promotion/demotion between `LOD 0` (`1s` tile sim) and `LOD 1` (`6s` rate-integrated sim) coupled to the Macro Graph $G=(V,E)$ via typed events. | M3 | survey_3 |
| 49 | `F-42` | **Pluggable Network Transport & 4-Channel Interest Delta Protocol** | `INetworkTransport` (`WebSocketTransport`, `ENetTransport`, `LoopbackMemoryTransport`) with dirty-bit delta packets (`MSG_TICK_DELTA`) across `CHAN_GLOBAL_MACRO`, `CHAN_FACTION`, `CHAN_NODE`, `CHAN_MANOR`. | M5 | survey_1, survey_3 |
| 50 | `F-43` | **6-Stage Server-Authoritative Command Validation & Anti-Cheat Pipeline** | Wire safety (`bytes_to_var` object deserialization disabled), session ownership binding, monotonic `cmd_seq` + token-bucket rate limiter, political role check, resource escrow check, and audit logging. | M5 | survey_1, survey_3 |
| 51 | `F-44` | **Hybrid JSONL WAL + `/usr/bin/sqlite3` Relational Persistence Engine** | Real-time `wal_commands.jsonl` + double-buffered atomic JSON snapshots + transactional `/usr/bin/sqlite3` sync to `saves/world_state.db` (10 relational tables including `persona_import_challenges`) with deterministic crash replay. | M5 | survey_3 |
| 52 | `F-45` | **Programmatic Godot 4 Client UI Views (`장원 뷰 / 천하 전략도 / 정청 및 거래소 HUD`)** | Code-first GDScript client views (`src/ui/`) rendering the `32×32` Manor grid, Work Priority Matrix & Schedule editor, Three Kingdoms Macro Graph, Coalition Siege planner, and Morning Gazette modal. | M6 | survey_1, survey_3 |
| 53 | `FH-07` | **Godot 4.4.1 Web (HTML5/WASM) Export & GitHub Pages CI/CD Pipeline** | Single-threaded WebGL 2.0 (`gl_compatibility`, `variant/thread_support=false`) `export_presets.cfg`, `coi-serviceworker.js` isolation shim, and automated `.github/workflows/deploy-pages.yml` publishing the playable HTML5/WASM client build (`index.html`, `.wasm`, `.pck`, `.js`) to GitHub Pages. | M7 | m7_survey_1, m7_survey_2, m7_survey_3 |
| 54 | `F-46` | **Browser-Playable WebAssembly Live Demo & Korean CJK Web Font / PCK Runtime Compatibility** | Auto-starting in-browser `LiveSessionDriver` local demo (`player_01` + `lord_wei` + `ally_shu`), `.pck`-first `ResourceLoader` audio/texture loading, and bundled Korean CJK `FontFile` support for WebAssembly where `SystemFont` is unavailable. | M7 | m7_survey_1, m7_survey_2 |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| **M0** | **Phase 0: AI Agent Harness & Game Design / Technical Architecture Blueprint (User Confirmation Gate)** | Author and verify the complete AI Agent Godot 4 Harness Specification (`docs/01_AI_AGENT_HARNESS_SPEC.md`), Game Design Document (`docs/02_GAME_DESIGN_DOCUMENT.md`), Shared-World Multiplayer Technical Architecture (`docs/03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md`), User Confirmation Checklist (`docs/04_USER_CONFIRMATION_CHECKLIST.md`), SQLite Relational Schema (`data/schemas/world_state_schema.sql`), and automated Blueprint/Schema Verification Script (`scripts/harness/verify_blueprint.py`). Pause for User Confirmation after M0 gate passes. (`FH-00`) | none | DONE (User Confirmed `"진행해. 확인 완료."` — Defaults `D-01`..`D-06` Approved; `VICTORY CONFIRMED`) |
| **M1** | **Toolchain Setup, Core Deterministic Engine & Stage 1–2 Headless Harness** | Provision user-space Godot 4 binary (`scripts/setup_godot.sh`), strict `project.godot`, Stage 1 syntax/schema gate (`check_syntax.sh`, `validate_data.gd`), Stage 2 headless test runner (`test_case.gd`, `test_runner.gd`), and deterministic core (`SimClock`, `DeterministicRNG`, `StateHasher`, `SimEventBus`, `dto_schemas.gd`, `sealed_token_codec.gd`, `data/persona_seal_rules.json`). (`FH-01`..`FH-04`) | M0 (User Confirmation) | DONE (Verified: Godot 4.4.1, Stage 1 15 files PASS, Stage 2 40/40 tests & 637 assertions PASS, Forensic Audit CLEAN) |
| **M2** | **Layer 1: RimWorld Micro Manor, Autonomous Pawns & Stage 3 Sim Harness** | Implement `32×32` Manor Grid & 7 Zones, 10 Buildings, Character Creation (`F-01`..`F-04`), 5 Stats + Passion Flames, 5 RimWorld Needs, 10 Traits, Timed Thoughts/Mood/Mental Breaks/Heroic Awakenings, 7-Domain 1–4 Work Priority Matrix, 12-ShiChen Schedule, 8-Resource Economy & 6-Tier Crafting, Tech Research, `LOD 0`/`LOD 1` processors, Manor Raid Defense + Hidden Vault & Offline Retainer Survival, and Stage 3 `sim_harness.gd`. (`FH-05`, `F-01`..`F-17`, `F-20`, `F-40`) | M1 | DONE (Verified: Stage 1 24 files PASS, Stage 2 58/58 tests & 2199 assertions PASS, Stage 3 10k-tick + LOD0/1 parity + 3 adversarial unseen seeds PASS, Forensic Audit CLEAN) |
| **M3** | **Layer 2: Shared Three Kingdoms Macro Graph, Doctrines, Auto-Battle & Storyteller** | Implement Macro Graph $G=(V,E)$ (`macro_map_3k.json`), Cross-Layer Micro↔Macro Bridge (`F-41`), Troop Equipment & Unit Promotion (`F-18`), Standing Tactical Doctrines (`F-21`), Lanchester $N^{0.85}$ Round-Based Auto-Battle (`F-22`), 5-Bout Officer Duels (`F-23`), Battlefield Stratagems & Weather (`F-24`), Battle Replay JSON logs (`F-26`), Regional Limit Order Book + AMM Market & Caravans (`F-19`), and Mandate of Heaven AI Storyteller (`F-35`). (`F-18`, `F-19`, `F-21`..`F-24`, `F-26`, `F-35`, `F-41`) | M2 | DONE (Verified: Stage 1 34 files & 7 JSON PASS, Stage 2 77/77 tests & 4083 assertions PASS, Forensic Audit CLEAN) |
| **M4** | **Dual Roleplay Politics (Officer ↔ Lord), Coalition Sieges, Espionage & Diplomacy** | Implement 4-Tier Hierarchy & 9-Rank Court Merit Ladder (`F-27`), Faction Mission Board & Idle Auto-Queue (`F-28`), Retainer Proposals (`F-29`), Governor (`태수`) & Viceroy (`도독`) Delegation (`F-30`), Lord Macro Policy Sliders (`F-31`), Espionage/Poaching/Defection/Governor Rebellion (`F-32`), Multi-Army Coalition Sieges & Supply Interdiction (`F-25`), Affinity/Sworn Sibling Graph (`F-33`), Banquets (`F-34`), and 4-Season Cycle & Treaties (`F-36`). (`F-25`, `F-27`..`F-34`, `F-36`) | M3 | DONE (Verified: Stage 1 44 files & 7 JSON PASS, Stage 2 94/94 tests & 4377 assertions PASS, Forensic Audit CLEAN) |
| **M5** | **Authoritative Network Protocol, 6-Stage Security & Hybrid WAL + SQLite Persistence** | Implement `INetworkTransport` (`WebSocket`, `ENet`, `LoopbackMemory`) & 4-Channel Interest Delta Manager (`F-42`), 6-Stage Command Validator & Token-Bucket Rate Limiter (`F-43`), Hybrid JSONL WAL + Atomic Snapshot + `/usr/bin/sqlite3` `world_state.db` Persistence Engine (`F-44`), Reconnect Morning Court Gazette (`F-38`), and Asynchronous Event Decision Queue (`F-39`). (`F-38`, `F-39`, `F-42`..`F-44`) | M4 | DONE (Verified: Stage 1 56 files & 7 JSON PASS, Stage 2 102/102 tests & 4587 assertions PASS, 10-table SQLite + WAL/Snapshot + 6-stage anti-cheat verified, Forensic Audit CLEAN) |
| **M6** | **Programmatic Client UI Views, Season Hegemony & Full Shared-World E2E Verification** | Implement Programmatic GDScript Client UI Views (`F-45`), Season Era Hegemony & Lineage Succession (`F-37`), Stage 4 Multi-Process/Multi-Client Shared-World Smoke Harness (`FH-06`: `net_harness.gd`, `run_net_smoke.py`, `audit_verifier.py`), and pass 100% of E2E tests (Tiers 1–4) + Tier 5 Adversarial Coverage Hardening. (`FH-06`, `F-37`, `F-45`) | M5 | DONE (Verified: Stage 1 64 GDScript & 7 JSON --strict --require-all PASS, Stage 2 110/110 tests & 4853 assertions PASS, Stage 3 10k-tick + 3 unseen seeds PASS, Stage 4 Loopback + Multi-Process WebSocket + 10-table SQLite Audit PASS, Headless Scene Boot PASS, Forensic Checks #1–#7 CLEAN) |
| **M7** | **Godot 4.4.1 Web (HTML5/WASM) Export & GitHub Pages Live Browser Demo Deployment** | Configure `export_presets.cfg` (`Web` single-threaded WASM + `coi-serviceworker.js`), `project.godot` WebGL2 `gl_compatibility` renderer, Web Korean CJK font & `.pck` audio/asset loading compatibility, `.github/workflows/deploy-pages.yml` CI/CD deployment pipeline, GitHub Pages enablement, unit tests, and `README.md` live browser demo documentation with 0 regressions across Stage 0–4. (`FH-07`, `F-46`) | M6 | IN_PROGRESS |

---

## Interface Contracts

### 1. `src/core` ↔ All Simulation Modules (`src/micro`, `src/macro`, `src/faction`)
- **Deterministic Serializable Entity Contract**:
  Every authoritative state class MUST `extends RefCounted` and implement:
  - `func to_dict() -> Dictionary`: Returns a canonical dictionary with primitive/array/dict values only (all fractional quantities scaled as `int64` basis points / permille `SCALE = 1000`).
  - `static func from_dict(data: Dictionary) -> RefCounted`: Reconstructs exact in-memory state from `to_dict()`.
- **Deterministic Random Contract (`src/core/deterministic_rng.gd`)**:
  - `static func roll_range(world_seed: int, tick_id: int, entity_id: int, salt: int, min_val: int, max_val: int) -> int`
  - Unseeded `randf()`, `randi()`, `randomize()`, and wall-clock `Time.get_ticks_msec()` / `Time.get_unix_time_from_system()` calls are strictly forbidden inside `src/micro/`, `src/macro/`, and `src/faction/`.

### 2. `src/micro` ↔ `src/macro` (`src/core/sim_event_bus.gd`)
- **`MICRO_TO_MACRO_EXPEDITION_DISPATCHED`**:
  - Payload: `{ "event": "MICRO_TO_MACRO_EXPEDITION_DISPATCHED", "tick_id": int, "player_id": String, "manor_id": String, "origin_node_id": String, "unit_type": String ("ARMY"|"CARAVAN"), "officers": Array[Dictionary], "troop_count": int, "morale_bp": int, "carried_grain": int, "cargo": Dictionary, "path_edge_ids": Array[String], "standing_doctrine": Dictionary }`
  - Invariant: Dispatched officers transition to `STATE_ON_EXPEDITION` in `manor_state.gd`, and `troop_count` + `carried_grain` + `cargo` are atomically deducted from Manor stockpiles before the Macro entity spawns on `path_edge_ids[0]`.
- **`MACRO_TO_MICRO_RAID_INCOMING`**:
  - Payload: `{ "event": "MACRO_TO_MICRO_RAID_INCOMING", "tick_id": int, "target_manor_id": String, "host_node_id": String, "attacker_entity_id": String, "attacker_owner_id": String, "attacker_power": Dictionary, "promote_to_lod0": true }`
  - Invariant: Immediately promotes `target_manor_id` from `LOD 1` to `LOD 0`, evaluates `manor.standing_doctrine`, protects `vault_protected_bp` resources in `ZONE_HIDDEN_VAULT`, guarantees non-permadeath (`STATE_WOUNDED`) for defending Sworn Retainers while owner is offline, and activates `truce_shield_until_tick` on breach.

### 3. `src/ui` / Client ↔ `src/net` Authoritative Server (`src/core/dto_schemas.gd`)
- **Client Intent Command Envelope (`CommandEnvelope`)**:
  - `{ "v": 1, "cmd_seq": int, "client_tick": int, "player_id": String, "cmd_type": String, "args": Dictionary }`
  - Validated through the 6-Stage `CommandValidator` (`ERR_SCHEMA`, `ERR_UNAUTHORIZED`, `ERR_RATE_LIMITED`, `ERR_ROLE_PERMISSION`, `ERR_INSUFFICIENT_RESOURCE`, `ERR_INVALID_STATE`).
- **Server Command Receipt (`MSG_CMD_RECEIPT`)**:
  - `{ "v": 1, "msg_type": "MSG_CMD_RECEIPT", "cmd_seq": int, "status": "ACCEPTED"|"REJECTED", "error_code": String, "exec_tick_id": int }`
- **Server Interest-Filtered Tick Delta (`MSG_TICK_DELTA`)**:
  - `{ "v": 1, "msg_type": "MSG_TICK_DELTA", "tick_id": int, "macro_tick_id": int, "day_id": int, "season": String, "state_crc32": int, "channels": Dictionary, "events": Array[Dictionary] }`

### 4. `src/persistence` ↔ `/usr/bin/sqlite3` (`data/schemas/world_state_schema.sql`)
- **WAL Record Schema (`saves/wal_commands.jsonl`)**:
  - `{ "tick_id": int, "cmd_seq": int, "player_id": String, "cmd_type": String, "payload": Dictionary, "crc32": int }`
- **SQLite Relational Checkpoint (`saves/world_state.db`)**:
  - 10 canonical tables (`world_meta`, `factions`, `macro_nodes`, `persona_import_challenges`, `players`, `manors`, `pawns_officers`, `armies_caravans`, `market_orders`, `command_audit_log`) synchronized transactionally on every `DAILY_SETTLEMENT_TICK` and audited by `tools/harness/audit_verifier.py`.

---

## Code Layout

```
/home/antigravity/
├── PROJECT.md                           # Global Architecture, Feature Inventory, Milestones, Contracts
├── project.godot                        # Godot 4 project config (strict GDScript warnings-as-errors = 2, Web gl_compatibility)
├── export_presets.cfg                   # [M7] Godot 4.4.1 Web (HTML5/WASM) export preset (single-threaded + coi-serviceworker)
├── .github/
│   └── workflows/
│       └── deploy-pages.yml             # [M7] Automated Godot 4.4.1 Web export & GitHub Pages deployment workflow
├── web/
│   └── coi-serviceworker.js             # [M7] Cross-Origin-Isolation service worker shim for GitHub Pages
├── docs/                                # [M0 Deliverables] Concrete Specifications & User Confirmation Gate
│   ├── 01_AI_AGENT_HARNESS_SPEC.md      # AI Agent Godot 4 Development & Verification Harness Spec
│   ├── 02_GAME_DESIGN_DOCUMENT.md       # Complete Three Kingdoms × RimWorld Shared-World Idle GDD
│   ├── 03_SHARED_WORLD_MULTIPLAYER_ARCHITECTURE.md # Two-Layer Sim, Network, Security & Persistence Spec
│   └── 04_USER_CONFIRMATION_CHECKLIST.md # Structured Decision & Confirmation Checklist for User Review
├── scripts/
│   ├── setup_godot.sh                   # User-space Godot 4 Linux x86_64 bootstrap with SHA-512 verification
│   └── harness/
│       ├── verify_blueprint.py          # [M0] Automated verifier for docs, feature coverage, SQLite DDL & TK3K2 codec
│       ├── check_syntax.sh              # [M1] Stage 1: Class cache warmup + --check-only + JSON validation
│       ├── run_tests.sh                 # [M1] Stage 2: Headless unit & integration test suite runner
│       ├── run_sim.sh                   # [M2] Stage 3: Deterministic N-tick simulation & offline parity runner
│       └── run_net_smoke.py             # [M6] Stage 4: Multi-process 1-server + N-bot shared-world verifier
├── data/
│   ├── schemas/
│   │   └── world_state_schema.sql       # [M0/M5] Canonical SQLite DDL for saves/world_state.db (10 tables)
│   ├── macro_map_3k.json                # Three Kingdoms Macro Graph nodes (V) & edges (E)
│   ├── officers_catalog.json            # Historical & procedural Officer templates, stats & traits
│   ├── interview_questions.json         # 8-scene Three Kingdoms interview bank & AI persona fusion mappings
│   ├── persona_seal_rules.json          # TK3K2 Base-31 alphabet, trait light/shadow costs & coercion thresholds
│   ├── items_buildings.json             # Manor zones, 10 buildings, 8 resources & crafting recipes
│   ├── storytellers.json                # Mandate of Heaven Storyteller configs (Sima Qian, Dong Zhuo, Wen-Jing)
│   └── scenarios/                       # Deterministic seed scenarios for sim_harness & net_harness
├── src/
│   ├── core/                            # SimClock, DeterministicRNG, StateHasher, SimEventBus, dto_schemas, sealed_token_codec
│   ├── micro/                           # ManorState (32x32), PawnEntity, JobScheduler (1-4), LOD0/1, RaidDefense
│   ├── macro/                           # WorldGraph, ArmyCaravanManager, RegionalMarket, SiegeResolver, Storyteller
│   ├── faction/                         # FactionManager (4-Tier / 9-Rank), DiplomacyTreatyEngine, EspionageService
│   ├── net/                             # INetworkTransport, AuthoritativeServer, CommandValidator, InterestDelta
│   ├── persistence/                     # WALLogger (JSONL), SnapshotSerializer, SQLiteBridge (/usr/bin/sqlite3)
│   └── ui/                              # Programmatic client views (ManorGridView, MacroMapView, CourtMarketHUD)
├── scenes/                              # Minimal (<30 lines) static bootstrapper scenes
│   ├── main_client.tscn
│   └── headless_server.tscn
├── tools/
│   └── harness/                         # test_case.gd, test_runner.gd, validate_data.gd, sim_harness.gd, net_harness.gd, audit_verifier.py
└── tests/                               # [Owner: Test Writer ONLY] Unit & Integration test suites
```
