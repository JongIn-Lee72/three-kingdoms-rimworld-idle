# 03. 공유 월드 멀티플레이어 및 기술 아키텍처 명세서 (Shared-World Multiplayer Technical Architecture)

- **문서 버전**: `v1.0.0` (Milestone `M0` / Feature `FH-00`)
- **대상 시스템**: Godot 4 단일 코드베이스 권위 서버(Authoritative Server) + 2계층 결합 결정론적 시뮬레이션 엔진 + WAL/SQLite 하이브리드 영속성 아키텍처
- **관련 기능 ID**: `FH-00` ~ `FH-06`, `F-01` ~ `F-45` (특히 `F-19`, `F-25`, `F-27` ~ `F-44`)

---

## 1. 아키텍처 개요 및 2계층 결합 시뮬레이션 엔진 (Two-Layer Coupled Simulation Engine — `F-41`)

수백 명의 플레이어가 동일한 삼국지 천하(단일 서버)에서 활동하면서도 각자의 장원에서는 림월드(RimWorld) 수준의 정교한 가신 자율 생활 시뮬레이션을 누릴 수 있도록, 공간과 연산 주기를 **마이크로 계층(Layer 1)** 과 **매크로 계층(Layer 2)** 으로 분리하고 타입화된 이벤트 버스(`SimEventBus`)로 결합한다.

```
+========================================================================================+
|                   GODOT 4 AUTHORITATIVE SHARED-WORLD SERVER (HEADLESS)                 |
|                                                                                        |
|  +----------------------------------------------------------------------------------+  |
|  | LAYER 2: 매크로 전략 계층 (천하 전략도 그래프 G = (V, E) — src/macro/, src/faction/)|  |
|  |  - 노드 (V): 주/군/대도시/현성/관문 (비옥도, 성벽 내구도, 치안, 지역 거래소 호가창)|  |
|  |  - 간선 (E): 관도(Highway), 산길(Mountain), 수운(River) — 출진 부대 및 상단 이동  |  |
|  |  - 공유 시스템: 4단계 신분/구품 관직, 연합 공성전, 보급선 약탈/호위, 이간/회유,    |  |
|  |                 서버 강제 외교 조약, 천명 감독관(사마천/동탁/문경지치) 스토리텔러  |  |
|  +------------------------------------^-----------------------+---------------------+  |
|                                       |                       |                        |
|               마이크로 -> 매크로 이벤트|                       | 매크로 -> 마이크로 이벤트|
|       (MICRO_TO_MACRO_EXPEDITION,     |                       | (MACRO_TO_MICRO_RAID,  |
|        세금 납부, 거래소 지정가 주문)  |                       |  봉록 지급, 계절/기후) |
|                                       |                       v                        |
|  +------------------------------------+---------------------------------------------+  |
|  | LAYER 1: 마이크로 림월드 계층 (인스턴스화된 개인 장원 32x32 — src/micro/)         |  |
|  |  +--------------------------+  +--------------------------+  +----------------+  |  |
|  |  | 플레이어 A 장원 [LOD 0]  |  | 플레이어 B 장원 [LOD 0]  |  | 플레이어 C..N  |  |  |
|  |  | (온라인 / 방어전 진행중) |  | (온라인 / 타인 관전중)   |  | 장원 [LOD 1]   |  |  |
|  |  | - 32x32 타일 및 7대 구역 |  | - 32x32 타일 및 7대 구역 |  | (오프라인 평화)|  |  |
|  |  | - 1초 마이크로 틱 연산   |  | - 1초 마이크로 틱 연산   |  | - 6초 매크로 틱|  |  |
|  |  | - 1~4 우선순위 & 일과표  |  | - 1~4 우선순위 & 일과표  |  |   비율 적분식  |  |  |
|  |  +--------------------------+  +--------------------------+  +----------------+  |  |
|  +----------------------------------------------------------------------------------+  |
|                                       |                                                |
|  +------------------------------------v---------------------------------------------+  |
|  | 권위 게이트웨이 및 영속성 계층 (src/net/, src/persistence/)                       |  |
|  |  - 6단계 서버 권위 명령 검증 파이프라인 & 토큰 버킷 속도 제한기 (`F-43`)          |  |
|  |  - 4채널 관심 영역 필터링 및 더티 비트 델타 압축 (`MSG_TICK_DELTA`, `F-42`)       |  |
|  |  - 실시간 JSONL WAL (`wal_commands.jsonl`) + 원자적 스냅샷 + `/usr/bin/sqlite3`   |  |
|  +----------------------------------------------------------------------------------+  |
+========================================================================================+
```

### 1.1 Layer 1: 마이크로 장원 시뮬레이션 및 동적 LOD (`LOD 0` ↔ `LOD 1`)

1. **`LOD 0` (활성 / 관전 중 / 습격 방어전 진행 중 — `MICRO_TICK = 1.0s`)**:
   - 플레이어가 온라인이거나 다른 플레이어가 해당 장원을 관전(`CHAN_MANOR:<manor_id>` 구독) 중이거나 적의 습격(`MACRO_TO_MICRO_RAID_INCOMING`)이 진행 중일 때 활성화된다.
   - 매 1.0초(`MICRO_TICK`)마다 장원 내 각 가신/사병의 2D 그리드 위치, 작업 진행도, 욕구 변화, 전투 라운드를 단계별로 정밀 시뮬레이션한다:
     $$\Delta W_{\text{tick}}(p, j) = W_{\text{base}}(j) \times \left(1 + \frac{\text{Stat}_{\text{domain}}(p)}{100}\right) \times M_{\text{mood}}(p) \times M_{\text{facility}}(j) \times M_{\text{weather}}$$
2. **`LOD 1` (비관찰 오프라인 평화 상태 — `MACRO_TICK = 6.0s`)**:
   - 외부 간섭이 없는 오프라인 장원은 서버 CPU(2 vCPU 기준 수백 개 장원 동시 처리) 최적화를 위해 매 6.0초(`MACRO_TICK`)마다 동일한 1–4 업무 우선순위 매트릭스와 십이지시 일과표에서 유도된 **결정론적 비율 적분 방정식(Rate-Integrated Equation)** 으로 연산한다:
     $$\Delta W_{\text{macro}}(j) = \sum_{p \in \text{Pawns}} 6 \cdot \eta_{\text{walk}}(j) \cdot \alpha_{p,j} \cdot \Delta W_{\text{tick}}(p, j)$$
   - 여기서 $\alpha_{p,j} \in [0, 1]$는 가신 $p$의 일과표 및 1–4 우선순위 행에서 도출된 정규화 시간 배분 가중치이며, $\eta_{\text{walk}}(j) \in [0.75, 0.92]$는 장원 구역 배치 거리에서 캐싱된 이동 효율 상수이다.
3. **무단절 즉시 승격 (Zero-Discontinuity Instant Promotion)**:
   - 오프라인(`LOD 1`) 장원에 적 습격 부대가 도착하거나 플레이어가 접속/관전하는 즉시 해당 틱 경계에서 `LOD 0`으로 승격되어 타일 단위 전술 방어전과 작업이 한 치의 자원 불연속 없이 이어진다.

### 1.2 Layer 2: 매크로 삼국지 천하 전략도 그래프 $G = (V, E)$

- **노드 ($v \in V$ — 주/군/성/현/관문)**:
  - `node_tier`: `CAPITAL_METROPOLIS`(도성: 낙양·허창·업·양양·성도·건업 등), `COMMANDERY_CITY`(군치 대도시), `COUNTY_TOWN`(현성 — 플레이어 장원 정박지), `STRATEGIC_PASS`(관문/나루: 호로관·함곡관·적벽 등).
  - 상태 속성: `owner_faction_id`, `governor_player_id`, `fortification_hp`, `public_order_bp`(`0..10000`), `bandit_pressure_bp`(`0..10000`), `tax_rate_bp`(표준 태수 `500..2500`, 전시·비상 스키마 상한 `500..5000`), `treasury_grain`, `treasury_coin`, `grain_price_bp`, `iron_price_bp`.
- **간선 ($e = (u, v) \in E$ — 가도/산길/수운)**:
  - 상태 속성: `edge_id`, `from_node_id`, `to_node_id`, `distance_li`(거리), `terrain_type`(`HIGHWAY`, `MOUNTAIN_ROAD`, `RIVER_ROUTE`), `active_transits`(현재 행군 중인 군대 및 보급 상단 목록, 진행도 `edge_progress_pm` `0..1000`).

### 1.3 계층 간 결합 이벤트 계약 (`src/core/sim_event_bus.gd`)

1. **`MICRO_TO_MACRO_EXPEDITION_DISPATCHED` (장원 → 천하 전략도 출진/상단 파견)**:
   ```json
   {
     "event": "MICRO_TO_MACRO_EXPEDITION_DISPATCHED",
     "tick_id": 1441,
     "player_id": "player_01",
     "manor_id": "manor_player_01",
     "origin_node_id": "xuchang",
     "unit_type": "ARMY",
     "officers": [
       {"pawn_id": "pawn_01", "leadership": 86, "martial": 91, "intelligence": 74, "traits": ["T_FIERCE"]}
     ],
     "troop_count": 300,
     "morale_bp": 9500,
     "carried_grain": 1800,
     "cargo": {"WEAPONS": 50},
     "path_edge_ids": ["edge_xuchang_luoyang"],
     "standing_doctrine": {"retreat_morale_bp": 2500, "duel_policy": "ACCEPT_IF_ADVANTAGE"}
   }
   ```
   - **원자적 보존 불변식 (`INV-WORLD-CONSERVATION`)**: 이벤트 발행 시 출진 장수들은 장원에서 즉시 `STATE_ON_EXPEDITION`으로 전환되어 장원 내 작업/방어 풀에서 제외되며, `troop_count`, `carried_grain`, `cargo`가 장원 비축고에서 원자적으로 차감된 뒤 매크로 간선 `path_edge_ids[0]`에 엔티티가 생성된다.

2. **`MACRO_TO_MICRO_RAID_INCOMING` (천하 전략도 → 장원 습격 도달)**:
   ```json
   {
     "event": "MACRO_TO_MICRO_RAID_INCOMING",
     "tick_id": 1520,
     "target_manor_id": "manor_player_02",
     "host_node_id": "yingchuan",
     "attacker_entity_id": "army_raider_88",
     "attacker_owner_id": "player_09",
     "attacker_power": {"troop_count": 220, "lead_martial": 84, "lead_leadership": 79, "siege_bonus_bp": 1100},
     "promote_to_lod0": true
   }
   ```
   - **방어 불변식**: 즉시 대상 장원을 `LOD 0`으로 승격시키고, `manor.standing_doctrine`을 평가하며, 비상 지하창고(`vault_protected_bp`) 자원을 보호하고, 오프라인 가신 불사(`STATE_WOUNDED`) 및 패배 후 휴전 보호막(`truce_shield_until_tick`)을 적용한다.

---

## 2. 4단계 정치 신분 상태 머신 및 6대 플레이어 간 상호작용 (`F-19`, `F-25`, `F-27` ~ `F-36`)

### 2.1 4단계 정치 계층 (`role_tier`)
- **`FREE_OFFICER` (재야 장수)**: 소속 세력 없음. 세금 면제, 황건적 토벌 현상금·상단 호위/약탈·재야 거병 가능.
- **`FACTION_OFFICER` (일반 장수, 구품~일품)**: AI 또는 플레이어 군주 휘하. 일일 봉록(`Stipend`) 수령, 정청 임무 자동 수행, 연합 공성전 참전, 이간/회유/하야 가능.
- **`GOVERNOR` (태수/도독, 오품~이품)**: 군주로부터 1개 이상의 매크로 도시 노드를 위임받아 세율(`500..2500 bp`), 성벽 보수, 수비대 예산을 통제. 충성도 저하 시 도시를 통째로 들고 **태수 독립 반란** 가능.
- **`LORD` (군주)**: 세력 수도 및 국정 정책 통할, 태수/중신 임명, 외교 조약(`동맹/불가침/조공/통행권`) 체결, 연합 공성전 집결령 발령.

### 2.2 6대 플레이어 간 협동 및 경쟁(Co-op & PvP) 시스템

1. **다중 플레이어 연합 공성전 (`F-25: Joint Coalition Sieges`)**:
   - 군주/태수가 적 거점에 대해 집결령(`CMD_CREATE_COALITION_RALLY`)을 발령하면 동맹 장수들이 각자의 장원에서 병력과 공성기를 파견한다.
   - 공성전은 매크로 틱마다 **1페이즈(성벽 포격) → 2페이즈(성문 돌파 및 선봉 1v1 일기토 `±1500~1800 bp` 사기 변동) → 3페이즈(내성 점령)** 으로 진행되며, 승리 시 전리품과 전공(`war_merit`)이 기여도 공식에 따라 분배된다:
     $$\text{Share}_i = \frac{0.5 \cdot \text{DamageDealt}_i + 0.3 \cdot \text{DamageAbsorbed}_i + 0.2 \cdot \text{SupplyContributed}_i}{\sum_{k \in \text{Coalition}} \text{TotalScore}_k}$$
2. **보급 상단 호위 및 간선 매복 약탈 (`F-19`, `F-25: Supply Caravan Raiding & Escorting`)**:
   - 출진 부대는 매크로 틱마다 $C_{\text{grain}} = N_{\text{troops}} \times 2$의 군량을 소모하며, 군량 고갈 시 기아 탈영(매크로 틱당 사기 `-1500 bp`, 병력 `-5%`)을 겪는다.
   - 플레이어들은 보급 상단을 파견하고 호위 현상금(`CMD_POST_ESCORT_CONTRACT`)을 걸 수 있으며, 적대 플레이어는 산길/수운 간선에 매복 부대(`CMD_SET_EDGE_AMBUSH`)를 배치해 상단 화물의 최대 60%를 탈취할 수 있다.
3. **세작 침투, 이간계 및 가신 밀서 회유 (`F-32: Officer Espionage & Poaching`)**:
   - `CMD_EXECUTE_ESPIONAGE`를 통해 적 장원의 가신 충성도를 깎거나(`OP_SOW_DISCORD`), 충성도 `< 6000 bp`인 가신을 매수(`OP_POACH_RETAINER`)하여 자신의 장원으로 빼올 수 있다. 방어측은 `PATROL` 우선순위 가신과 망루로 적 세작을 체포해 몸값을 요구한다.
4. **지역 지정가 호가창 + AMM 거래소 및 상단 차익 거래 (`F-19: Regional Limit Order Book + AMM`)**:
   - 각 매크로 노드 $v \in V$는 6대 전략 물자(`GRAIN`, `IRON`, `WOOD`, `HORSES`, `WEAPONS`, `HERBS_WINE`)에 대해 독립된 지정가 주문장(`BID`/`ASK`)과 기초 유동성 AMM을 운영한다. 전선 도시의 군량 시세가 폭등하면 후방 농경 플레이어가 상단으로 군량을 운송해 차익을 실현한다.
5. **서버 강제 외교 조약 및 배신자 페널티 (`F-36: Server-Enforced Treaties & Oathbreaker`)**:
   - 군주 간 체결된 조약(`TREATY_ALLIANCE`, `TREATY_NON_AGGRESSION`, `TREATY_MILITARY_ACCESS`, `TREATY_VASSAL_TRIBUTE`)을 기간 만료 전 파기(`CMD_BREAK_TREATY`)하면 15 인게임 일 동안 전 세력에 **`배신자(Oathbreaker)`** 디버프(`의협` 장수 충성도 `-1500 bp`, 외교 평판 `-30%`)가 강제 적용된다.
6. **거점 통치 경쟁 및 반란군 자금 지원 (`F-30`, `F-36: Territory Governance & Insurgency`)**:
   - 치안(`public_order_bp`)이 `3500 bp` 미만으로 떨어진 적 도시에는 경쟁 세력이 황건 잔당/도적 자금 지원(`CMD_FUND_INSURGENTS`)을 실행하여 내부 반란 레이드를 유발할 수 있다.

---

## 3. 4대 오프라인 보호 아키텍처 (4-Pillar Offline Protection System — `F-38` ~ `F-40`)

공유 월드에서 8~24시간 오프라인 자리를 비운 플레이어가 하루아침에 파산하거나 핵심 장수를 잃지 않도록 서버 커널 수준에서 4중 보호 장치를 강제한다:

1. **서버 상시 교전 및 내정 수칙 (`Server-Side Standing Doctrines`, `F-21`)**:
   - `manors.standing_doctrine_json`에 저장된 방어 태세(`HOLD_WALLS_THEN_VAULT`, 적 전투력 1.3배 초과 시 주력 대피 `EVACUATE_ON_OVERWHELM`), 군량 5일분 미만 시 자동 시장 매수(`auto_market_replenish`), 부상 가신 자동 의막 후송(`auto_medical_triage`)이 플레이어 접속 여부와 무관하게 매 틱 실행된다.
2. **비상 지하창고 (`Hidden Vault 40%~65%`) 및 오프라인 가신 불사 규칙 (`F-40`)**:
   - `ZONE_HIDDEN_VAULT`는 장원 방어전 패배 시에도 핵심 자원의 `4000..6500 bp`(`40%~65%`)를 약탈로부터 완벽히 보호한다.
   - 플레이어가 오프라인(`players.is_online == 0`)인 동안 발생한 방어전에서는 주인공과 가신이 절대 영구 사망하지 않으며, `STATE_WOUNDED`(중상/요양) 상태로 전환되어 의막에서 회복된 후 5일간 적의 밀서 회유로부터도 면역된다.
3. **전령 경보 지연 (`Siege Warning Window`) 및 패배 후 황실 휴전 보호막 (`Post-Raid Truce Shield`, `F-40`)**:
   - 적 공격대는 간선 이동 시간 외에도 도착 후 `3 매크로 틱`의 진영 구축 시간을 거쳐야 하며, 만일 오프라인 장원이 한 번 돌파당하면 즉시 `truce_shield_until_tick = current_tick + 720`이 설정되어 연속 약탈(Griefing)을 차단한다.
4. **재접속 조보 / 지난 밤의 사기 브리핑 (`Reconnect Morning Court Gazette`, `F-38`)**:
   - 로그인 시 `last_seen_tick`부터 `current_tick_id`까지의 순 자원 수확량, 봉록, 완료 임무, 가신 성장/사념 이벤트, 전투 리플레이를 요약한 `MSG_OFFLINE_CHRONICLE_DIGEST` 패킷을 전송한다.

---

## 4. Godot 4 기술 스택, 결정론적 코어 및 네트워크 프로토콜 (`FH-04`, `F-42`, `F-43`)

### 4.1 3주기 결정론적 틱 클럭 (`SimClock`)

| 틱 주기 명칭 | 실시간 간격 (`sim_harness`는 `0ms`) | 인게임 시간 대응 | 실행되는 권위 서버 파이프라인 작업 |
|---|---|---|---|
| **`MICRO_TICK`** | **`1.0초`** (매 1틱) | 1 인게임 시간 | 클라이언트 명령 큐 드레인, `LOD 0` 장원 타일/작업/욕구 전진, 활성 국지전 라운드 진행 |
| **`MACRO_TICK`** | **`6.0초`** (매 6 마이크로 틱) | 1/4 인게임 일 (3시진) | `LOD 1` 장원 비율 적분 산출, 매크로 간선 부대/상단 이동, 공성전 웨이브 및 일기토, 지역 거래소 호가 매칭, 권위 **`state_crc32`** 해시 계산 |
| **`DAILY_SETTLEMENT_TICK`** | **`24.0초`** (매 24 마이크로 틱) | 1 인게임 일 (12시진; 30일=1계절) | 현 세금 징수, 구품 관직별 봉록 지급, 충성/야망 드리프트, 천명 감독관 이벤트 판정, **영속성 체크포인트 커밋** (`wal_commands.jsonl` 플러시 + 원자적 JSON 스냅샷 + `/usr/bin/sqlite3` `world_state.db` 동기화) |

### 4.2 SplitMix64 결정론적 난수 생성기 (`src/core/deterministic_rng.gd`)

```gdscript
class_name DeterministicRNG
extends RefCounted

# 순수 GDScript 64비트 정수 기반 무상태(Stateless) SplitMix64 해시 주사위
static func roll_range(world_seed: int, tick_id: int, entity_id: int, salt: int, min_val: int, max_val: int) -> int:
    if max_val <= min_val:
        return min_val
    var z: int = world_seed ^ (tick_id * 0x9E3779B97F4A7C15) ^ (entity_id * 0xBF58476D1CE4E5B9) ^ (salt * 0x94D049BB133111EB)
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    z = z ^ (z >> 31)
    var span: int = (max_val - min_val) + 1
    var pos_z: int = z & 0x7FFFFFFFFFFFFFFF
    return min_val + (pos_z % span)
```

### 4.3 플러그형 네트워크 트랜스포트 및 4채널 관심 영역 델타 압축 (`F-42`)

1. **추상 트랜스포트 인터페이스 (`INetworkTransport`)**:
   - `WebSocketTransport`: `WebSocketMultiplayerPeer` 기반 상용 크로스플랫폼 클라이언트/서버 통신.
   - `ENetTransport`: `ENetMultiplayerPeer` 기반 저지연 UDP 데스크톱/헤드리스 피어 통신.
   - `LoopbackMemoryTransport`: 단일 헤드리스 프로세스 내에서 1개의 권위 서버와 $N$개의 봇 클라이언트 세션을 인메모리 큐로 연결하여 초당 1,000틱 이상 고속 검증.
2. **4채널 관심 영역 구독 (4-Channel Interest Management)**:
   - `CHAN_GLOBAL_MACRO`: 전체 매크로 노드 소유권, 진행 중인 공성전 표시, 지역별 군량 시세 지수, 천하 연표 공지.
   - `CHAN_FACTION:<faction_id>`: 소속 세력 금고, 구품 관직 명부, 연합 공성 집결지, 외교 조약 현황.
   - `CHAN_NODE:<node_id>`: 현재 열람 중인 도시/현의 전체 지정가 호가창(`BID`/`ASK`), 인접 간선 행군 부대, 공성전 웨이브 상세.
   - `CHAN_MANOR:<manor_id>`: 본인 또는 관전 중인 장원의 `32×32` 그리드 변경분, 가신 위치/작업/욕구, 비축고 재고. (구독 시 서버에서 자동 `LOD 0` 승격)
3. **더티 비트 델타 패킷 규격 (`MSG_TICK_DELTA`)**:
   변동이 발생한 필드(`_dirty_mask != 0`)만 `"u_<collection>"`에 담아 전송하며 변경되지 않은 엔티티는 0바이트를 소모한다:
   ```json
   {
     "v": 1,
     "msg_type": "MSG_TICK_DELTA",
     "tick_id": 1440,
     "macro_tick_id": 240,
     "day_id": 60,
     "season": "AUTUMN",
     "state_crc32": 3491827412,
     "channels": {
       "CHAN_GLOBAL_MACRO": {
         "u_nodes": {"xuchang": {"fortification_hp": 8400, "grain_price_bp": 1350}},
         "u_armies": {"army_104": {"edge_id": "xuchang_luoyang", "progress_pm": 650, "morale_bp": 9100}},
         "d_armies": ["army_099"]
       },
       "CHAN_MANOR:manor_player_01": {
         "lod": 0,
         "u_stockpile": {"GRAIN": 45200, "IRON": 3100, "COIN": 12800},
         "u_pawns": {"pawn_02": {"x": 14, "y": 9, "job": "AGRICULTURE", "progress_pm": 420, "food_bp": 8800, "loyalty_bp": 9200}}
       }
     },
     "events": [
       {"ev_id": 8812, "type": "CARAVAN_ARRIVED", "node_id": "xuchang", "profit_coin": 1450}
     ]
   }
   ```

### 4.4 6단계 서버 권위 명령 검증 및 안티치트 파이프라인 (`F-43`)

클라이언트는 결코 상태를 직접 수정할 수 없으며 오직 선언형 의도 명령(`CommandEnvelope`)만 서버로 전송한다. 서버의 `CommandValidator`는 다음 6단계를 순차 검증한 뒤 `MSG_CMD_RECEIPT`를 반환한다:

| 단계 | 검증 게이트 명칭 | 거부 오류 코드 | 세부 검증 규칙 |
|---|---|---|---|
| **Stage 1** | **Wire Safety & Schema Guard** | `ERR_SCHEMA` | `bytes_to_var` 객체 역직렬화 원천 비활성화(원격 코드 실행 방지); 페이로드 `<= 4096 bytes`; 필수 키(`v`, `cmd_seq`, `client_tick`, `player_id`, `cmd_type`, `args`) 타입 확인 |
| **Stage 2** | **Session Auth & Ownership Binding** | `ERR_UNAUTHORIZED` | 트랜스포트 `peer_id`와 인증된 `session_player_id` 대조; 타 플레이어의 `player_id`나 `manor_id`, `pawn_id`를 조작하려는 시도 즉시 차단 |
| **Stage 3** | **Monotonic Sequence & Token-Bucket** | `ERR_RATE_LIMITED` | `cmd_seq > last_accepted_seq[player_id]` 단조 증가 검증(리플레이 공격 방지); 피어당 버스트 10 cmd/s, 지속 3 cmd/s 토큰 버킷 속도 제한 |
| **Stage 4** | **Political Role Permission Check** | `ERR_ROLE_PERMISSION` | `player.role_tier` 및 `court_rank` 권한 확인 (예: `CMD_SET_NODE_POLICY`는 해당 노드의 `GOVERNOR` 또는 `LORD`만 허용; `CMD_PROPOSE_OR_SIGN_TREATY`는 `LORD`만 허용) |
| **Stage 5** | **Resource Escrow, Sealed Persona & Domain Bounds** | `ERR_INSUFFICIENT_RESOURCE` / `ERR_INVALID_STATE` / `ERR_PLAINTEXT_JSON_FORBIDDEN` / `ERR_TOKEN_FORMAT` / `ERR_TOKEN_TAMPERED` / `ERR_CHALLENGE_UNKNOWN` / `ERR_CHALLENGE_OWNERSHIP` / `ERR_CHALLENGE_EXPIRED` / `ERR_CHALLENGE_REPLAYED` / `ERR_CHALLENGE_COOLDOWN` / `ERR_COERCION_REJECTED` / `ERR_TOKEN_DOMAIN` | 우선순위 값 `0..4`, 장원 좌표 `0..31` 범위 확인; 출진 대상 장수가 `STATE_IN_MANOR` 상태인지 확인; 비축고 군량/은전/병력 충분 여부 및 그래프 간선 연결성 확인; **Track B 2단계 핸드셰이크 (`CMD_REQUEST_PERSONA_CHALLENGE` → `MSG_PERSONA_CHALLENGE` → `CMD_CREATE_CHARACTER` Stage 5a–5e)**: ① `Stage 5a`: 평문 JSON(`AI_PERSONA_EXPORT_V1`, `{...}`) 즉시 거부(`ERR_PLAINTEXT_JSON_FORBIDDEN`), ② `Stage 5b`: `persona_import_challenges` 소유권·`CHALLENGE_TTL_TICKS = 900`·단회 사용(`ISSUED → CONSUMED`)·쿨다운/비율 제한(`15분 3회`, `24시간 5회`) 검증, ③ `Stage 5c`: 세션 `HMAC-SHA256` Fisher-Yates 코드북 `K^-1` + **Fletcher-31** 무결성 검증(`ERR_TOKEN_TAMPERED`, `max_attempts = 3` 초과 시 `REVOKED_TAMPER` + 지수 쿨다운 `300/900/3600`), ④ `Stage 5d`: `v[15]` 강압 텔레메트리(`R0_CLEAN`, `R1_MILD_STEERING`→`FUSION_INTERVIEW` `2000 bp`, `R2_STAT_COERCION`/`R3_PROMPT_INJECTION`→`ERR_COERCION_REJECTED` 및 `R3` `1800` 틱 쿨다운) + 제로 트러스트 통계 이상치(`H1` 평탄 ceiling, `H2` 극단 이분화 소프트 압축, `H3` 5 빛`+1`/5 그림자`-1` 보정, `H4` 무상자원 0 및 서사 살균), ⑤ `Stage 5e`: `TOTAL_STAT_BUDGET = 320`, `[35, 85]`, `PASSION_BUDGET = 3` 원자적 정규화 및 커밋 |
| **Stage 6** | **Tick Queue Commit & Audit Log** | `OK` (`ACCEPTED`) | `exec_tick_id = current_tick_id + 1` 할당, `saves/wal_commands.jsonl` 및 SQLite `command_audit_log` 테이블에 기록 후 `MSG_CMD_RECEIPT` 전송 |

---

## 5. 하이브리드 JSONL WAL + `/usr/bin/sqlite3` 관계형 영속성 엔진 (`F-44`)

외부 C++ GDExtension 컴파일 의존성 없이 100% 크래시 복구력과 SQL 관계형 감사(Forensic Audit) 능력을 동시에 확보하기 위해 2티어 영속성 엔진을 구축한다:

1. **Tier 1 — 실시간 Write-Ahead Log (`saves/wal_commands.jsonl`) 및 이중 버퍼 원자적 스냅샷 (`saves/world_snapshot.json`)**:
   - 승인된 모든 플레이어 명령과 스토리텔러 시드 이벤트는 즉시 `wal_commands.jsonl`에 한 줄씩 추가(`flush()`)된다:
     `{"tick_id":1441,"cmd_seq":42,"player_id":"p_01","cmd_type":"CMD_SET_WORK_PRIORITY","payload":{"pawn_id":"pawn_02","domain":"AGRICULTURE","priority":1},"crc32":29182311}`
   - 매 `DAILY_SETTLEMENT_TICK`(24틱)마다 전체 월드 상태를 `saves/world_snapshot.tmp.json`에 기록 후 `saves/world_snapshot.json`으로 원자적 이름 변경(Atomic Rename)한다. 서버 재시작 시 스냅샷 로드 후 이후 틱의 WAL 레코드를 결정론적으로 리플레이하여 단 1틱의 데이터 손실도 허용하지 않는다.
2. **Tier 2 — 정규 SQLite 10테이블 관계형 체크포인트 (`saves/world_state.db` via `/usr/bin/sqlite3`)**:
   - 매 `DAILY_SETTLEMENT_TICK` 및 서버 종료 시 트랜잭션 SQL 배치를 생성하여 `/usr/bin/sqlite3 saves/world_state.db`에 동기화한다.
   - **정규 10대 테이블 구성 (`data/schemas/world_state_schema.sql`)**:
     1. `world_meta`: 월드 시드, 현재 틱/일차, 계절(`SPRING/SUMMER/AUTUMN/WINTER`), 스토리텔러 ID, `state_crc32`.
     2. `factions`: 세력 ID, 세력명, 군주 플레이어 ID, 수도 노드 ID, 세력 금고(`treasury_grain`, `treasury_coin`), 칙서, 명망.
     3. `macro_nodes`: 노드 ID, 주(`province`), 등급(`node_tier`), 소유 세력, 태수 ID, 성벽 내구도, 치안/도적 압력(`0..10000 bp`), 세율(표준 태수 `500..2500 bp`, 비상 스키마 상한 `500..5000 bp`), 지역 시세.
     4. `persona_import_challenges`: Track B 일회성 챌린지 및 안티리플레이 원장(`challenge_id`, `account_id`, `bound_player_id`, `nonce` [`UNIQUE`], `session_salt`, `cipher_key_hint`, `issued_at_tick`, `ttl_expires_tick`, `consumed_at_tick`, `status` [`ISSUED`, `CONSUMED`, `EXPIRED`, `REVOKED_TAMPER`], `attempt_count`, `max_attempts`, `cooldown_until_tick`, `last_coercion_flag`, `last_reject_reason`).
     5. `players`: 플레이어 ID, 생성 경로(`creation_mode`: `INTERVIEW_ONLY`/`FUSION_INTERVIEW`/`AI_DIRECT_WITH_CONFIRM`), 봉인 해독 열전 JSON(`persona_profile_json`), 챌린지 외래키(`persona_challenge_id` [`UNIQUE`, 다중 `NULL` 허용]), 감찰 상태(`import_audit_status`: `NONE`/`VERIFIED_CLEAN`/`DOWNGRADED_ANOMALY`/`REJECTED_COERCION`/`FALLBACK_INTERVIEW`), 강압 플래그(`coercion_flag`: `R0_CLEAN`/`R1_MILD_STEERING`/`R2_STAT_COERCION`/`R3_PROMPT_INJECTION`), 신분 계층(`FREE_OFFICER`, `FACTION_OFFICER`, `GOVERNOR`, `LORD`), 소속 세력, 구품 관직(`RANK_9`..`RANK_1` 등), 전공(`war_merit`), 정박 노드, 장원 ID, 온라인 여부, 휴전 보호막 종료 틱.
     6. `manors`: 장원 ID, 소유자 ID, 호스트 노드 ID, 현재 LOD(`0` 또는 `1`), 자원 재고(`grain_stock`, `coin_stock`, `iron_stock`, `wood_stock`, `weapon_stock` 등 모두 `>= 0`), 비상 지하창고 보호 비율(`4000..6500 bp`), 성책 내구도, 상시 교전 수칙 JSON, 구역 그리드 JSON.
     7. `pawns_officers`: 장수/가신 ID, 소유 플레이어 ID, 장원 ID, 주인공 여부, 현재 상태(`IN_MANOR`, `ON_EXPEDITION`, `WOUNDED`, `CAPTURED`), 5대 능력치(`1..120`), 5대 욕구(`0..10000 bp`), 기질 특성 JSON, 업무 우선순위 JSON.
     8. `armies_caravans`: 부대/상단 엔티티 ID, 소유자 ID, 세력 ID, 유닛 유형(`ARMY`, `CARAVAN`, `RAID_PARTY`, `COALITION_FORCE`), 현재 노드/간선 ID, 간선 진행도(`0..1000 pm`), 병력 수, 사기(`0..10000 bp`), 휴대 군량/은전, 화물 JSON, 교전 수칙 JSON.
     9. `market_orders`: 주문 ID, 노드 ID, 플레이어 ID, 6대 품목(`GRAIN`, `IRON`, `WOOD`, `HORSES`, `WEAPONS`, `HERBS_WINE`), 매수/매도(`BID`, `ASK`), 지정가(`price_bp > 0`), 주문 수량, 체결 수량, 상태(`OPEN`, `FILLED`, `CANCELLED`).
     10. `command_audit_log`: 단조 증가 시퀀스(`seq_id`), 틱 ID, 플레이어 ID, 명령 유형, 처리 상태(`ACCEPTED`, `REJECTED`), 거부 사유, 페이로드 JSON.

---

## 6. 단계별 개발 및 검증 마일스톤 로드맵 (`M0` ~ `M6`)

| 마일스톤 | 핵심 목표 및 대상 모듈 | 포함 기능 ID (`52개 전수 매핑`) | 완료 검증 게이트 명령어 |
|---|---|---|---|
| **M0** | **Phase 0: AI 에이전트 하네스 및 기획/아키텍처 청사진 확립 (사용자 확인 게이트)** | `FH-00` | `python3 scripts/harness/verify_blueprint.py && /usr/bin/sqlite3 :memory: < data/schemas/world_state_schema.sql` |
| **M1** | **Godot 4 툴체인 부트스트랩, 결정론적 코어 엔진 및 Stage 1~2 하네스 구축** | `FH-01`, `FH-02`, `FH-03`, `FH-04` | `bash scripts/setup_godot.sh && bash scripts/harness/check_syntax.sh && bash scripts/harness/run_tests.sh` |
| **M2** | **Layer 1: 림월드 마이크로 장원(`32×32`), 자율 가신 AI, 8대 자원 경제 및 Stage 3 시뮬레이션 하네스** | `FH-05`, `F-01`, `F-02`, `F-03`, `F-04`, `F-05`, `F-06`, `F-07`, `F-08`, `F-09`, `F-10`, `F-11`, `F-12`, `F-13`, `F-14`, `F-15`, `F-16`, `F-17`, `F-20`, `F-40` | `bash scripts/harness/run_sim.sh --seed=18401 --ticks=10000 --verify-determinism --verify-offline-equivalence` |
| **M3** | **Layer 2: 삼국지 천하 전략도 그래프 $G=(V,E)$, 상시 교전 수칙, 랜체스터 자동 전투/일기토 및 천명 스토리텔러** | `F-18`, `F-19`, `F-21`, `F-22`, `F-23`, `F-24`, `F-26`, `F-35`, `F-41` | `bash scripts/harness/run_tests.sh --suite=macro_combat_storyteller` |
| **M4** | **장수 ↔ 군주 이중 정치 루프, 구품 관직, 연합 공성전, 세작/회유/거병 및 사계절 외교 조약** | `F-25`, `F-27`, `F-28`, `F-29`, `F-30`, `F-31`, `F-32`, `F-33`, `F-34`, `F-36` | `bash scripts/harness/run_tests.sh --suite=faction_politics_siege` |
| **M5** | **권위 서버 네트워크 프로토콜, 6단계 보안 파이프라인, 하이브리드 WAL+SQLite 영속성 및 조보/서신함** | `F-38`, `F-39`, `F-42`, `F-43`, `F-44` | `bash scripts/harness/run_tests.sh --suite=net_security_persistence` |
| **M6** | **프로그래밍 방식 클라이언트 UI 뷰, 시즌 천하통일/가문 계승 및 Stage 4 멀티클라이언트 공유 월드 E2E 검증** | `FH-06`, `F-37`, `F-45` | `python3 scripts/harness/run_net_smoke.py && python3 tools/harness/audit_verifier.py --db saves/world_state.db` |
