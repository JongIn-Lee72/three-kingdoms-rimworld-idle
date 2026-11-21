class_name InterestDeltaManager
extends RefCounted

var peer_subscriptions: Dictionary = {}   # peer_key -> Array[String]
var peer_channel_cache: Dictionary = {}   # peer_key -> { channel_name -> Dictionary }


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


func _init() -> void:
	peer_subscriptions.clear()
	peer_channel_cache.clear()


func register_peer(peer_id: Variant, default_channels: Array[String] = []) -> void:
	var pkey: String = str(peer_id)
	if pkey.is_empty():
		return
	var chans: Array[String] = []
	if not default_channels.has(DtoSchemas.CHAN_GLOBAL_MACRO):
		chans.append(DtoSchemas.CHAN_GLOBAL_MACRO)
	for c: String in default_channels:
		if not c.is_empty() and not chans.has(c):
			chans.append(c)
	peer_subscriptions[pkey] = chans
	if not peer_channel_cache.has(pkey):
		var empty_cache: Dictionary = {}
		peer_channel_cache[pkey] = empty_cache


func unregister_peer(peer_id: Variant) -> void:
	var pkey: String = str(peer_id)
	var _e1: bool = peer_subscriptions.erase(pkey)
	var _e2: bool = peer_channel_cache.erase(pkey)


func subscribe(peer_id: Variant, channel: String) -> bool:
	if channel.is_empty():
		return false
	var pkey: String = str(peer_id)
	if not peer_subscriptions.has(pkey):
		register_peer(pkey)
	var list_var: Variant = peer_subscriptions[pkey]
	if list_var is Array:
		var list: Array = list_var
		if not list.has(channel):
			list.append(channel)
		return true
	return false


func unsubscribe(peer_id: Variant, channel: String) -> bool:
	var pkey: String = str(peer_id)
	if not peer_subscriptions.has(pkey):
		return false
	var list_var: Variant = peer_subscriptions[pkey]
	if list_var is Array:
		var list: Array = list_var
		list.erase(channel)
	if peer_channel_cache.has(pkey):
		var c_var: Variant = peer_channel_cache[pkey]
		if c_var is Dictionary:
			var c_dict: Dictionary = c_var
			var _er: bool = c_dict.erase(channel)
	return true


func get_subscriptions(peer_id: Variant) -> Array[String]:
	var pkey: String = str(peer_id)
	var out: Array[String] = []
	if not peer_subscriptions.has(pkey):
		return out
	var list_var: Variant = peer_subscriptions[pkey]
	if list_var is Array:
		var list: Array = list_var
		for item: Variant in list:
			out.append(str(item))
	out.sort()
	return out


func is_manor_observed(manor_id: String) -> bool:
	var target_chan: String = DtoSchemas.CHAN_MANOR + ":" + manor_id
	for k: Variant in peer_subscriptions.keys():
		var list_var: Variant = peer_subscriptions[k]
		if list_var is Array:
			var list: Array = list_var
			if list.has(target_chan):
				return true
	return false


func sync_manor_lods(manors: Dictionary, online_players: Dictionary) -> void:
	for pid_v: Variant in manors.keys():
		var pid: String = str(pid_v)
		var m_v: Variant = manors[pid_v]
		if not (m_v is ManorState):
			continue
		var manor: ManorState = m_v
		var is_online: bool = _to_bool(online_players.get(pid, false), false)
		if is_online or manor.raid_defense_active or is_manor_observed(manor.manor_id):
			ManorSimulator.promote_to_lod0(manor)
		else:
			ManorSimulator.demote_to_lod1(manor)


func _diff_entity_dict(prev_map: Dictionary, cur_map: Dictionary) -> Dictionary:
	var updates: Dictionary = {}
	var deletions: Array[String] = []

	var cur_ids: Array[String] = []
	for k: Variant in cur_map.keys():
		cur_ids.append(str(k))
	cur_ids.sort()

	for eid: String in cur_ids:
		var cur_ent_v: Variant = cur_map[eid]
		if not (cur_ent_v is Dictionary):
			continue
		var cur_ent: Dictionary = cur_ent_v
		if not prev_map.has(eid):
			updates[eid] = cur_ent.duplicate(true)
			continue
		var prev_ent_v: Variant = prev_map[eid]
		if not (prev_ent_v is Dictionary):
			updates[eid] = cur_ent.duplicate(true)
			continue
		var prev_ent: Dictionary = prev_ent_v
		var changed_fields: Dictionary = {}
		var fkeys: Array[String] = []
		for fk: Variant in cur_ent.keys():
			fkeys.append(str(fk))
		fkeys.sort()
		for fk: String in fkeys:
			var c_val: Variant = cur_ent[fk]
			if not prev_ent.has(fk) or StateHasher.canonical_json(prev_ent[fk]) != StateHasher.canonical_json(c_val):
				if c_val is Dictionary:
					var cd: Dictionary = c_val
					changed_fields[fk] = cd.duplicate(true)
				elif c_val is Array:
					var ca: Array = c_val
					changed_fields[fk] = ca.duplicate(true)
				else:
					changed_fields[fk] = c_val
		if not changed_fields.is_empty():
			updates[eid] = changed_fields

	var prev_ids: Array[String] = []
	for pk: Variant in prev_map.keys():
		prev_ids.append(str(pk))
	prev_ids.sort()
	for pid: String in prev_ids:
		if not cur_map.has(pid):
			deletions.append(pid)

	return {"updates": updates, "deletions": deletions}


func _diff_flat_dict(prev_d: Dictionary, cur_d: Dictionary) -> Dictionary:
	var changed: Dictionary = {}
	var keys: Array[String] = []
	for k: Variant in cur_d.keys():
		keys.append(str(k))
	keys.sort()
	for k: String in keys:
		if not prev_d.has(k) or StateHasher.canonical_json(prev_d[k]) != StateHasher.canonical_json(cur_d[k]):
			var cv: Variant = cur_d[k]
			if cv is Dictionary:
				var cd: Dictionary = cv
				changed[k] = cd.duplicate(true)
			elif cv is Array:
				var ca: Array = cv
				changed[k] = ca.duplicate(true)
			else:
				changed[k] = cv
	return changed


func _build_global_macro_snapshot(server_state: Dictionary) -> Dictionary:
	var nodes_snap: Dictionary = {}
	var wg_v: Variant = server_state.get("world_graph", null)
	if wg_v is WorldGraph:
		var wg: WorldGraph = wg_v
		for nid: String in wg.get_node_ids():
			var nd: Dictionary = wg.get_node(nid)
			nodes_snap[nid] = {
				"owner_faction_id": str(nd.get("owner_faction_id", "NEUTRAL")),
				"governor_player_id": str(nd.get("governor_player_id", "")),
				"fortification_hp": _to_int(nd.get("fortification_hp", 0), 0),
				"security_bp": _to_int(nd.get("security_bp", 7000), 7000),
				"bandit_pressure_bp": _to_int(nd.get("bandit_pressure_bp", 0), 0),
				"tax_rate_bp": _to_int(nd.get("tax_rate_bp", 1000), 1000),
				"grain_price_bp": _to_int(nd.get("grain_price_bp", 1000), 1000),
				"iron_price_bp": _to_int(nd.get("iron_price_bp", 2000), 2000)
			}

	var armies_snap: Dictionary = {}
	var acm_v: Variant = server_state.get("army_manager", null)
	if acm_v is ArmyCaravanManager:
		var acm: ArmyCaravanManager = acm_v
		for eid: String in acm.get_entity_ids():
			var ent: Dictionary = acm.get_entity(eid)
			armies_snap[eid] = {
				"unit_type": str(ent.get("unit_type", "ARMY")),
				"faction_id": str(ent.get("faction_id", "NEUTRAL")),
				"current_node_id": str(ent.get("current_node_id", "")),
				"edge_id": str(ent.get("current_edge_id", "")),
				"progress_pm": _to_int(ent.get("edge_progress_pm", 0), 0),
				"troop_count": _to_int(ent.get("troop_count", 0), 0),
				"morale_bp": _to_int(ent.get("morale_bp", 8000), 8000),
				"status": str(ent.get("status", "MARCHING"))
			}

	return {"nodes": nodes_snap, "armies": armies_snap}


func _build_faction_snapshot(faction_id: String, server_state: Dictionary) -> Dictionary:
	var fm_v: Variant = server_state.get("faction_manager", null)
	var dte_v: Variant = server_state.get("diplomacy", null)
	var sbr_v: Variant = server_state.get("siege_resolver", null)
	var fac_data: Dictionary = {}
	var members_data: Dictionary = {}
	if fm_v is FactionManager:
		var fm: FactionManager = fm_v
		if fm.has_faction(faction_id):
			var fac: Dictionary = fm.get_faction(faction_id)
			fac_data = {
				"treasury_grain": _to_int(fac.get("treasury_grain", 0), 0),
				"treasury_coin": _to_int(fac.get("treasury_coin", 0), 0),
				"prestige": _to_int(fac.get("prestige", 0), 0),
				"royal_rank": str(fac.get("royal_rank", "GOVERNOR_INSPECTOR")),
				"oathbreaker_until_tick": _to_int(fac.get("oathbreaker_until_tick", 0), 0)
			}
			for pid: String in fm.get_faction_members(faction_id):
				var prof: Dictionary = fm.get_player_profile(pid)
				members_data[pid] = {
					"role_tier": str(prof.get("role_tier", "FREE_OFFICER")),
					"court_rank": str(prof.get("court_rank", "NONE")),
					"war_merit": _to_int(prof.get("war_merit", 0), 0)
				}

	var treaties_snap: Dictionary = {}
	if dte_v is DiplomacyTreatyEngine:
		var dte: DiplomacyTreatyEngine = dte_v
		for tid: String in dte.get_treaty_ids():
			var tr: Dictionary = dte.get_treaty(tid)
			if str(tr.get("faction_a_id", "")) == faction_id or str(tr.get("faction_b_id", "")) == faction_id:
				treaties_snap[tid] = {
					"status": str(tr.get("status", "ACTIVE")),
					"treaty_type": str(tr.get("treaty_type", "")),
					"expires_tick": _to_int(tr.get("expires_tick", 0), 0)
				}

	var rallies_snap: Dictionary = {}
	if sbr_v is SiegeBattleResolver:
		var sbr: SiegeBattleResolver = sbr_v
		for rid: String in sbr.get_rally_ids():
			var ral: Dictionary = sbr.get_rally(rid)
			if str(ral.get("leader_faction_id", "")) == faction_id:
				var parts_v: Variant = ral.get("participants", [])
				var part_cnt: int = 0
				if parts_v is Array:
					var parts_a: Array = parts_v
					part_cnt = parts_a.size()
				rallies_snap[rid] = {
					"status": str(ral.get("status", "RALLYING")),
					"target_node_id": str(ral.get("target_node_id", "")),
					"participant_count": part_cnt
				}

	return {
		"faction": fac_data,
		"members": members_data,
		"treaties": treaties_snap,
		"rallies": rallies_snap
	}


func _build_node_snapshot(node_id: String, server_state: Dictionary) -> Dictionary:
	var prices: Dictionary = {}
	var orders_snap: Dictionary = {}
	var rm_v: Variant = server_state.get("regional_market", null)
	if rm_v is RegionalMarket:
		var rm: RegionalMarket = rm_v
		for comm: String in RegionalMarket.COMMODITIES:
			prices[comm] = rm.get_node_price_bp(node_id, comm)
		var oids: Array[String] = []
		for ok: Variant in rm.orders.keys():
			oids.append(str(ok))
		oids.sort()
		for oid: String in oids:
			var ord: Dictionary = rm.get_order(oid)
			if str(ord.get("node_id", "")) == node_id and str(ord.get("status", "")) == "OPEN":
				orders_snap[oid] = {
					"commodity": str(ord.get("commodity", "")),
					"side": str(ord.get("side", "")),
					"price_bp": _to_int(ord.get("price_bp", 0), 0),
					"remaining_qty": _to_int(ord.get("quantity", 0), 0) - _to_int(ord.get("filled_quantity", 0), 0)
				}
	return {"prices": prices, "orders": orders_snap}


func _find_manor_by_id(manor_id: String, server_state: Dictionary) -> ManorState:
	var manors_v: Variant = server_state.get("manors", {})
	if manors_v is Dictionary:
		var md: Dictionary = manors_v
		for k: Variant in md.keys():
			var mv: Variant = md[k]
			if mv is ManorState:
				var m: ManorState = mv
				if m.manor_id == manor_id:
					return m
	return null


func _build_manor_snapshot(manor_id: String, server_state: Dictionary) -> Dictionary:
	var manor: ManorState = _find_manor_by_id(manor_id, server_state)
	if manor == null:
		return {}
	var stockpile: Dictionary = {}
	for rk: String in DtoSchemas.RESOURCE_KEYS:
		stockpile[rk] = manor.get_resource(rk)
	var pawns_snap: Dictionary = {}
	for p: PawnEntity in manor.pawns:
		pawns_snap[p.pawn_id] = {
			"x": p.grid_x,
			"y": p.grid_y,
			"job": p.current_job,
			"progress_pm": p.job_progress_pm,
			"state": p.state,
			"health_state": p.health_state,
			"food_bp": p.get_need("FOOD"),
			"rest_bp": p.get_need("REST"),
			"morale_bp": p.get_need("MORALE"),
			"loyalty_bp": p.get_need("LOYALTY"),
			"mood": p.mood,
			"mental_state": p.mental_state
		}
	return {
		"meta": {
			"lod": manor.current_lod,
			"wall_hp": manor.wall_hp,
			"household_troops": manor.household_troops,
			"truce_shield_until_tick": manor.truce_shield_until_tick
		},
		"stockpile": stockpile,
		"pawns": pawns_snap
	}


func build_tick_delta_for_peer(
	peer_id: Variant,
	server_state: Dictionary,
	tick_events: Array[Dictionary] = []
) -> Dictionary:
	var pkey: String = str(peer_id)
	if not peer_subscriptions.has(pkey):
		register_peer(pkey)

	var cache_var: Variant = peer_channel_cache.get(pkey, {})
	var peer_cache: Dictionary = cache_var if cache_var is Dictionary else {}
	peer_channel_cache[pkey] = peer_cache

	var channels_delta: Dictionary = {}
	for chan: String in get_subscriptions(pkey):
		if chan == DtoSchemas.CHAN_GLOBAL_MACRO:
			var cur_g: Dictionary = _build_global_macro_snapshot(server_state)
			var prev_g_v: Variant = peer_cache.get(chan, {})
			var prev_g: Dictionary = prev_g_v if prev_g_v is Dictionary else {}
			var prev_nodes: Dictionary = prev_g.get("nodes", {}) if prev_g.get("nodes", {}) is Dictionary else {}
			var prev_armies: Dictionary = prev_g.get("armies", {}) if prev_g.get("armies", {}) is Dictionary else {}
			var cur_nodes: Dictionary = cur_g["nodes"]
			var cur_armies: Dictionary = cur_g["armies"]
			var diff_n: Dictionary = _diff_entity_dict(prev_nodes, cur_nodes)
			var diff_a: Dictionary = _diff_entity_dict(prev_armies, cur_armies)
			var chan_payload: Dictionary = {}
			var u_nodes: Dictionary = diff_n["updates"]
			var u_armies: Dictionary = diff_a["updates"]
			var d_armies: Array = diff_a["deletions"]
			if not u_nodes.is_empty():
				chan_payload["u_nodes"] = u_nodes
			if not u_armies.is_empty():
				chan_payload["u_armies"] = u_armies
			if not d_armies.is_empty():
				chan_payload["d_armies"] = d_armies
			if not chan_payload.is_empty():
				channels_delta[chan] = chan_payload
			peer_cache[chan] = cur_g

		elif chan.begins_with(DtoSchemas.CHAN_FACTION + ":"):
			var fid: String = chan.substr((DtoSchemas.CHAN_FACTION + ":").length())
			var cur_f: Dictionary = _build_faction_snapshot(fid, server_state)
			var prev_f_v: Variant = peer_cache.get(chan, {})
			var prev_f: Dictionary = prev_f_v if prev_f_v is Dictionary else {}
			var prev_fac: Dictionary = prev_f.get("faction", {}) if prev_f.get("faction", {}) is Dictionary else {}
			var prev_mem: Dictionary = prev_f.get("members", {}) if prev_f.get("members", {}) is Dictionary else {}
			var prev_trt: Dictionary = prev_f.get("treaties", {}) if prev_f.get("treaties", {}) is Dictionary else {}
			var prev_ral: Dictionary = prev_f.get("rallies", {}) if prev_f.get("rallies", {}) is Dictionary else {}
			var cf_fac_v: Variant = cur_f.get("faction", {})
			var cf_mem_v: Variant = cur_f.get("members", {})
			var cf_trt_v: Variant = cur_f.get("treaties", {})
			var cf_ral_v: Variant = cur_f.get("rallies", {})
			var cf_fac: Dictionary = cf_fac_v if cf_fac_v is Dictionary else {}
			var cf_mem: Dictionary = cf_mem_v if cf_mem_v is Dictionary else {}
			var cf_trt: Dictionary = cf_trt_v if cf_trt_v is Dictionary else {}
			var cf_ral: Dictionary = cf_ral_v if cf_ral_v is Dictionary else {}
			var df: Dictionary = _diff_flat_dict(prev_fac, cf_fac)
			var dm: Dictionary = _diff_entity_dict(prev_mem, cf_mem)
			var dt: Dictionary = _diff_entity_dict(prev_trt, cf_trt)
			var dr: Dictionary = _diff_entity_dict(prev_ral, cf_ral)
			var dm_upd_v: Variant = dm.get("updates", {})
			var dt_upd_v: Variant = dt.get("updates", {})
			var dr_upd_v: Variant = dr.get("updates", {})
			var dm_upd: Dictionary = dm_upd_v if dm_upd_v is Dictionary else {}
			var dt_upd: Dictionary = dt_upd_v if dt_upd_v is Dictionary else {}
			var dr_upd: Dictionary = dr_upd_v if dr_upd_v is Dictionary else {}
			var f_payload: Dictionary = {}
			if not df.is_empty():
				f_payload["u_faction"] = df
			if not dm_upd.is_empty():
				f_payload["u_members"] = dm_upd
			if not dt_upd.is_empty():
				f_payload["u_treaties"] = dt_upd
			if not dr_upd.is_empty():
				f_payload["u_rallies"] = dr_upd
			if not f_payload.is_empty():
				channels_delta[chan] = f_payload
			peer_cache[chan] = cur_f

		elif chan.begins_with(DtoSchemas.CHAN_NODE + ":"):
			var nid: String = chan.substr((DtoSchemas.CHAN_NODE + ":").length())
			var cur_nd: Dictionary = _build_node_snapshot(nid, server_state)
			var prev_nd_v: Variant = peer_cache.get(chan, {})
			var prev_nd: Dictionary = prev_nd_v if prev_nd_v is Dictionary else {}
			var prev_pr: Dictionary = prev_nd.get("prices", {}) if prev_nd.get("prices", {}) is Dictionary else {}
			var prev_ord: Dictionary = prev_nd.get("orders", {}) if prev_nd.get("orders", {}) is Dictionary else {}
			var cnd_pr_v: Variant = cur_nd.get("prices", {})
			var cnd_ord_v: Variant = cur_nd.get("orders", {})
			var cnd_pr: Dictionary = cnd_pr_v if cnd_pr_v is Dictionary else {}
			var cnd_ord: Dictionary = cnd_ord_v if cnd_ord_v is Dictionary else {}
			var dp: Dictionary = _diff_flat_dict(prev_pr, cnd_pr)
			var do: Dictionary = _diff_entity_dict(prev_ord, cnd_ord)
			var do_upd_v: Variant = do.get("updates", {})
			var do_del_v: Variant = do.get("deletions", [])
			var do_upd: Dictionary = do_upd_v if do_upd_v is Dictionary else {}
			var do_del: Array = do_del_v if do_del_v is Array else []
			var n_payload: Dictionary = {}
			if not dp.is_empty():
				n_payload["u_prices"] = dp
			if not do_upd.is_empty():
				n_payload["u_orders"] = do_upd
			if not do_del.is_empty():
				n_payload["d_orders"] = do_del
			if not n_payload.is_empty():
				channels_delta[chan] = n_payload
			peer_cache[chan] = cur_nd

		elif chan.begins_with(DtoSchemas.CHAN_MANOR + ":"):
			var mid: String = chan.substr((DtoSchemas.CHAN_MANOR + ":").length())
			var cur_m: Dictionary = _build_manor_snapshot(mid, server_state)
			if cur_m.is_empty():
				continue
			var prev_m_v: Variant = peer_cache.get(chan, {})
			var prev_m: Dictionary = prev_m_v if prev_m_v is Dictionary else {}
			var prev_meta: Dictionary = prev_m.get("meta", {}) if prev_m.get("meta", {}) is Dictionary else {}
			var prev_stock: Dictionary = prev_m.get("stockpile", {}) if prev_m.get("stockpile", {}) is Dictionary else {}
			var prev_pawns: Dictionary = prev_m.get("pawns", {}) if prev_m.get("pawns", {}) is Dictionary else {}
			var cm_meta_v: Variant = cur_m.get("meta", {})
			var cm_stock_v: Variant = cur_m.get("stockpile", {})
			var cm_pawns_v: Variant = cur_m.get("pawns", {})
			var cm_meta: Dictionary = cm_meta_v if cm_meta_v is Dictionary else {}
			var cm_stock: Dictionary = cm_stock_v if cm_stock_v is Dictionary else {}
			var cm_pawns: Dictionary = cm_pawns_v if cm_pawns_v is Dictionary else {}
			var d_meta: Dictionary = _diff_flat_dict(prev_meta, cm_meta)
			var d_stock: Dictionary = _diff_flat_dict(prev_stock, cm_stock)
			var d_pawns: Dictionary = _diff_entity_dict(prev_pawns, cm_pawns)
			var dp_upd_v: Variant = d_pawns.get("updates", {})
			var dp_del_v: Variant = d_pawns.get("deletions", [])
			var dp_upd: Dictionary = dp_upd_v if dp_upd_v is Dictionary else {}
			var dp_del: Array = dp_del_v if dp_del_v is Array else []
			var m_payload: Dictionary = {}
			if d_meta.has("lod"):
				m_payload["lod"] = d_meta["lod"]
			if not d_meta.is_empty():
				m_payload["u_meta"] = d_meta
			if not d_stock.is_empty():
				m_payload["u_stockpile"] = d_stock
			if not dp_upd.is_empty():
				m_payload["u_pawns"] = dp_upd
			if not dp_del.is_empty():
				m_payload["d_pawns"] = dp_del
			if not m_payload.is_empty():
				channels_delta[chan] = m_payload
			peer_cache[chan] = cur_m

	var clock_v: Variant = server_state.get("clock", null)
	var clock: SimClock = clock_v if clock_v is SimClock else SimClock.new(0)
	var ev_out: Array[Dictionary] = []
	for ev: Dictionary in tick_events:
		ev_out.append(ev.duplicate(true))

	return {
		"v": 1,
		"msg_type": DtoSchemas.MSG_TICK_DELTA,
		"tick_id": clock.current_tick_id,
		"macro_tick_id": clock.get_macro_tick_id(),
		"day_id": clock.get_day_id(),
		"season": clock.get_season(),
		"state_crc32": maxi(0, _to_int(server_state.get("state_crc32", 0), 0)),
		"channels": channels_delta,
		"events": ev_out
	}


func reset_peer_cache(peer_id: Variant) -> void:
	var pkey: String = str(peer_id)
	var empty_c: Dictionary = {}
	peer_channel_cache[pkey] = empty_c


func to_dict() -> Dictionary:
	var subs_copy: Dictionary = {}
	var pkeys: Array[String] = []
	for k: Variant in peer_subscriptions.keys():
		pkeys.append(str(k))
	pkeys.sort()
	for pk: String in pkeys:
		subs_copy[pk] = get_subscriptions(pk)
	return {"peer_subscriptions": subs_copy}


static func from_dict(data: Dictionary) -> InterestDeltaManager:
	var mgr: InterestDeltaManager = InterestDeltaManager.new()
	var sub_v: Variant = data.get("peer_subscriptions", {})
	if sub_v is Dictionary:
		var sd: Dictionary = sub_v
		for pk_v: Variant in sd.keys():
			var pk: String = str(pk_v)
			var arr_v: Variant = sd[pk_v]
			var chans: Array[String] = []
			if arr_v is Array:
				var arr: Array = arr_v
				for item: Variant in arr:
					chans.append(str(item))
			mgr.register_peer(pk, chans)
	return mgr
