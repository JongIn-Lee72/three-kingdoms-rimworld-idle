class_name SeasonHegemonyService
extends RefCounted

const HEGEMON_TITLE_KO: String = "천하 패자"
const TOP_OFFICER_TITLE_KO: String = "개국 공신"
const MENTOR_XP_MIN_PM: int = 50
const MENTOR_XP_MAX_PM: int = 120

var season_history: Array[Dictionary] = []
var lineage_records: Array[Dictionary] = []


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


static func _royal_rank_tier(raw_rank: String) -> int:
	match raw_rank:
		"PREFECT", "GOVERNOR_INSPECTOR":
			return 1
		"GOVERNOR_GENERAL", "PROVINCE_GOVERNOR":
			return 2
		"DUKE":
			return 3
		"KING":
			return 4
		"EMPEROR":
			return 5
		_:
			return 1


static func _court_rank_tier(raw_rank: String) -> int:
	var spec_var: Variant = FactionManager.RANK_SPECS.get(raw_rank, null)
	if spec_var is Dictionary:
		var spec: Dictionary = spec_var
		return _to_int(spec.get("tier", 0), 0)
	return 0


static func _extract_factions_list(world_snapshot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var src: Variant = world_snapshot.get("factions", null)
	if src == null and world_snapshot.has("faction_manager"):
		var fm_v: Variant = world_snapshot["faction_manager"]
		if fm_v is Dictionary:
			var fm_d: Dictionary = fm_v
			src = fm_d.get("factions", null)

	if src is Array:
		var arr: Array = src
		for item: Variant in arr:
			if item is Dictionary:
				var d: Dictionary = item
				out.append(d)
	elif src is Dictionary:
		var md: Dictionary = src
		var keys: Array[String] = []
		for k: Variant in md.keys():
			keys.append(str(k))
		keys.sort()
		for k_str: String in keys:
			var item_v: Variant = md[k_str]
			if item_v is Dictionary:
				var d2: Dictionary = item_v
				var copy_d: Dictionary = d2.duplicate(true)
				if not copy_d.has("faction_id"):
					copy_d["faction_id"] = k_str
				out.append(copy_d)
	return out


static func _extract_players_list(world_snapshot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var src: Variant = world_snapshot.get("players", null)
	if src == null and world_snapshot.has("faction_manager"):
		var fm_v: Variant = world_snapshot["faction_manager"]
		if fm_v is Dictionary:
			var fm_d: Dictionary = fm_v
			src = fm_d.get("players", null)

	if src is Array:
		var arr: Array = src
		for item: Variant in arr:
			if item is Dictionary:
				var d: Dictionary = item
				out.append(d)
	elif src is Dictionary:
		var md: Dictionary = src
		var keys: Array[String] = []
		for k: Variant in md.keys():
			keys.append(str(k))
		keys.sort()
		for k_str: String in keys:
			var item_v: Variant = md[k_str]
			if item_v is Dictionary:
				var d2: Dictionary = item_v
				var copy_d: Dictionary = d2.duplicate(true)
				if not copy_d.has("player_id"):
					copy_d["player_id"] = k_str
				out.append(copy_d)
	return out


static func _extract_nodes_list(world_snapshot: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var src: Variant = world_snapshot.get("nodes", null)
	if src == null:
		src = world_snapshot.get("macro_nodes", null)
	if src == null and world_snapshot.has("world_graph"):
		var wg_v: Variant = world_snapshot["world_graph"]
		if wg_v is Dictionary:
			var wg_d: Dictionary = wg_v
			src = wg_d.get("nodes", null)

	if src is Array:
		var arr: Array = src
		for item: Variant in arr:
			if item is Dictionary:
				var d: Dictionary = item
				out.append(d)
	elif src is Dictionary:
		var md: Dictionary = src
		var keys: Array[String] = []
		for k: Variant in md.keys():
			keys.append(str(k))
		keys.sort()
		for k_str: String in keys:
			var item_v: Variant = md[k_str]
			if item_v is Dictionary:
				var d2: Dictionary = item_v
				out.append(d2)
	return out


static func _count_sworn_siblings_map(world_snapshot: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	var rel_src: Variant = world_snapshot.get("relation_tags", null)
	if rel_src == null and world_snapshot.has("social_service"):
		var ss_v: Variant = world_snapshot["social_service"]
		if ss_v is Dictionary:
			var ss_d: Dictionary = ss_v
			rel_src = ss_d.get("relation_tags", null)
	if not (rel_src is Dictionary):
		return counts
	var rel_d: Dictionary = rel_src
	var seen_pairs: Dictionary = {}
	for edge_v: Variant in rel_d.keys():
		var edge: String = str(edge_v)
		var sep: int = edge.find("->")
		if sep <= 0:
			continue
		var from_id: String = edge.substr(0, sep)
		var to_id: String = edge.substr(sep + 2)
		var tags_v: Variant = rel_d[edge_v]
		if not (tags_v is Array):
			continue
		var tags: Array = tags_v
		var has_sworn: bool = false
		for t_v: Variant in tags:
			if str(t_v) == "SWORN_SIBLING":
				has_sworn = true
				break
		if not has_sworn:
			continue
		var norm_from: String = from_id.trim_suffix("_avatar")
		var norm_to: String = to_id.trim_suffix("_avatar")
		var pair_key: String = norm_from + "|" + norm_to
		if not seen_pairs.has(pair_key):
			seen_pairs[pair_key] = true
			counts[norm_from] = _to_int(counts.get(norm_from, 0), 0) + 1
	return counts


static func _count_adopted_proposals_map(world_snapshot: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	var prop_src: Variant = world_snapshot.get("proposals", null)
	if prop_src == null and world_snapshot.has("faction_manager"):
		var fm_v: Variant = world_snapshot["faction_manager"]
		if fm_v is Dictionary:
			var fm_d: Dictionary = fm_v
			prop_src = fm_d.get("proposals", null)

	var items: Array = []
	if prop_src is Array:
		var pa: Array = prop_src
		items = pa
	elif prop_src is Dictionary:
		var pd: Dictionary = prop_src
		for k_v: Variant in pd.keys():
			items.append(pd[k_v])

	for item: Variant in items:
		if not (item is Dictionary):
			continue
		var pr: Dictionary = item
		if str(pr.get("status", "")) != "ADOPTED":
			continue
		var owner_pid: String = str(pr.get("owner_player_id", ""))
		if owner_pid.is_empty():
			var pawn_id: String = str(pr.get("pawn_id", ""))
			if pawn_id.ends_with("_avatar"):
				owner_pid = pawn_id.trim_suffix("_avatar")
		if not owner_pid.is_empty():
			counts[owner_pid] = _to_int(counts.get(owner_pid, 0), 0) + 1
	return counts


static func _compare_lord_entries(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = _to_int(a.get("score", 0), 0)
	var sb: int = _to_int(b.get("score", 0), 0)
	if sa != sb:
		return sa > sb
	return str(a.get("faction_id", "")) < str(b.get("faction_id", ""))


static func _compare_officer_entries(a: Dictionary, b: Dictionary) -> bool:
	var sa: int = _to_int(a.get("score", 0), 0)
	var sb: int = _to_int(b.get("score", 0), 0)
	if sa != sb:
		return sa > sb
	return str(a.get("player_id", "")) < str(b.get("player_id", ""))


func _init() -> void:
	season_history.clear()
	lineage_records.clear()


func compute_season_settlement(world_snapshot: Dictionary, season_number: int) -> Dictionary:
	var resolved_season: int = maxi(1, season_number)
	var factions_list: Array[Dictionary] = _extract_factions_list(world_snapshot)
	var players_list: Array[Dictionary] = _extract_players_list(world_snapshot)
	var nodes_list: Array[Dictionary] = _extract_nodes_list(world_snapshot)

	var city_counts: Dictionary = {}
	for nd: Dictionary in nodes_list:
		var owner_fid: String = str(nd.get("owner_faction_id", "NEUTRAL"))
		if not owner_fid.is_empty() and owner_fid != "NEUTRAL":
			city_counts[owner_fid] = _to_int(city_counts.get(owner_fid, 0), 0) + 1

	var lord_board: Array[Dictionary] = []
	for fac: Dictionary in factions_list:
		var fid: String = str(fac.get("faction_id", ""))
		if fid.is_empty() or fid == "NEUTRAL":
			continue
		var lord_pid: String = str(fac.get("lord_player_id", ""))
		if fid == "YELLOW_TURBAN" and lord_pid == "npc_zhang_jiao" and _to_int(city_counts.get(fid, 0), 0) == 0:
			continue

		var controlled_cities: int = _to_int(city_counts.get(fid, _to_int(fac.get("controlled_cities", 0), 0)), 0)
		if fac.has("controlled_cities") and nodes_list.is_empty():
			controlled_cities = maxi(0, _to_int(fac.get("controlled_cities", 0), 0))
		var royal_rank_str: String = str(fac.get("royal_rank", "GOVERNOR_INSPECTOR"))
		var royal_tier: int = _to_int(fac.get("royal_rank_tier", _royal_rank_tier(royal_rank_str)), _royal_rank_tier(royal_rank_str))
		var prestige: int = maxi(0, _to_int(fac.get("prestige", 0), 0))
		var treasury_total: int = 0
		if fac.has("treasury"):
			treasury_total = maxi(0, _to_int(fac.get("treasury", 0), 0))
		else:
			treasury_total = maxi(0, _to_int(fac.get("treasury_coin", 0), 0)) + maxi(0, _to_int(fac.get("treasury_grain", 0), 0))

		@warning_ignore("integer_division")
		var treasury_score: int = treasury_total / 100
		var score: int = controlled_cities * 500 + royal_tier * 800 + prestige + treasury_score

		lord_board.append({
			"faction_id": fid,
			"faction_name": str(fac.get("name", fid)),
			"lord_player_id": lord_pid,
			"controlled_cities": controlled_cities,
			"royal_rank": royal_rank_str,
			"royal_rank_tier": royal_tier,
			"prestige": prestige,
			"treasury": treasury_total,
			"score": score,
			"title": ""
		})

	lord_board.sort_custom(Callable(SeasonHegemonyService, "_compare_lord_entries"))
	for i: int in range(lord_board.size()):
		lord_board[i]["rank"] = i + 1
		if i == 0:
			lord_board[i]["title"] = HEGEMON_TITLE_KO

	var sworn_map: Dictionary = _count_sworn_siblings_map(world_snapshot)
	var prop_map: Dictionary = _count_adopted_proposals_map(world_snapshot)

	var officer_board: Array[Dictionary] = []
	for prof: Dictionary in players_list:
		var pid: String = str(prof.get("player_id", ""))
		if pid.is_empty() or pid == "npc_neutral_lord" or pid == "npc_zhang_jiao":
			continue
		var war_merit: int = maxi(0, _to_int(prof.get("war_merit", 0), 0))
		var court_rank_str: String = str(prof.get("court_rank", "NONE"))
		var court_tier: int = _to_int(prof.get("court_rank_tier", _court_rank_tier(court_rank_str)), _court_rank_tier(court_rank_str))
		var sworn_cnt: int = _to_int(prof.get("sworn_siblings_count", sworn_map.get(pid, 0)), 0)
		if prof.has("sworn_siblings") and prof["sworn_siblings"] is Array:
			var s_arr: Array = prof["sworn_siblings"]
			sworn_cnt = maxi(sworn_cnt, s_arr.size())
		var prop_cnt: int = _to_int(prof.get("proposals_adopted", prop_map.get(pid, 0)), 0)
		var score: int = war_merit + court_tier * 400 + sworn_cnt * 250 + prop_cnt * 150

		officer_board.append({
			"player_id": pid,
			"faction_id": str(prof.get("faction_id", "")),
			"role_tier": str(prof.get("role_tier", "FREE_OFFICER")),
			"court_rank": court_rank_str,
			"court_rank_tier": court_tier,
			"war_merit": war_merit,
			"sworn_siblings": sworn_cnt,
			"proposals_adopted": prop_cnt,
			"score": score,
			"title": ""
		})

	officer_board.sort_custom(Callable(SeasonHegemonyService, "_compare_officer_entries"))
	for i: int in range(officer_board.size()):
		officer_board[i]["rank"] = i + 1
		if i == 0:
			officer_board[i]["title"] = TOP_OFFICER_TITLE_KO

	var hegemon: Dictionary = lord_board[0].duplicate(true) if not lord_board.is_empty() else {}
	var top_officer: Dictionary = officer_board[0].duplicate(true) if not officer_board.is_empty() else {}

	var settlement: Dictionary = {
		"season_number": resolved_season,
		"tick_id": maxi(0, _to_int(world_snapshot.get("tick_id", 0), 0)),
		"hegemon_title": HEGEMON_TITLE_KO,
		"hegemon": hegemon,
		"top_officer_title": TOP_OFFICER_TITLE_KO,
		"top_merit_officer": top_officer,
		"lord_leaderboard": lord_board,
		"officer_leaderboard": officer_board
	}
	season_history.append(settlement.duplicate(true))
	return settlement


static func _extract_surname(mentor_name: String) -> String:
	var trimmed: String = mentor_name.strip_edges()
	if trimmed.is_empty():
		return "무명"
	if trimmed.contains("_"):
		var parts: PackedStringArray = trimmed.split("_", false)
		if not parts.is_empty():
			return parts[0]
	if trimmed.contains(" "):
		var parts_sp: PackedStringArray = trimmed.split(" ", false)
		if not parts_sp.is_empty():
			return parts_sp[0]
	return trimmed.substr(0, 1)


func create_lineage_heir(
	mentor_pawn_dict: Dictionary,
	heir_name: String,
	family_motto: String,
	world_seed: int,
	tick_id: int
) -> Dictionary:
	var mentor_id: String = str(mentor_pawn_dict.get("pawn_id", "mentor_unknown"))
	var mentor_name: String = str(mentor_pawn_dict.get("name", "선대 장수"))
	var owner_pid: String = str(mentor_pawn_dict.get("owner_player_id", "player_01"))
	var clean_heir_name: String = heir_name.strip_edges()
	if clean_heir_name.is_empty():
		clean_heir_name = "후계자"
	var clean_motto: String = family_motto.strip_edges()
	if clean_motto.length() > 40:
		clean_motto = clean_motto.substr(0, 40)
	if clean_motto.is_empty():
		clean_motto = "가문의 대의를 잇는다"

	var surname: String = _extract_surname(mentor_name)

	# Derive raw stat proportions from mentor while strictly enforcing TOTAL_STAT_BUDGET = 320 & [35, 85]
	var m_stats_v: Variant = mentor_pawn_dict.get("stats", {})
	var m_stats: Dictionary = m_stats_v if m_stats_v is Dictionary else {}
	var raw_weights: Array[int] = []
	for sk: String in DtoSchemas.STAT_KEYS:
		raw_weights.append(clampi(_to_int(m_stats.get(sk, 64), 64), 1, 1000))
	var norm_arr: Array[int] = SealedTokenCodec.normalize_weights_320(raw_weights)

	var heir_stats: Dictionary = {}
	var stat_sum: int = 0
	for i: int in range(DtoSchemas.STAT_KEYS.size()):
		var sk: String = DtoSchemas.STAT_KEYS[i]
		var sv: int = clampi(norm_arr[i], DtoSchemas.STAT_MIN_BASE, DtoSchemas.STAT_MAX_BASE)
		heir_stats[sk] = sv
		stat_sum += sv

	# Bounded deterministic mentorship XP boost (+50..+120 pm)
	var entity_hash: int = StateHasher.crc32_bytes((mentor_id + ":" + clean_heir_name).to_utf8_buffer())
	var mentorship_xp_boost_pm: int = DeterministicRNG.roll_range(
		world_seed, tick_id, entity_hash, 7301, MENTOR_XP_MIN_PM, MENTOR_XP_MAX_PM
	)

	# Inherit bounded passions (50% inheritance / max PASSION_BUDGET = 3 points)
	var m_pass_v: Variant = mentor_pawn_dict.get("passions_pm", {})
	var m_pass: Dictionary = m_pass_v if m_pass_v is Dictionary else {}
	var best_stat: String = "LEA"
	var best_pm: int = -1
	for sk: String in DtoSchemas.STAT_KEYS:
		var pm: int = _to_int(m_pass.get(sk, PawnEntity.PASSION_NORMAL_PM), PawnEntity.PASSION_NORMAL_PM)
		if pm > best_pm:
			best_pm = pm
			best_stat = sk

	var heir_passions: Dictionary = {}
	var passion_points_used: int = 0
	for sk: String in DtoSchemas.STAT_KEYS:
		heir_passions[sk] = PawnEntity.PASSION_NORMAL_PM
	if best_pm >= PawnEntity.PASSION_DOUBLE_PM:
		heir_passions[best_stat] = PawnEntity.PASSION_SINGLE_PM
		passion_points_used = 1
	elif best_pm >= PawnEntity.PASSION_SINGLE_PM:
		heir_passions[best_stat] = PawnEntity.PASSION_SINGLE_PM
		passion_points_used = 1

	var heir_seq: int = lineage_records.size() + 1
	var heir_id: String = "%s_heir_%04d" % [owner_pid, heir_seq]
	var chronicle_text: String = "%s의 문하에서 %s(%s 가문)이 '%s'의 가훈과 함께 후계자로 입문하였다 (사사 경험치 보너스 +%d pm)." % [
		mentor_name, clean_heir_name, surname, clean_motto, mentorship_xp_boost_pm
	]

	var rec: Dictionary = {
		"heir_id": heir_id,
		"owner_player_id": owner_pid,
		"mentor_pawn_id": mentor_id,
		"mentor_name": mentor_name,
		"heir_name": clean_heir_name,
		"inherited_surname": surname,
		"family_motto": clean_motto,
		"origin_archetype": str(mentor_pawn_dict.get("origin_archetype", "ORIGIN_CHIVALROUS_HERO")),
		"stats": heir_stats,
		"total_stat_budget": stat_sum,
		"passions_pm": heir_passions,
		"passion_points_used": passion_points_used,
		"mentorship_xp_boost_pm": mentorship_xp_boost_pm,
		"created_tick": maxi(0, tick_id),
		"legacy_chronicle": chronicle_text
	}
	lineage_records.append(rec.duplicate(true))
	return rec


func to_dict() -> Dictionary:
	var hist_copy: Array[Dictionary] = []
	for sh: Dictionary in season_history:
		hist_copy.append(sh.duplicate(true))
	var lin_copy: Array[Dictionary] = []
	for lr: Dictionary in lineage_records:
		lin_copy.append(lr.duplicate(true))
	return {
		"season_history": hist_copy,
		"lineage_records": lin_copy
	}


static func from_dict(data: Dictionary) -> SeasonHegemonyService:
	var svc: SeasonHegemonyService = SeasonHegemonyService.new()
	var sh_v: Variant = data.get("season_history", [])
	if sh_v is Array:
		var sha: Array = sh_v
		for item: Variant in sha:
			if item is Dictionary:
				var d: Dictionary = item
				svc.season_history.append(d.duplicate(true))
	var lr_v: Variant = data.get("lineage_records", [])
	if lr_v is Array:
		var lra: Array = lr_v
		for item: Variant in lra:
			if item is Dictionary:
				var d2: Dictionary = item
				svc.lineage_records.append(d2.duplicate(true))
	return svc
