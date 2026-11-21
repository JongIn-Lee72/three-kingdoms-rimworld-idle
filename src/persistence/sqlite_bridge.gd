class_name SQLiteBridge
extends RefCounted

const SQLITE_BIN: String = "/usr/bin/sqlite3"
const DEFAULT_SCHEMA_PATH: String = "res://data/schemas/world_state_schema.sql"

const CANONICAL_TABLES: Array[String] = [
	"world_meta",
	"factions",
	"macro_nodes",
	"persona_import_challenges",
	"players",
	"manors",
	"pawns_officers",
	"armies_caravans",
	"market_orders",
	"command_audit_log"
]

const VALID_SEASONS: Array[String] = ["SPRING", "SUMMER", "AUTUMN", "WINTER"]
const VALID_STORYTELLERS: Array[String] = ["SIMA_QIAN", "DONG_ZHUO", "WEN_JING"]
const VALID_ROYAL_RANKS: Array[String] = ["PREFECT", "GOVERNOR_GENERAL", "DUKE", "KING", "EMPEROR"]
const VALID_NODE_TIERS: Array[String] = ["CAPITAL_METROPOLIS", "COMMANDERY_CITY", "COUNTY_TOWN", "STRATEGIC_PASS"]
const VALID_CHALLENGE_STATUSES: Array[String] = ["ISSUED", "CONSUMED", "EXPIRED", "REVOKED_TAMPER"]
const VALID_COERCION_FLAGS: Array[String] = ["R0_CLEAN", "R1_MILD_STEERING", "R2_STAT_COERCION", "R3_PROMPT_INJECTION"]
const VALID_ORIGIN_ARCHETYPES: Array[String] = [
	"ORIGIN_FALLEN_ROYAL",
	"ORIGIN_FRONTIER_OFFICER",
	"ORIGIN_PURE_SCHOLAR",
	"ORIGIN_CHIVALROUS_HERO",
	"ORIGIN_AGRARIAN_GENTRY"
]
const VALID_CREATION_MODES: Array[String] = ["INTERVIEW_ONLY", "FUSION_INTERVIEW", "AI_DIRECT_WITH_CONFIRM"]
const VALID_IMPORT_STATUSES: Array[String] = [
	"NONE", "VERIFIED_CLEAN", "DOWNGRADED_ANOMALY", "REJECTED_COERCION", "FALLBACK_INTERVIEW"
]
const VALID_ROLE_TIERS: Array[String] = ["FREE_OFFICER", "FACTION_OFFICER", "GOVERNOR", "LORD"]
const VALID_COURT_RANKS: Array[String] = [
	"NONE",
	"RANK_9", "RANK_8", "RANK_7", "RANK_6", "RANK_5",
	"RANK_4", "RANK_3", "RANK_2", "RANK_1", "SOVEREIGN"
]
const VALID_PAWN_STATES: Array[String] = ["IN_MANOR", "ON_EXPEDITION", "WOUNDED", "CAPTURED"]
const VALID_HEALTH_STATES: Array[String] = ["HEALTHY", "LIGHT_WOUND", "SEVERE_WOUND", "SCARRED"]
const VALID_MENTAL_STATES: Array[String] = [
	"NORMAL",
	"BREAK_MINOR_BINGE", "BREAK_MINOR_SECLUSION",
	"BREAK_MAJOR_CHARGE", "BREAK_MAJOR_EMBEZZLE",
	"BREAK_EXTREME_DESERTION", "BREAK_EXTREME_MUTINY",
	"CATHARSIS",
	"AWAKENED_STRATAGEM", "AWAKENED_VALOR", "AWAKENED_FORGING", "AWAKENED_HEARTS"
]
const VALID_ARMY_UNIT_TYPES: Array[String] = ["ARMY", "CARAVAN", "RAID_PARTY", "COALITION_FORCE"]
const VALID_COMMODITIES: Array[String] = ["GRAIN", "IRON", "WOOD", "HORSES", "WEAPONS", "HERBS_WINE"]
const VALID_ORDER_SIDES: Array[String] = ["BID", "ASK"]
const VALID_ORDER_STATUSES: Array[String] = ["OPEN", "FILLED", "CANCELLED"]
const VALID_AUDIT_STATUSES: Array[String] = ["ACCEPTED", "REJECTED"]


static func _to_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	if v is bool:
		var bv: bool = v
		return int(bv)
	return fallback


static func _to_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	if v is int:
		var iv: int = v
		return iv != 0
	return fallback


static func resolve_path(path: String) -> String:
	return WALLogger.resolve_path(path)


static func sql_quote(text: String) -> String:
	# Strip NUL bytes cleanly and escape single quotes for SQLite string literals.
	var nul_char: String = String.chr(0)
	var sanitized: String = text.replace(nul_char, "").replace("'", "''")
	return "'" + sanitized + "'"


static func sql_nullable_text(v: Variant) -> String:
	if v == null:
		return "NULL"
	var s: String = str(v)
	if s.is_empty():
		return "NULL"
	return sql_quote(s)


static func sql_nullable_int(v: Variant) -> String:
	if v == null:
		return "NULL"
	if v is int or v is float or v is bool:
		return str(_to_int(v, 0))
	return "NULL"


static func _json_text(v: Variant, fallback_json: String) -> String:
	if v is String:
		var s: String = str(v)
		if s.length() >= 2:
			return s
		return fallback_json
	if v is Dictionary or v is Array:
		var serialized: String = StateHasher.canonical_json(v)
		if serialized.length() >= 2:
			return serialized
	return fallback_json


static func _map_royal_rank(raw_rank: String) -> String:
	if VALID_ROYAL_RANKS.has(raw_rank):
		return raw_rank
	match raw_rank:
		"GOVERNOR_INSPECTOR":
			return "PREFECT"
		"PROVINCE_GOVERNOR":
			return "GOVERNOR_GENERAL"
		_:
			return "PREFECT"


static func _map_node_tier(raw_tier: String) -> String:
	if VALID_NODE_TIERS.has(raw_tier):
		return raw_tier
	match raw_tier:
		"CAPITAL":
			return "CAPITAL_METROPOLIS"
		"CITY":
			return "COMMANDERY_CITY"
		"COUNTY":
			return "COUNTY_TOWN"
		"PASS":
			return "STRATEGIC_PASS"
		_:
			return "COUNTY_TOWN"


static func _map_army_unit_type(raw_type: String) -> String:
	if VALID_ARMY_UNIT_TYPES.has(raw_type):
		return raw_type
	return "ARMY"


static func _map_commodity(raw_c: String) -> String:
	var up: String = raw_c.to_upper()
	if VALID_COMMODITIES.has(up):
		return up
	if up == "HORSE":
		return "HORSES"
	if up == "WEAPON":
		return "WEAPONS"
	return "GRAIN"


static func _exec_sql_file(db_path: String, sql_file_path: String) -> Dictionary:
	var output: Array = []
	var args: PackedStringArray = PackedStringArray(["-bail", db_path, ".read " + sql_file_path])
	var exit_code: int = OS.execute(SQLITE_BIN, args, output, true)
	var joined_lines: PackedStringArray = PackedStringArray()
	for item: Variant in output:
		var _ok: bool = joined_lines.append(str(item))
	var out_str: String = "\n".join(joined_lines).strip_edges()
	return {
		"ok": exit_code == 0,
		"exit_code": exit_code,
		"output": out_str
	}


static func _run_sql_script(db_path: String, sql_script: String, temp_suffix: String) -> Dictionary:
	var resolved_db: String = resolve_path(db_path)
	if resolved_db.is_empty():
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Empty db_path",
			"exit_code": -1,
			"output": ""
		}

	var parent_dir: String = resolved_db.get_base_dir()
	if not parent_dir.is_empty():
		var mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			return {
				"ok": false,
				"error_code": DtoSchemas.ERR_INVALID_STATE,
				"reason": "Failed to create SQLite directory: " + parent_dir,
				"exit_code": -1,
				"output": ""
			}

	var sql_path: String = resolved_db + temp_suffix
	var final_sql: String = sql_script
	if not final_sql.begins_with("PRAGMA foreign_keys = ON;"):
		final_sql = "PRAGMA foreign_keys = ON;\n" + final_sql

	var f: FileAccess = FileAccess.open(sql_path, FileAccess.WRITE)
	if f == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to write temporary SQL file: " + sql_path,
			"exit_code": -1,
			"output": ""
		}
	var _ok_w: bool = f.store_string(final_sql)
	f.flush()
	f.close()

	var exec_res: Dictionary = _exec_sql_file(resolved_db, sql_path)
	if FileAccess.file_exists(sql_path):
		var _rm_err: Error = DirAccess.remove_absolute(sql_path)

	if not _to_bool(exec_res.get("ok", false), false):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "sqlite3 failed (exit=%d): %s" % [
				_to_int(exec_res.get("exit_code", -1), -1),
				str(exec_res.get("output", ""))
			],
			"exit_code": _to_int(exec_res.get("exit_code", -1), -1),
			"output": str(exec_res.get("output", ""))
		}

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"exit_code": 0,
		"output": str(exec_res.get("output", ""))
	}


static func init_database(db_path: String, schema_sql_path: String = DEFAULT_SCHEMA_PATH) -> Dictionary:
	var resolved_schema: String = resolve_path(schema_sql_path)
	if resolved_schema.is_empty() or not FileAccess.file_exists(resolved_schema):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_SCHEMA,
			"reason": "Schema SQL file not found: " + resolved_schema
		}

	var sf: FileAccess = FileAccess.open(resolved_schema, FileAccess.READ)
	if sf == null:
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "Failed to open schema SQL file: " + resolved_schema
		}
	var schema_sql: String = sf.get_as_text()
	sf.close()

	var script: String = "PRAGMA foreign_keys = ON;\n" + schema_sql + "\n"
	var res: Dictionary = _run_sql_script(db_path, script, ".init.sql")
	if not _to_bool(res.get("ok", false), false):
		return res

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"db_path": resolve_path(db_path)
	}


static func _extract_dict_rows(source: Variant, id_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if source is Array:
		var arr: Array = source
		for item: Variant in arr:
			if item is Dictionary:
				var d: Dictionary = item
				out.append(d.duplicate(true))
	elif source is Dictionary:
		var dict_src: Dictionary = source
		var keys: Array[String] = []
		for k: Variant in dict_src.keys():
			keys.append(str(k))
		keys.sort()
		for ks: String in keys:
			var item_v: Variant = dict_src[ks]
			if item_v is Dictionary:
				var d: Dictionary = item_v
				var cp: Dictionary = d.duplicate(true)
				if not id_key.is_empty() and not cp.has(id_key):
					cp[id_key] = ks
				out.append(cp)
	return out


static func _nonempty_str(v: Variant, fallback: String) -> String:
	var s: String = str(v) if v != null else ""
	if s.is_empty():
		return fallback
	return s


static func sync_world_checkpoint(db_path: String, world_export: Dictionary) -> Dictionary:
	var resolved_db: String = resolve_path(db_path)
	if resolved_db.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Empty db_path"}
	if not FileAccess.file_exists(resolved_db):
		var init_res: Dictionary = init_database(resolved_db)
		if not _to_bool(init_res.get("ok", false), false):
			return init_res

	var sql_lines: PackedStringArray = PackedStringArray()
	var _a0: bool = sql_lines.append("PRAGMA foreign_keys = ON;")
	var _a1: bool = sql_lines.append("BEGIN IMMEDIATE;")

	# Clear tables in reverse FK dependency order so repeated full checkpoints stay consistent
	var _c0: bool = sql_lines.append("DELETE FROM command_audit_log;")
	var _c1: bool = sql_lines.append("DELETE FROM market_orders;")
	var _c2: bool = sql_lines.append("DELETE FROM armies_caravans;")
	var _c3: bool = sql_lines.append("DELETE FROM pawns_officers;")
	var _c4: bool = sql_lines.append("DELETE FROM manors;")
	var _c5: bool = sql_lines.append("DELETE FROM players;")
	var _c6: bool = sql_lines.append("DELETE FROM persona_import_challenges;")
	var _c7: bool = sql_lines.append("DELETE FROM macro_nodes;")
	var _c8: bool = sql_lines.append("DELETE FROM factions;")
	var _c9: bool = sql_lines.append("DELETE FROM world_meta;")

	# 1. world_meta
	var meta_v: Variant = world_export.get("world_meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var world_id: String = _nonempty_str(meta.get("world_id", world_export.get("world_id", "world_main")), "world_main")
	var world_seed: int = _to_int(meta.get("world_seed", world_export.get("world_seed", 18401)), 18401)
	var cur_tick: int = maxi(0, _to_int(meta.get("current_tick_id", world_export.get("current_tick_id", 0)), 0))
	var cur_day: int = maxi(0, _to_int(meta.get("current_day_id", cur_tick / SimClock.DAILY_SETTLEMENT_TICK), 0))
	var raw_season: String = _nonempty_str(meta.get("season", world_export.get("season", "SPRING")), "SPRING")
	var season: String = raw_season if VALID_SEASONS.has(raw_season) else "SPRING"
	var raw_st: String = _nonempty_str(meta.get("storyteller_id", world_export.get("storyteller_id", "SIMA_QIAN")), "SIMA_QIAN")
	var storyteller_id: String = raw_st if VALID_STORYTELLERS.has(raw_st) else "SIMA_QIAN"
	var state_crc32: int = _to_int(meta.get("state_crc32", world_export.get("state_crc32", StateHasher.crc32_dict(world_export))), 0)
	var updated_at: String = _nonempty_str(meta.get("updated_at_utc", "tick_%d" % cur_tick), "tick_%d" % cur_tick)

	var _w_meta: bool = sql_lines.append(
		"INSERT INTO world_meta (world_id, world_seed, current_tick_id, current_day_id, season, storyteller_id, state_crc32, updated_at_utc) VALUES (%s, %d, %d, %d, %s, %s, %d, %s);" % [
			sql_quote(world_id),
			world_seed,
			cur_tick,
			cur_day,
			sql_quote(season),
			sql_quote(storyteller_id),
			state_crc32,
			sql_quote(updated_at)
		]
	)

	# Pre-collect faction, node, challenge, player, and manor sets for FK consistency
	var faction_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("factions", []), "faction_id")
	var known_factions: Dictionary = {}
	for fd: Dictionary in faction_rows:
		var fid: String = _nonempty_str(fd.get("faction_id", ""), "")
		if not fid.is_empty():
			known_factions[fid] = true

	var node_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("macro_nodes", world_export.get("nodes", [])), "node_id")
	var known_nodes: Dictionary = {}
	for nd: Dictionary in node_rows:
		var nid: String = _nonempty_str(nd.get("node_id", ""), "")
		if not nid.is_empty():
			known_nodes[nid] = true
			var owner_fid: String = _nonempty_str(nd.get("owner_faction_id", "NEUTRAL"), "NEUTRAL")
			if not known_factions.has(owner_fid):
				known_factions[owner_fid] = true
				faction_rows.append({
					"faction_id": owner_fid,
					"name": owner_fid,
					"lord_player_id": "npc_" + owner_fid,
					"capital_node_id": nid,
					"royal_rank": "PREFECT"
				})

	var challenge_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("persona_import_challenges", []), "challenge_id")
	var known_challenges: Dictionary = {}
	for cd: Dictionary in challenge_rows:
		var cid: String = _nonempty_str(cd.get("challenge_id", ""), "")
		if not cid.is_empty():
			known_challenges[cid] = true

	var player_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("players", []), "player_id")
	var known_players: Dictionary = {}
	for pd: Dictionary in player_rows:
		var pid: String = _nonempty_str(pd.get("player_id", ""), "")
		if not pid.is_empty():
			known_players[pid] = true

	var manor_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("manors", []), "manor_id")
	var known_manors: Dictionary = {}
	for md: Dictionary in manor_rows:
		var mid: String = _nonempty_str(md.get("manor_id", ""), "")
		var mpid: String = _nonempty_str(md.get("player_id", ""), "")
		var m_nid: String = _nonempty_str(md.get("host_node_id", "xuchang"), "xuchang")
		if not mid.is_empty():
			known_manors[mid] = true
		if not mpid.is_empty() and not known_players.has(mpid):
			known_players[mpid] = true
			player_rows.append({
				"player_id": mpid,
				"display_name": mpid,
				"host_node_id": m_nid,
				"manor_id": mid if not mid.is_empty() else "manor_" + mpid
			})
		if not known_nodes.has(m_nid):
			known_nodes[m_nid] = true
			if not known_factions.has("NEUTRAL"):
				known_factions["NEUTRAL"] = true
				faction_rows.append({
					"faction_id": "NEUTRAL",
					"name": "NEUTRAL",
					"lord_player_id": "npc_neutral",
					"capital_node_id": m_nid,
					"royal_rank": "PREFECT"
				})
			node_rows.append({
				"node_id": m_nid,
				"name": m_nid,
				"province": "UNKNOWN",
				"node_tier": "COUNTY_TOWN",
				"owner_faction_id": "NEUTRAL"
			})

	# Ensure referenced host_node_id and persona_challenge_id in players exist
	for pd: Dictionary in player_rows:
		var h_nid: String = _nonempty_str(pd.get("host_node_id", "xuchang"), "xuchang")
		if not known_nodes.has(h_nid):
			known_nodes[h_nid] = true
			if not known_factions.has("NEUTRAL"):
				known_factions["NEUTRAL"] = true
				faction_rows.append({
					"faction_id": "NEUTRAL",
					"name": "NEUTRAL",
					"lord_player_id": "npc_neutral",
					"capital_node_id": h_nid,
					"royal_rank": "PREFECT"
				})
			node_rows.append({
				"node_id": h_nid,
				"name": h_nid,
				"province": "UNKNOWN",
				"node_tier": "COUNTY_TOWN",
				"owner_faction_id": "NEUTRAL"
			})
		var pcid_v: Variant = pd.get("persona_challenge_id", null)
		if pcid_v != null:
			var pcid: String = str(pcid_v)
			if not pcid.is_empty() and not known_challenges.has(pcid):
				known_challenges[pcid] = true
				challenge_rows.append({
					"challenge_id": pcid,
					"account_id": _nonempty_str(pd.get("player_id", "acc"), "acc"),
					"bound_player_id": _nonempty_str(pd.get("player_id", ""), ""),
					"nonce": "nonce_" + pcid + "_auto",
					"session_salt": "salt_auto",
					"cipher_key_hint": "hint_auto",
					"issued_at_tick": 0,
					"ttl_expires_tick": 900,
					"consumed_at_tick": 0,
					"status": "CONSUMED"
				})

	var pawn_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("pawns_officers", world_export.get("pawns", [])), "pawn_id")
	var army_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("armies_caravans", world_export.get("entities", [])), "entity_id")
	var order_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("market_orders", world_export.get("orders", [])), "order_id")
	var audit_rows: Array[Dictionary] = _extract_dict_rows(world_export.get("command_audit_log", []), "")

	# 2. factions
	for fd: Dictionary in faction_rows:
		var fid: String = _nonempty_str(fd.get("faction_id", ""), "")
		if fid.is_empty():
			continue
		var fname: String = _nonempty_str(fd.get("name", fid), fid)
		var lord_pid: String = _nonempty_str(fd.get("lord_player_id", "npc_" + fid), "npc_" + fid)
		var cap_nid: String = _nonempty_str(fd.get("capital_node_id", "luoyang"), "luoyang")
		var rrank: String = _map_royal_rank(_nonempty_str(fd.get("royal_rank", "PREFECT"), "PREFECT"))
		var t_grain: int = maxi(0, _to_int(fd.get("treasury_grain", 0), 0))
		var t_coin: int = maxi(0, _to_int(fd.get("treasury_coin", 0), 0))
		var edicts: int = maxi(0, _to_int(fd.get("imperial_edicts", 0), 0))
		var prestige: int = maxi(0, _to_int(fd.get("prestige", 0), 0))
		var oath_tick: int = maxi(0, _to_int(fd.get("oathbreaker_until_tick", 0), 0))

		var _wf: bool = sql_lines.append(
			"INSERT INTO factions (faction_id, name, lord_player_id, capital_node_id, royal_rank, treasury_grain, treasury_coin, imperial_edicts, prestige, oathbreaker_until_tick) VALUES (%s, %s, %s, %s, %s, %d, %d, %d, %d, %d);" % [
				sql_quote(fid),
				sql_quote(fname),
				sql_quote(lord_pid),
				sql_quote(cap_nid),
				sql_quote(rrank),
				t_grain,
				t_coin,
				edicts,
				prestige,
				oath_tick
			]
		)

	# 3. macro_nodes
	for nd: Dictionary in node_rows:
		var nid: String = _nonempty_str(nd.get("node_id", ""), "")
		if nid.is_empty():
			continue
		var nname: String = _nonempty_str(nd.get("name", nd.get("name_ko", nid)), nid)
		var prov: String = _nonempty_str(nd.get("province", "UNKNOWN"), "UNKNOWN")
		var ntier: String = _map_node_tier(_nonempty_str(nd.get("node_tier", "COUNTY_TOWN"), "COUNTY_TOWN"))
		var owner_fid: String = _nonempty_str(nd.get("owner_faction_id", "NEUTRAL"), "NEUTRAL")
		var gov_pid: Variant = nd.get("governor_player_id", null)
		var max_hp: int = maxi(1, _to_int(nd.get("max_fortification_hp", 10000), 10000))
		var fort_hp: int = clampi(_to_int(nd.get("fortification_hp", max_hp), max_hp), 0, max_hp)
		var po_bp: int = clampi(_to_int(nd.get("public_order_bp", nd.get("security_bp", 7000)), 7000), 0, 10000)
		var bp_bp: int = clampi(_to_int(nd.get("bandit_pressure_bp", 200), 200), 0, 10000)
		var tax_bp: int = clampi(_to_int(nd.get("tax_rate_bp", 1000), 1000), 500, 5000)
		var n_grain: int = maxi(0, _to_int(nd.get("treasury_grain", 0), 0))
		var n_coin: int = maxi(0, _to_int(nd.get("treasury_coin", 0), 0))
		var g_price: int = clampi(_to_int(nd.get("grain_price_bp", 1000), 1000), 100, 100000)
		var i_price: int = clampi(_to_int(nd.get("iron_price_bp", 2000), 2000), 100, 100000)

		var _wn: bool = sql_lines.append(
			"INSERT INTO macro_nodes (node_id, name, province, node_tier, owner_faction_id, governor_player_id, fortification_hp, max_fortification_hp, public_order_bp, bandit_pressure_bp, tax_rate_bp, treasury_grain, treasury_coin, grain_price_bp, iron_price_bp) VALUES (%s, %s, %s, %s, %s, %s, %d, %d, %d, %d, %d, %d, %d, %d, %d);" % [
				sql_quote(nid),
				sql_quote(nname),
				sql_quote(prov),
				sql_quote(ntier),
				sql_quote(owner_fid),
				sql_nullable_text(gov_pid),
				fort_hp,
				max_hp,
				po_bp,
				bp_bp,
				tax_bp,
				n_grain,
				n_coin,
				g_price,
				i_price
			]
		)

	# 4. persona_import_challenges
	for cd: Dictionary in challenge_rows:
		var cid: String = _nonempty_str(cd.get("challenge_id", ""), "")
		if cid.is_empty():
			continue
		var acc_id: String = _nonempty_str(cd.get("account_id", "acc_" + cid), "acc_" + cid)
		var bound_pid: Variant = cd.get("bound_player_id", null)
		var nonce: String = _nonempty_str(cd.get("nonce", "nonce_" + cid), "nonce_" + cid)
		while nonce.length() < 6:
			nonce += "_0"
		var ssalt: String = _nonempty_str(cd.get("session_salt", "salt"), "salt")
		while ssalt.length() < 4:
			ssalt += "0"
		var ckey: String = _nonempty_str(cd.get("cipher_key_hint", "hint"), "hint")
		while ckey.length() < 4:
			ckey += "0"
		var issued_t: int = maxi(0, _to_int(cd.get("issued_at_tick", 0), 0))
		var ttl_t: int = maxi(issued_t + 1, _to_int(cd.get("ttl_expires_tick", issued_t + 900), issued_t + 900))
		var raw_cstatus: String = _nonempty_str(cd.get("status", "ISSUED"), "ISSUED")
		var cstatus: String = raw_cstatus if VALID_CHALLENGE_STATUSES.has(raw_cstatus) else "ISSUED"
		var consumed_sql: String = "NULL"
		if cstatus == "CONSUMED":
			var cons_t: int = maxi(issued_t, _to_int(cd.get("consumed_at_tick", issued_t), issued_t))
			consumed_sql = str(cons_t)
		var max_att: int = clampi(_to_int(cd.get("max_attempts", 3), 3), 1, 10)
		var att_cnt: int = clampi(_to_int(cd.get("attempt_count", 0), 0), 0, max_att)
		var cd_until: int = maxi(0, _to_int(cd.get("cooldown_until_tick", 0), 0))
		var raw_cf: String = _nonempty_str(cd.get("last_coercion_flag", "R0_CLEAN"), "R0_CLEAN")
		var last_cf: String = raw_cf if VALID_COERCION_FLAGS.has(raw_cf) else "R0_CLEAN"
		var last_rej: Variant = cd.get("last_reject_reason", null)

		var _wc: bool = sql_lines.append(
			"INSERT INTO persona_import_challenges (challenge_id, account_id, bound_player_id, nonce, session_salt, cipher_key_hint, issued_at_tick, ttl_expires_tick, consumed_at_tick, status, attempt_count, max_attempts, cooldown_until_tick, last_coercion_flag, last_reject_reason) VALUES (%s, %s, %s, %s, %s, %s, %d, %d, %s, %s, %d, %d, %d, %s, %s);" % [
				sql_quote(cid),
				sql_quote(acc_id),
				sql_nullable_text(bound_pid),
				sql_quote(nonce),
				sql_quote(ssalt),
				sql_quote(ckey),
				issued_t,
				ttl_t,
				consumed_sql,
				sql_quote(cstatus),
				att_cnt,
				max_att,
				cd_until,
				sql_quote(last_cf),
				sql_nullable_text(last_rej)
			]
		)

	# 5. players
	for pd: Dictionary in player_rows:
		var pid: String = _nonempty_str(pd.get("player_id", ""), "")
		if pid.is_empty():
			continue
		var dname: String = _nonempty_str(pd.get("display_name", pid), pid)
		var ahash: String = _nonempty_str(pd.get("auth_token_hash", "hash_" + pid), "hash_" + pid)
		var raw_orig: String = _nonempty_str(pd.get("origin_archetype", "ORIGIN_CHIVALROUS_HERO"), "ORIGIN_CHIVALROUS_HERO")
		var orig: String = raw_orig if VALID_ORIGIN_ARCHETYPES.has(raw_orig) else "ORIGIN_CHIVALROUS_HERO"
		var raw_cmode: String = _nonempty_str(pd.get("creation_mode", "INTERVIEW_ONLY"), "INTERVIEW_ONLY")
		var cmode: String = raw_cmode if VALID_CREATION_MODES.has(raw_cmode) else "INTERVIEW_ONLY"
		var pprof_json: String = _json_text(pd.get("persona_profile_json", pd.get("persona_profile", {})), "{}")
		var pchall_v: Variant = pd.get("persona_challenge_id", null)
		var raw_imp: String = _nonempty_str(pd.get("import_audit_status", "NONE"), "NONE")
		var imp_stat: String = raw_imp if VALID_IMPORT_STATUSES.has(raw_imp) else "NONE"
		var raw_pcf: String = _nonempty_str(pd.get("coercion_flag", "R0_CLEAN"), "R0_CLEAN")
		var p_cf: String = raw_pcf if VALID_COERCION_FLAGS.has(raw_pcf) else "R0_CLEAN"
		var raw_rt: String = _nonempty_str(pd.get("role_tier", "FREE_OFFICER"), "FREE_OFFICER")
		var rtier: String = raw_rt if VALID_ROLE_TIERS.has(raw_rt) else "FREE_OFFICER"
		var p_fid: Variant = pd.get("faction_id", null)
		var raw_cr: String = _nonempty_str(pd.get("court_rank", "NONE"), "NONE")
		var crank: String = raw_cr if VALID_COURT_RANKS.has(raw_cr) else "NONE"
		var wmerit: int = maxi(0, _to_int(pd.get("war_merit", 0), 0))
		var h_nid: String = _nonempty_str(pd.get("host_node_id", "xuchang"), "xuchang")
		var p_mid: String = _nonempty_str(pd.get("manor_id", "manor_" + pid), "manor_" + pid)
		var is_on: int = 1 if _to_bool(pd.get("is_online", false), false) else 0
		var last_seen: int = maxi(0, _to_int(pd.get("last_seen_tick", 0), 0))
		var truce_t: int = maxi(0, _to_int(pd.get("truce_shield_until_tick", 0), 0))
		var adapt_bp: int = clampi(_to_int(pd.get("adaptation_factor_bp", 1000), 1000), 400, 1500)

		var _wp: bool = sql_lines.append(
			"INSERT INTO players (player_id, display_name, auth_token_hash, origin_archetype, creation_mode, persona_profile_json, persona_challenge_id, import_audit_status, coercion_flag, role_tier, faction_id, court_rank, war_merit, host_node_id, manor_id, is_online, last_seen_tick, truce_shield_until_tick, adaptation_factor_bp) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %d, %s, %s, %d, %d, %d, %d);" % [
				sql_quote(pid),
				sql_quote(dname),
				sql_quote(ahash),
				sql_quote(orig),
				sql_quote(cmode),
				sql_quote(pprof_json),
				sql_nullable_text(pchall_v),
				sql_quote(imp_stat),
				sql_quote(p_cf),
				sql_quote(rtier),
				sql_nullable_text(p_fid),
				sql_quote(crank),
				wmerit,
				sql_quote(h_nid),
				sql_quote(p_mid),
				is_on,
				last_seen,
				truce_t,
				adapt_bp
			]
		)

	# 6. manors
	for md: Dictionary in manor_rows:
		var mid: String = _nonempty_str(md.get("manor_id", ""), "")
		if mid.is_empty():
			continue
		var mpid: String = _nonempty_str(md.get("player_id", ""), "")
		if mpid.is_empty():
			continue
		var mnid: String = _nonempty_str(md.get("host_node_id", "xuchang"), "xuchang")
		var mlod: int = 0 if _to_int(md.get("current_lod", 1), 1) == 0 else 1

		var res_v: Variant = md.get("resources", null)
		var res_d: Dictionary = res_v if res_v is Dictionary else {}
		var grain_s: int = maxi(0, _to_int(md.get("grain_stock", res_d.get("GRAIN", 0)), 0))
		var coin_s: int = maxi(0, _to_int(md.get("coin_stock", res_d.get("COIN", 0)), 0))
		var iron_s: int = maxi(0, _to_int(md.get("iron_stock", res_d.get("IRON", 0)), 0))
		var wood_s: int = maxi(0, _to_int(md.get("wood_stock", res_d.get("WOOD", 0)), 0))
		var horse_s: int = maxi(0, _to_int(md.get("horse_stock", res_d.get("HORSES", 0)), 0))
		var hw_s: int = maxi(0, _to_int(md.get("herbs_wine_stock", res_d.get("HERBS_WINE", 0)), 0))
		var weap_s: int = maxi(0, _to_int(md.get("weapon_stock", res_d.get("WEAPONS", 0)), 0))
		var htroops: int = clampi(_to_int(md.get("household_troops", 0), 0), 0, 3000)
		var vault_bp: int = clampi(_to_int(md.get("vault_protected_bp", 4000), 4000), 4000, 6500)
		var wall_hp: int = maxi(0, _to_int(md.get("wall_hp", 2000), 2000))
		var sd_json: String = _json_text(md.get("standing_doctrine_json", md.get("standing_doctrine", {})), "{}")
		var gz_json: String = _json_text(md.get("grid_zones_json", md.get("zones", [])), "[]")

		var _wm: bool = sql_lines.append(
			"INSERT INTO manors (manor_id, player_id, host_node_id, current_lod, grain_stock, coin_stock, iron_stock, wood_stock, horse_stock, herbs_wine_stock, weapon_stock, household_troops, vault_protected_bp, wall_hp, standing_doctrine_json, grid_zones_json) VALUES (%s, %s, %s, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s, %s);" % [
				sql_quote(mid),
				sql_quote(mpid),
				sql_quote(mnid),
				mlod,
				grain_s,
				coin_s,
				iron_s,
				wood_s,
				horse_s,
				hw_s,
				weap_s,
				htroops,
				vault_bp,
				wall_hp,
				sql_quote(sd_json),
				sql_quote(gz_json)
			]
		)

	# 7. pawns_officers
	for pwd: Dictionary in pawn_rows:
		var pwid: String = _nonempty_str(pwd.get("pawn_id", ""), "")
		if pwid.is_empty():
			continue
		var owner_pid: String = _nonempty_str(pwd.get("owner_player_id", ""), "")
		var p_mid: String = _nonempty_str(pwd.get("manor_id", ""), "")
		if owner_pid.is_empty() or p_mid.is_empty():
			continue
		var pname: String = _nonempty_str(pwd.get("name", pwid), pwid)
		var is_av: int = 1 if _to_bool(pwd.get("is_avatar", false), false) else 0
		var raw_pstate: String = _nonempty_str(pwd.get("state", "IN_MANOR"), "IN_MANOR")
		var pstate: String = raw_pstate if VALID_PAWN_STATES.has(raw_pstate) else "IN_MANOR"
		var raw_hstate: String = _nonempty_str(pwd.get("health_state", "HEALTHY"), "HEALTHY")
		var hstate: String = raw_hstate if VALID_HEALTH_STATES.has(raw_hstate) else "HEALTHY"

		var st_v: Variant = pwd.get("stats", null)
		var st_d: Dictionary = st_v if st_v is Dictionary else {}
		var lea: int = clampi(_to_int(pwd.get("leadership", st_d.get("LEA", 60)), 60), 1, 120)
		var mar: int = clampi(_to_int(pwd.get("martial", st_d.get("MAR", 60)), 60), 1, 120)
		var intl: int = clampi(_to_int(pwd.get("intelligence", st_d.get("INT", 60)), 60), 1, 120)
		var pol: int = clampi(_to_int(pwd.get("politics", st_d.get("POL", 60)), 60), 1, 120)
		var cha: int = clampi(_to_int(pwd.get("charisma", st_d.get("CHA", 60)), 60), 1, 120)

		var nd_v: Variant = pwd.get("needs_bp", null)
		var nd_d: Dictionary = nd_v if nd_v is Dictionary else {}
		var food_bp: int = clampi(_to_int(pwd.get("food_need_bp", nd_d.get("FOOD", 7500)), 7500), 0, 10000)
		var rest_bp: int = clampi(_to_int(pwd.get("rest_need_bp", nd_d.get("REST", 7500)), 7500), 0, 10000)
		var mor_bp: int = clampi(_to_int(pwd.get("morale_bp", nd_d.get("MORALE", 7500)), 7500), 0, 10000)
		var loy_bp: int = clampi(_to_int(pwd.get("loyalty_bp", nd_d.get("LOYALTY", 7500)), 7500), 0, 10000)
		var amb_bp: int = clampi(_to_int(pwd.get("ambition_bp", nd_d.get("AMBITION", 5000)), 5000), 0, 10000)

		var mood: int = clampi(_to_int(pwd.get("mood", 50), 50), 0, 100)
		var raw_mstate: String = _nonempty_str(pwd.get("mental_state", "NORMAL"), "NORMAL")
		var mstate: String = raw_mstate if VALID_MENTAL_STATES.has(raw_mstate) else "NORMAL"
		var tr_json: String = _json_text(pwd.get("traits_json", pwd.get("traits", [])), "[]")
		var wp_json: String = _json_text(pwd.get("work_priorities_json", pwd.get("work_priorities", {})), "{}")
		var ds_json: String = _json_text(pwd.get("daily_schedule_json", pwd.get("daily_schedule", [])), "[]")

		var _wpw: bool = sql_lines.append(
			"INSERT INTO pawns_officers (pawn_id, owner_player_id, manor_id, name, is_avatar, state, health_state, leadership, martial, intelligence, politics, charisma, food_need_bp, rest_need_bp, morale_bp, loyalty_bp, ambition_bp, mood, mental_state, traits_json, work_priorities_json, daily_schedule_json) VALUES (%s, %s, %s, %s, %d, %s, %s, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %s, %s, %s, %s);" % [
				sql_quote(pwid),
				sql_quote(owner_pid),
				sql_quote(p_mid),
				sql_quote(pname),
				is_av,
				sql_quote(pstate),
				sql_quote(hstate),
				lea,
				mar,
				intl,
				pol,
				cha,
				food_bp,
				rest_bp,
				mor_bp,
				loy_bp,
				amb_bp,
				mood,
				sql_quote(mstate),
				sql_quote(tr_json),
				sql_quote(wp_json),
				sql_quote(ds_json)
			]
		)

	# 8. armies_caravans
	for ad: Dictionary in army_rows:
		var eid: String = _nonempty_str(ad.get("entity_id", ""), "")
		if eid.is_empty():
			continue
		var a_pid: String = _nonempty_str(ad.get("owner_player_id", ""), "")
		if a_pid.is_empty():
			continue
		var a_fid: Variant = ad.get("faction_id", null)
		var aut: String = _map_army_unit_type(_nonempty_str(ad.get("unit_type", "ARMY"), "ARMY"))
		var cur_nid: Variant = ad.get("current_node_id", null)
		var cur_eid: Variant = ad.get("current_edge_id", null)
		var e_pm: int = clampi(_to_int(ad.get("edge_progress_pm", 0), 0), 0, 1000)
		var troops: int = maxi(0, _to_int(ad.get("troop_count", 0), 0))
		var mor: int = clampi(_to_int(ad.get("morale_bp", 8000), 8000), 0, 10000)
		var c_grain: int = maxi(0, _to_int(ad.get("carried_grain", 0), 0))
		var c_coin: int = maxi(0, _to_int(ad.get("carried_coin", 0), 0))
		var cargo_json: String = _json_text(ad.get("cargo_json", ad.get("cargo", {})), "{}")
		var doc_json: String = _json_text(ad.get("doctrine_json", ad.get("doctrine", ad.get("standing_doctrine", {}))), "{}")

		var _wa: bool = sql_lines.append(
			"INSERT INTO armies_caravans (entity_id, owner_player_id, faction_id, unit_type, current_node_id, current_edge_id, edge_progress_pm, troop_count, morale_bp, carried_grain, carried_coin, cargo_json, doctrine_json) VALUES (%s, %s, %s, %s, %s, %s, %d, %d, %d, %d, %d, %s, %s);" % [
				sql_quote(eid),
				sql_quote(a_pid),
				sql_nullable_text(a_fid),
				sql_quote(aut),
				sql_nullable_text(cur_nid),
				sql_nullable_text(cur_eid),
				e_pm,
				troops,
				mor,
				c_grain,
				c_coin,
				sql_quote(cargo_json),
				sql_quote(doc_json)
			]
		)

	# 9. market_orders
	for od: Dictionary in order_rows:
		var oid: String = _nonempty_str(od.get("order_id", ""), "")
		var o_nid: String = _nonempty_str(od.get("node_id", ""), "")
		var o_pid: String = _nonempty_str(od.get("player_id", ""), "")
		if oid.is_empty() or o_nid.is_empty() or o_pid.is_empty():
			continue
		var comm: String = _map_commodity(_nonempty_str(od.get("commodity", "GRAIN"), "GRAIN"))
		var raw_side: String = _nonempty_str(od.get("side", "BID"), "BID")
		var oside: String = raw_side if VALID_ORDER_SIDES.has(raw_side) else "BID"
		var price_bp: int = clampi(_to_int(od.get("price_bp", 1000), 1000), 100, 100000)
		var qty: int = maxi(1, _to_int(od.get("quantity", 1), 1))
		var filled: int = clampi(_to_int(od.get("filled_quantity", 0), 0), 0, qty)
		var ctick: int = maxi(0, _to_int(od.get("created_tick", 0), 0))
		var raw_ostatus: String = _nonempty_str(od.get("status", "OPEN"), "OPEN")
		var ostatus: String = raw_ostatus if VALID_ORDER_STATUSES.has(raw_ostatus) else "OPEN"

		var _wo: bool = sql_lines.append(
			"INSERT INTO market_orders (order_id, node_id, player_id, commodity, side, price_bp, quantity, filled_quantity, created_tick, status) VALUES (%s, %s, %s, %s, %s, %d, %d, %d, %d, %s);" % [
				sql_quote(oid),
				sql_quote(o_nid),
				sql_quote(o_pid),
				sql_quote(comm),
				sql_quote(oside),
				price_bp,
				qty,
				filled,
				ctick,
				sql_quote(ostatus)
			]
		)

	# 10. command_audit_log
	for ld: Dictionary in audit_rows:
		var l_tick: int = maxi(0, _to_int(ld.get("tick_id", 0), 0))
		var l_pid: String = _nonempty_str(ld.get("player_id", "system"), "system")
		var l_ctype: String = _nonempty_str(ld.get("cmd_type", "UNKNOWN"), "UNKNOWN")
		var raw_lstat: String = _nonempty_str(ld.get("status", "ACCEPTED"), "ACCEPTED")
		var l_stat: String = raw_lstat if VALID_AUDIT_STATUSES.has(raw_lstat) else "ACCEPTED"
		var l_reason: Variant = ld.get("reject_reason", null)
		var l_payload: String = _json_text(ld.get("payload_json", ld.get("payload", {})), "{}")

		if ld.has("seq_id") and _to_int(ld.get("seq_id", 0), 0) > 0:
			var seq_id: int = _to_int(ld.get("seq_id", 1), 1)
			var _wl1: bool = sql_lines.append(
				"INSERT INTO command_audit_log (seq_id, tick_id, player_id, cmd_type, status, reject_reason, payload_json) VALUES (%d, %d, %s, %s, %s, %s, %s);" % [
					seq_id,
					l_tick,
					sql_quote(l_pid),
					sql_quote(l_ctype),
					sql_quote(l_stat),
					sql_nullable_text(l_reason),
					sql_quote(l_payload)
				]
			)
		else:
			var _wl2: bool = sql_lines.append(
				"INSERT INTO command_audit_log (tick_id, player_id, cmd_type, status, reject_reason, payload_json) VALUES (%d, %s, %s, %s, %s, %s);" % [
					l_tick,
					sql_quote(l_pid),
					sql_quote(l_ctype),
					sql_quote(l_stat),
					sql_nullable_text(l_reason),
					sql_quote(l_payload)
				]
			)

	var _acom: bool = sql_lines.append("COMMIT;")
	var sql_script: String = "\n".join(sql_lines) + "\n"
	var res: Dictionary = _run_sql_script(resolved_db, sql_script, ".sync.sql")
	if not _to_bool(res.get("ok", false), false):
		return res

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"db_path": resolved_db,
		"synced_counts": {
			"world_meta": 1,
			"factions": faction_rows.size(),
			"macro_nodes": node_rows.size(),
			"persona_import_challenges": challenge_rows.size(),
			"players": player_rows.size(),
			"manors": manor_rows.size(),
			"pawns_officers": pawn_rows.size(),
			"armies_caravans": army_rows.size(),
			"market_orders": order_rows.size(),
			"command_audit_log": audit_rows.size()
		}
	}


static func query_table_counts(db_path: String) -> Dictionary:
	var resolved_db: String = resolve_path(db_path)
	if resolved_db.is_empty() or not FileAccess.file_exists(resolved_db):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "SQLite database does not exist: " + resolved_db,
			"counts": {}
		}

	var select_parts: PackedStringArray = PackedStringArray()
	for tbl: String in CANONICAL_TABLES:
		var _ok: bool = select_parts.append("SELECT '%s' AS tbl, COUNT(*) AS cnt FROM %s" % [tbl, tbl])
	var sql_script: String = "PRAGMA foreign_keys = ON;\n.mode list\n.separator |\n" + "\nUNION ALL\n".join(select_parts) + ";\n"

	var res: Dictionary = _run_sql_script(resolved_db, sql_script, ".counts.sql")
	if not _to_bool(res.get("ok", false), false):
		return {
			"ok": false,
			"error_code": str(res.get("error_code", DtoSchemas.ERR_INVALID_STATE)),
			"reason": str(res.get("reason", "Failed to query table counts")),
			"counts": {}
		}

	var counts: Dictionary = {}
	for tbl: String in CANONICAL_TABLES:
		counts[tbl] = 0

	var out_text: String = str(res.get("output", ""))
	for raw_line: String in out_text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty() or not line.contains("|"):
			continue
		var parts: PackedStringArray = line.split("|")
		if parts.size() >= 2:
			var tname: String = parts[0].strip_edges()
			var cnt_str: String = parts[1].strip_edges()
			if CANONICAL_TABLES.has(tname):
				counts[tname] = cnt_str.to_int()

	return {
		"ok": true,
		"error_code": DtoSchemas.ERR_OK,
		"reason": "",
		"counts": counts
	}


static func verify_integrity(db_path: String) -> Dictionary:
	var resolved_db: String = resolve_path(db_path)
	if resolved_db.is_empty() or not FileAccess.file_exists(resolved_db):
		return {
			"ok": false,
			"error_code": DtoSchemas.ERR_INVALID_STATE,
			"reason": "SQLite database does not exist: " + resolved_db,
			"foreign_key_violations": [],
			"integrity_ok": false
		}

	var fk_res: Dictionary = _run_sql_script(
		resolved_db,
		"PRAGMA foreign_keys = ON;\n.mode list\n.separator |\nPRAGMA foreign_key_check;\n",
		".fk_check.sql"
	)
	if not _to_bool(fk_res.get("ok", false), false):
		return {
			"ok": false,
			"error_code": str(fk_res.get("error_code", DtoSchemas.ERR_INVALID_STATE)),
			"reason": str(fk_res.get("reason", "PRAGMA foreign_key_check failed")),
			"foreign_key_violations": [],
			"integrity_ok": false
		}

	var fk_out: String = str(fk_res.get("output", "")).strip_edges()
	var fk_violations: Array[String] = []
	if not fk_out.is_empty():
		for line: String in fk_out.split("\n"):
			var trimmed: String = line.strip_edges()
			if not trimmed.is_empty():
				fk_violations.append(trimmed)

	var int_res: Dictionary = _run_sql_script(
		resolved_db,
		"PRAGMA foreign_keys = ON;\n.mode list\nPRAGMA integrity_check;\n",
		".int_check.sql"
	)
	if not _to_bool(int_res.get("ok", false), false):
		return {
			"ok": false,
			"error_code": str(int_res.get("error_code", DtoSchemas.ERR_INVALID_STATE)),
			"reason": str(int_res.get("reason", "PRAGMA integrity_check failed")),
			"foreign_key_violations": fk_violations,
			"integrity_ok": false
		}

	var int_out: String = str(int_res.get("output", "")).strip_edges()
	var integrity_ok: bool = int_out == "ok"
	var all_ok: bool = integrity_ok and fk_violations.is_empty()

	return {
		"ok": all_ok,
		"error_code": DtoSchemas.ERR_OK if all_ok else DtoSchemas.ERR_INVALID_STATE,
		"reason": "" if all_ok else "SQLite integrity or foreign key check failed",
		"foreign_key_violations": fk_violations,
		"integrity_check_output": int_out,
		"integrity_ok": integrity_ok
	}
