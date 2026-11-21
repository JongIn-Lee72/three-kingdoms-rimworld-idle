-- =============================================================================
-- File: data/schemas/world_state_schema.sql
-- Project: Three Kingdoms x RimWorld Shared-World Idle Game in Godot 4
-- Milestone: M0 (FH-00) / M5 (F-44)
-- Description: Canonical SQLite Relational Schema for saves/world_state.db
--              Defines 10 authoritative tables with strict NOT NULL, CHECK
--              domain invariants (int64 basis-point 0..10000 bounds, non-negative
--              stockpiles, valid political tiers, valid LOD 0/1), and indexes.
-- =============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- -----------------------------------------------------------------------------
-- 1. world_meta: Global authoritative server clock, seed, season & CRC32 state
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS world_meta (
    world_id TEXT PRIMARY KEY CHECK (length(world_id) > 0),
    world_seed INTEGER NOT NULL,
    current_tick_id INTEGER NOT NULL CHECK (current_tick_id >= 0),
    current_day_id INTEGER NOT NULL CHECK (current_day_id >= 0),
    season TEXT NOT NULL CHECK (season IN ('SPRING', 'SUMMER', 'AUTUMN', 'WINTER')),
    storyteller_id TEXT NOT NULL CHECK (storyteller_id IN ('SIMA_QIAN', 'DONG_ZHUO', 'WEN_JING')),
    state_crc32 INTEGER NOT NULL,
    updated_at_utc TEXT NOT NULL CHECK (length(updated_at_utc) > 0)
);

-- -----------------------------------------------------------------------------
-- 2. factions: Shared-world warlord factions (AI historical or Player-founded)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS factions (
    faction_id TEXT PRIMARY KEY CHECK (length(faction_id) > 0),
    name TEXT NOT NULL CHECK (length(name) > 0),
    lord_player_id TEXT NOT NULL CHECK (length(lord_player_id) > 0),
    capital_node_id TEXT NOT NULL CHECK (length(capital_node_id) > 0),
    royal_rank TEXT NOT NULL DEFAULT 'PREFECT' CHECK (royal_rank IN ('PREFECT', 'GOVERNOR_GENERAL', 'DUKE', 'KING', 'EMPEROR')),
    treasury_grain INTEGER NOT NULL DEFAULT 0 CHECK (treasury_grain >= 0),
    treasury_coin INTEGER NOT NULL DEFAULT 0 CHECK (treasury_coin >= 0),
    imperial_edicts INTEGER NOT NULL DEFAULT 0 CHECK (imperial_edicts >= 0),
    prestige INTEGER NOT NULL DEFAULT 0 CHECK (prestige >= 0),
    oathbreaker_until_tick INTEGER NOT NULL DEFAULT 0 CHECK (oathbreaker_until_tick >= 0)
);

-- -----------------------------------------------------------------------------
-- 3. macro_nodes: Layer 2 Three Kingdoms Strategic Graph Nodes (V)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS macro_nodes (
    node_id TEXT PRIMARY KEY CHECK (length(node_id) > 0),
    name TEXT NOT NULL CHECK (length(name) > 0),
    province TEXT NOT NULL CHECK (length(province) > 0),
    node_tier TEXT NOT NULL CHECK (node_tier IN ('CAPITAL_METROPOLIS', 'COMMANDERY_CITY', 'COUNTY_TOWN', 'STRATEGIC_PASS')),
    owner_faction_id TEXT NOT NULL,
    governor_player_id TEXT,
    fortification_hp INTEGER NOT NULL CHECK (fortification_hp >= 0 AND fortification_hp <= max_fortification_hp),
    max_fortification_hp INTEGER NOT NULL DEFAULT 10000 CHECK (max_fortification_hp > 0),
    public_order_bp INTEGER NOT NULL CHECK (public_order_bp BETWEEN 0 AND 10000),
    bandit_pressure_bp INTEGER NOT NULL CHECK (bandit_pressure_bp BETWEEN 0 AND 10000),
    tax_rate_bp INTEGER NOT NULL CHECK (tax_rate_bp BETWEEN 500 AND 5000),
    treasury_grain INTEGER NOT NULL DEFAULT 0 CHECK (treasury_grain >= 0),
    treasury_coin INTEGER NOT NULL DEFAULT 0 CHECK (treasury_coin >= 0),
    grain_price_bp INTEGER NOT NULL CHECK (grain_price_bp BETWEEN 100 AND 100000),
    iron_price_bp INTEGER NOT NULL CHECK (iron_price_bp BETWEEN 100 AND 100000),
    FOREIGN KEY (owner_faction_id) REFERENCES factions(faction_id)
);

-- -----------------------------------------------------------------------------
-- 4. persona_import_challenges: Track B One-Time Sealed-Token Challenge & Anti-Replay Ledger
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS persona_import_challenges (
    challenge_id TEXT PRIMARY KEY CHECK (length(challenge_id) > 0),
    account_id TEXT NOT NULL CHECK (length(account_id) > 0),
    bound_player_id TEXT,
    nonce TEXT NOT NULL UNIQUE CHECK (length(nonce) >= 6),
    session_salt TEXT NOT NULL CHECK (length(session_salt) >= 4),
    cipher_key_hint TEXT NOT NULL CHECK (length(cipher_key_hint) >= 4),
    issued_at_tick INTEGER NOT NULL CHECK (issued_at_tick >= 0),
    ttl_expires_tick INTEGER NOT NULL CHECK (ttl_expires_tick > issued_at_tick),
    consumed_at_tick INTEGER CHECK (consumed_at_tick IS NULL OR consumed_at_tick >= issued_at_tick),
    status TEXT NOT NULL DEFAULT 'ISSUED' CHECK (
        status IN ('ISSUED', 'CONSUMED', 'EXPIRED', 'REVOKED_TAMPER')
    ),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    max_attempts INTEGER NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 10),
    cooldown_until_tick INTEGER NOT NULL DEFAULT 0 CHECK (cooldown_until_tick >= 0),
    last_coercion_flag TEXT NOT NULL DEFAULT 'R0_CLEAN' CHECK (
        last_coercion_flag IN ('R0_CLEAN', 'R1_MILD_STEERING', 'R2_STAT_COERCION', 'R3_PROMPT_INJECTION')
    ),
    last_reject_reason TEXT,
    CHECK (attempt_count <= max_attempts),
    CHECK ((status = 'CONSUMED' AND consumed_at_tick IS NOT NULL) OR (status != 'CONSUMED' AND consumed_at_tick IS NULL))
);

-- -----------------------------------------------------------------------------
-- 5. players: Participating human/bot warlord & officer accounts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS players (
    player_id TEXT PRIMARY KEY CHECK (length(player_id) > 0),
    display_name TEXT NOT NULL CHECK (length(display_name) > 0),
    auth_token_hash TEXT NOT NULL CHECK (length(auth_token_hash) > 0),
    origin_archetype TEXT NOT NULL DEFAULT 'ORIGIN_CHIVALROUS_HERO' CHECK (
        origin_archetype IN (
            'ORIGIN_FALLEN_ROYAL',
            'ORIGIN_FRONTIER_OFFICER',
            'ORIGIN_PURE_SCHOLAR',
            'ORIGIN_CHIVALROUS_HERO',
            'ORIGIN_AGRARIAN_GENTRY'
        )
    ),
    creation_mode TEXT NOT NULL DEFAULT 'INTERVIEW_ONLY' CHECK (
        creation_mode IN ('INTERVIEW_ONLY', 'FUSION_INTERVIEW', 'AI_DIRECT_WITH_CONFIRM')
    ),
    persona_profile_json TEXT NOT NULL DEFAULT '{}' CHECK (length(persona_profile_json) >= 2),
    persona_challenge_id TEXT UNIQUE,
    import_audit_status TEXT NOT NULL DEFAULT 'NONE' CHECK (
        import_audit_status IN (
            'NONE', 'VERIFIED_CLEAN', 'DOWNGRADED_ANOMALY', 'REJECTED_COERCION', 'FALLBACK_INTERVIEW'
        )
    ),
    coercion_flag TEXT NOT NULL DEFAULT 'R0_CLEAN' CHECK (
        coercion_flag IN ('R0_CLEAN', 'R1_MILD_STEERING', 'R2_STAT_COERCION', 'R3_PROMPT_INJECTION')
    ),
    role_tier TEXT NOT NULL CHECK (role_tier IN ('FREE_OFFICER', 'FACTION_OFFICER', 'GOVERNOR', 'LORD')),
    faction_id TEXT,
    court_rank TEXT NOT NULL CHECK (
        court_rank IN (
            'NONE',
            'RANK_9', 'RANK_8', 'RANK_7', 'RANK_6', 'RANK_5',
            'RANK_4', 'RANK_3', 'RANK_2', 'RANK_1', 'SOVEREIGN'
        )
    ),
    war_merit INTEGER NOT NULL DEFAULT 0 CHECK (war_merit >= 0),
    host_node_id TEXT NOT NULL,
    manor_id TEXT NOT NULL UNIQUE,
    is_online INTEGER NOT NULL DEFAULT 0 CHECK (is_online IN (0, 1)),
    last_seen_tick INTEGER NOT NULL DEFAULT 0 CHECK (last_seen_tick >= 0),
    truce_shield_until_tick INTEGER NOT NULL DEFAULT 0 CHECK (truce_shield_until_tick >= 0),
    adaptation_factor_bp INTEGER NOT NULL DEFAULT 1000 CHECK (adaptation_factor_bp BETWEEN 400 AND 1500),
    FOREIGN KEY (host_node_id) REFERENCES macro_nodes(node_id),
    FOREIGN KEY (persona_challenge_id) REFERENCES persona_import_challenges(challenge_id)
);

-- -----------------------------------------------------------------------------
-- 6. manors: Layer 1 RimWorld 32x32 Personal Manor / Homestead State
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS manors (
    manor_id TEXT PRIMARY KEY CHECK (length(manor_id) > 0),
    player_id TEXT NOT NULL UNIQUE,
    host_node_id TEXT NOT NULL,
    current_lod INTEGER NOT NULL DEFAULT 1 CHECK (current_lod IN (0, 1)),
    grain_stock INTEGER NOT NULL DEFAULT 0 CHECK (grain_stock >= 0),
    coin_stock INTEGER NOT NULL DEFAULT 0 CHECK (coin_stock >= 0),
    iron_stock INTEGER NOT NULL DEFAULT 0 CHECK (iron_stock >= 0),
    wood_stock INTEGER NOT NULL DEFAULT 0 CHECK (wood_stock >= 0),
    horse_stock INTEGER NOT NULL DEFAULT 0 CHECK (horse_stock >= 0),
    herbs_wine_stock INTEGER NOT NULL DEFAULT 0 CHECK (herbs_wine_stock >= 0),
    weapon_stock INTEGER NOT NULL DEFAULT 0 CHECK (weapon_stock >= 0),
    household_troops INTEGER NOT NULL DEFAULT 0 CHECK (household_troops BETWEEN 0 AND 3000),
    vault_protected_bp INTEGER NOT NULL DEFAULT 4000 CHECK (vault_protected_bp BETWEEN 4000 AND 6500),
    wall_hp INTEGER NOT NULL DEFAULT 2000 CHECK (wall_hp >= 0),
    standing_doctrine_json TEXT NOT NULL CHECK (length(standing_doctrine_json) >= 2),
    grid_zones_json TEXT NOT NULL CHECK (length(grid_zones_json) >= 2),
    FOREIGN KEY (player_id) REFERENCES players(player_id),
    FOREIGN KEY (host_node_id) REFERENCES macro_nodes(node_id)
);

-- -----------------------------------------------------------------------------
-- 7. pawns_officers: Autonomous Main Characters & Sworn Retainers (5 Stats/Needs)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pawns_officers (
    pawn_id TEXT PRIMARY KEY CHECK (length(pawn_id) > 0),
    owner_player_id TEXT NOT NULL,
    manor_id TEXT NOT NULL,
    name TEXT NOT NULL CHECK (length(name) > 0),
    is_avatar INTEGER NOT NULL DEFAULT 0 CHECK (is_avatar IN (0, 1)),
    state TEXT NOT NULL CHECK (state IN ('IN_MANOR', 'ON_EXPEDITION', 'WOUNDED', 'CAPTURED')),
    health_state TEXT NOT NULL DEFAULT 'HEALTHY' CHECK (health_state IN ('HEALTHY', 'LIGHT_WOUND', 'SEVERE_WOUND', 'SCARRED')),
    leadership INTEGER NOT NULL CHECK (leadership BETWEEN 1 AND 120),
    martial INTEGER NOT NULL CHECK (martial BETWEEN 1 AND 120),
    intelligence INTEGER NOT NULL CHECK (intelligence BETWEEN 1 AND 120),
    politics INTEGER NOT NULL CHECK (politics BETWEEN 1 AND 120),
    charisma INTEGER NOT NULL CHECK (charisma BETWEEN 1 AND 120),
    food_need_bp INTEGER NOT NULL CHECK (food_need_bp BETWEEN 0 AND 10000),
    rest_need_bp INTEGER NOT NULL CHECK (rest_need_bp BETWEEN 0 AND 10000),
    morale_bp INTEGER NOT NULL CHECK (morale_bp BETWEEN 0 AND 10000),
    loyalty_bp INTEGER NOT NULL CHECK (loyalty_bp BETWEEN 0 AND 10000),
    ambition_bp INTEGER NOT NULL CHECK (ambition_bp BETWEEN 0 AND 10000),
    mood INTEGER NOT NULL DEFAULT 50 CHECK (mood BETWEEN 0 AND 100),
    mental_state TEXT NOT NULL DEFAULT 'NORMAL' CHECK (
        mental_state IN (
            'NORMAL',
            'BREAK_MINOR_BINGE', 'BREAK_MINOR_SECLUSION',
            'BREAK_MAJOR_CHARGE', 'BREAK_MAJOR_EMBEZZLE',
            'BREAK_EXTREME_DESERTION', 'BREAK_EXTREME_MUTINY',
            'CATHARSIS',
            'AWAKENED_STRATAGEM', 'AWAKENED_VALOR', 'AWAKENED_FORGING', 'AWAKENED_HEARTS'
        )
    ),
    traits_json TEXT NOT NULL CHECK (length(traits_json) >= 2),
    work_priorities_json TEXT NOT NULL CHECK (length(work_priorities_json) >= 2),
    daily_schedule_json TEXT NOT NULL DEFAULT '[]' CHECK (length(daily_schedule_json) >= 2),
    FOREIGN KEY (owner_player_id) REFERENCES players(player_id),
    FOREIGN KEY (manor_id) REFERENCES manors(manor_id)
);

-- -----------------------------------------------------------------------------
-- 8. armies_caravans: Layer 2 Marching Armies, Supply Caravans & Coalition Forces
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS armies_caravans (
    entity_id TEXT PRIMARY KEY CHECK (length(entity_id) > 0),
    owner_player_id TEXT NOT NULL,
    faction_id TEXT,
    unit_type TEXT NOT NULL CHECK (unit_type IN ('ARMY', 'CARAVAN', 'RAID_PARTY', 'COALITION_FORCE')),
    current_node_id TEXT,
    current_edge_id TEXT,
    edge_progress_pm INTEGER NOT NULL DEFAULT 0 CHECK (edge_progress_pm BETWEEN 0 AND 1000),
    troop_count INTEGER NOT NULL CHECK (troop_count >= 0),
    morale_bp INTEGER NOT NULL CHECK (morale_bp BETWEEN 0 AND 10000),
    carried_grain INTEGER NOT NULL DEFAULT 0 CHECK (carried_grain >= 0),
    carried_coin INTEGER NOT NULL DEFAULT 0 CHECK (carried_coin >= 0),
    cargo_json TEXT NOT NULL CHECK (length(cargo_json) >= 2),
    doctrine_json TEXT NOT NULL CHECK (length(doctrine_json) >= 2),
    FOREIGN KEY (owner_player_id) REFERENCES players(player_id)
);

-- -----------------------------------------------------------------------------
-- 9. market_orders: Regional Limit Order Book (BID/ASK) for Strategic Commodities
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS market_orders (
    order_id TEXT PRIMARY KEY CHECK (length(order_id) > 0),
    node_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    commodity TEXT NOT NULL CHECK (commodity IN ('GRAIN', 'IRON', 'WOOD', 'HORSES', 'WEAPONS', 'HERBS_WINE')),
    side TEXT NOT NULL CHECK (side IN ('BID', 'ASK')),
    price_bp INTEGER NOT NULL CHECK (price_bp BETWEEN 100 AND 100000),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    filled_quantity INTEGER NOT NULL DEFAULT 0 CHECK (filled_quantity >= 0 AND filled_quantity <= quantity),
    created_tick INTEGER NOT NULL CHECK (created_tick >= 0),
    status TEXT NOT NULL CHECK (status IN ('OPEN', 'FILLED', 'CANCELLED')),
    FOREIGN KEY (node_id) REFERENCES macro_nodes(node_id),
    FOREIGN KEY (player_id) REFERENCES players(player_id)
);

-- -----------------------------------------------------------------------------
-- 10. command_audit_log: 6-Stage CommandValidator Forensic Security Audit Trail
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS command_audit_log (
    seq_id INTEGER PRIMARY KEY AUTOINCREMENT,
    tick_id INTEGER NOT NULL CHECK (tick_id >= 0),
    player_id TEXT NOT NULL CHECK (length(player_id) > 0),
    cmd_type TEXT NOT NULL CHECK (length(cmd_type) > 0),
    status TEXT NOT NULL CHECK (status IN ('ACCEPTED', 'REJECTED')),
    reject_reason TEXT,
    payload_json TEXT NOT NULL CHECK (length(payload_json) >= 2)
);

-- -----------------------------------------------------------------------------
-- Performance & Forensic Audit Indexes
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_macro_nodes_owner_faction ON macro_nodes(owner_faction_id);
CREATE INDEX IF NOT EXISTS idx_players_faction_role ON players(faction_id, role_tier);
CREATE INDEX IF NOT EXISTS idx_players_host_node ON players(host_node_id);
CREATE INDEX IF NOT EXISTS idx_manors_host_node_lod ON manors(host_node_id, current_lod);
CREATE INDEX IF NOT EXISTS idx_pawns_manor_state ON pawns_officers(manor_id, state);
CREATE INDEX IF NOT EXISTS idx_pawns_owner_loyalty ON pawns_officers(owner_player_id, loyalty_bp);
CREATE INDEX IF NOT EXISTS idx_armies_node_edge ON armies_caravans(current_node_id, current_edge_id);
CREATE INDEX IF NOT EXISTS idx_market_orders_matching ON market_orders(node_id, commodity, status, side, price_bp);
CREATE INDEX IF NOT EXISTS idx_command_audit_tick_status ON command_audit_log(tick_id, status);
CREATE INDEX IF NOT EXISTS idx_players_import_audit ON players(import_audit_status, coercion_flag);
CREATE INDEX IF NOT EXISTS idx_challenges_account_status ON persona_import_challenges(account_id, status, ttl_expires_tick);
CREATE UNIQUE INDEX IF NOT EXISTS idx_challenges_nonce ON persona_import_challenges(nonce);
CREATE INDEX IF NOT EXISTS idx_challenges_cooldown ON persona_import_challenges(account_id, cooldown_until_tick);
