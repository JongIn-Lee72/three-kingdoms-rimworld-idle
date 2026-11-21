class_name RegionalMarket
extends RefCounted

const COMMODITIES: Array[String] = ["GRAIN", "IRON", "WOOD", "HORSES", "HERBS_WINE", "WEAPONS"]
const DEFAULT_BASE_PRICES_BP: Dictionary = {
	"GRAIN": 1000,
	"IRON": 2000,
	"WOOD": 1500,
	"HORSES": 4000,
	"HERBS_WINE": 2500,
	"WEAPONS": 3500
}
const DEFAULT_AMM_RESERVES: Dictionary = {
	"GRAIN": 20000,
	"IRON": 5000,
	"WOOD": 8000,
	"HORSES": 1500,
	"HERBS_WINE": 2500,
	"WEAPONS": 2000
}

var node_markets: Dictionary = {}
var orders: Dictionary = {}
var _next_order_seq: int = 1
var trade_history: Array[Dictionary] = []


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


func _init(world_graph: WorldGraph = null) -> void:
	node_markets.clear()
	orders.clear()
	_next_order_seq = 1
	trade_history.clear()
	if world_graph != null:
		init_from_world_graph(world_graph)


func init_from_world_graph(world_graph: WorldGraph) -> void:
	if world_graph == null:
		return
	for nid: String in world_graph.get_node_ids():
		var nd: Dictionary = world_graph.get_node(nid)
		var reserves_var: Variant = nd.get("amm_reserves", {})
		var res_d: Dictionary = reserves_var if reserves_var is Dictionary else {}
		var grain_bp: int = clampi(_to_int(nd.get("grain_price_bp", 1000), 1000), 100, 100000)
		var iron_bp: int = clampi(_to_int(nd.get("iron_price_bp", 2000), 2000), 100, 100000)
		var grain_res: int = maxi(100, _to_int(res_d.get("grain", 20000), 20000))
		var iron_res: int = maxi(100, _to_int(res_d.get("iron", 5000), 5000))
		var wood_res: int = maxi(100, _to_int(res_d.get("wood", 8000), 8000))
		var horse_res: int = maxi(100, _to_int(res_d.get("horse", 1500), 1500))
		var silk_res: int = maxi(100, _to_int(res_d.get("silk", 2500), 2500))
		var weapon_res: int = maxi(100, _to_int(res_d.get("weapons", 2000), 2000))

		var prices: Dictionary = {
			"GRAIN": grain_bp,
			"IRON": iron_bp,
			"WOOD": 1500,
			"HORSES": 4000,
			"HERBS_WINE": 2500,
			"WEAPONS": 3500
		}
		var pools: Dictionary = {}
		var res_map: Dictionary = {
			"GRAIN": grain_res,
			"IRON": iron_res,
			"WOOD": wood_res,
			"HORSES": horse_res,
			"HERBS_WINE": silk_res,
			"WEAPONS": weapon_res
		}
		for c: String in COMMODITIES:
			var r_qty: int = _to_int(res_map[c], 2000)
			var p_bp: int = _to_int(prices[c], 1000)
			@warning_ignore("integer_division")
			var coin_res: int = maxi(10000, (r_qty * p_bp) / 1000)
			pools[c] = {
				"commodity_reserve": r_qty,
				"coin_reserve": coin_res,
				"k_product": r_qty * coin_res,
				"price_bp": p_bp
			}
		node_markets[nid] = pools


func _ensure_node_market(node_id: String) -> Dictionary:
	if not node_markets.has(node_id):
		var pools: Dictionary = {}
		for c: String in COMMODITIES:
			var r_qty: int = _to_int(DEFAULT_AMM_RESERVES[c], 2000)
			var p_bp: int = _to_int(DEFAULT_BASE_PRICES_BP[c], 1000)
			@warning_ignore("integer_division")
			var coin_res: int = maxi(10000, (r_qty * p_bp) / 1000)
			pools[c] = {
				"commodity_reserve": r_qty,
				"coin_reserve": coin_res,
				"k_product": r_qty * coin_res,
				"price_bp": p_bp
			}
		node_markets[node_id] = pools
	var v: Variant = node_markets[node_id]
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func get_node_price_bp(node_id: String, commodity: String) -> int:
	if not COMMODITIES.has(commodity):
		return 1000
	var pools: Dictionary = _ensure_node_market(node_id)
	var p_var: Variant = pools.get(commodity, {})
	if p_var is Dictionary:
		var pd: Dictionary = p_var
		return clampi(_to_int(pd.get("price_bp", 1000), 1000), 100, 100000)
	return 1000


func get_amm_pool(node_id: String, commodity: String) -> Dictionary:
	if not COMMODITIES.has(commodity):
		return {}
	var pools: Dictionary = _ensure_node_market(node_id)
	var p_var: Variant = pools.get(commodity, {})
	if p_var is Dictionary:
		var pd: Dictionary = p_var
		return pd.duplicate(true)
	return {}


func set_amm_pool(node_id: String, commodity: String, commodity_reserve: int, coin_reserve: int) -> void:
	if not COMMODITIES.has(commodity):
		return
	var pools: Dictionary = _ensure_node_market(node_id)
	var cr: int = maxi(10, commodity_reserve)
	var cor: int = maxi(100, coin_reserve)
	@warning_ignore("integer_division")
	var spot_bp: int = clampi((cor * 1000) / cr, 100, 100000)
	pools[commodity] = {
		"commodity_reserve": cr,
		"coin_reserve": cor,
		"k_product": cr * cor,
		"price_bp": spot_bp
	}


func get_order(order_id: String) -> Dictionary:
	var v: Variant = orders.get(order_id, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d.duplicate(true)
	return {}


func place_order(
	node_id: String,
	player_id: String,
	commodity: String,
	side: String,
	price_bp: int,
	qty: int,
	tick_id: int
) -> Dictionary:
	if node_id.is_empty() or player_id.is_empty():
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Missing node_id or player_id"}
	if not COMMODITIES.has(commodity):
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid commodity: " + commodity}
	if side != "BID" and side != "ASK":
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Side must be BID or ASK"}
	if price_bp < 100 or price_bp > 100000 or qty <= 0:
		return {"ok": false, "error_code": DtoSchemas.ERR_SCHEMA, "reason": "Invalid price_bp or qty"}

	var _pools: Dictionary = _ensure_node_market(node_id)
	var seq: int = _next_order_seq
	_next_order_seq += 1
	var oid: String = "ord_%06d" % seq

	var order_rec: Dictionary = {
		"order_id": oid,
		"seq": seq,
		"node_id": node_id,
		"player_id": player_id,
		"commodity": commodity,
		"side": side,
		"price_bp": price_bp,
		"quantity": qty,
		"filled_quantity": 0,
		"created_tick": maxi(0, tick_id),
		"status": "OPEN"
	}
	orders[oid] = order_rec
	return {"ok": true, "error_code": DtoSchemas.ERR_OK, "order": order_rec.duplicate(true)}


func cancel_order(order_id: String, player_id: String) -> Dictionary:
	if not orders.has(order_id):
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Unknown order_id"}
	var ord: Dictionary = orders[order_id]
	if str(ord.get("player_id", "")) != player_id:
		return {"ok": false, "error_code": DtoSchemas.ERR_UNAUTHORIZED, "reason": "Order owned by another player"}
	if str(ord.get("status", "")) != "OPEN":
		return {"ok": false, "error_code": DtoSchemas.ERR_INVALID_STATE, "reason": "Order not OPEN"}
	ord["status"] = "CANCELLED"
	return {"ok": true, "error_code": DtoSchemas.ERR_OK, "order": ord.duplicate(true)}


static func _compare_bids(a: Dictionary, b: Dictionary) -> bool:
	var pa: int = _to_int(a.get("price_bp", 0), 0)
	var pb: int = _to_int(b.get("price_bp", 0), 0)
	if pa != pb:
		return pa > pb
	var ta: int = _to_int(a.get("created_tick", 0), 0)
	var tb: int = _to_int(b.get("created_tick", 0), 0)
	if ta != tb:
		return ta < tb
	return _to_int(a.get("seq", 0), 0) < _to_int(b.get("seq", 0), 0)


static func _compare_asks(a: Dictionary, b: Dictionary) -> bool:
	var pa: int = _to_int(a.get("price_bp", 0), 0)
	var pb: int = _to_int(b.get("price_bp", 0), 0)
	if pa != pb:
		return pa < pb
	var ta: int = _to_int(a.get("created_tick", 0), 0)
	var tb: int = _to_int(b.get("created_tick", 0), 0)
	if ta != tb:
		return ta < tb
	return _to_int(a.get("seq", 0), 0) < _to_int(b.get("seq", 0), 0)


func _execute_amm_buy(pool: Dictionary, max_qty: int, limit_price_bp: int) -> Dictionary:
	var comm_res: int = maxi(2, _to_int(pool.get("commodity_reserve", 1000), 1000))
	var coin_res: int = maxi(100, _to_int(pool.get("coin_reserve", 1000000), 1000000))
	var k_prod: int = _to_int(pool.get("k_product", comm_res * coin_res), comm_res * coin_res)

	var buy_qty: int = mini(max_qty, comm_res - 1)
	if buy_qty <= 0:
		return {"filled": 0, "coin_cost": 0, "exec_price_bp": _to_int(pool.get("price_bp", 1000), 1000)}

	# Binary search / reduce buy_qty if marginal average price > limit_price_bp
	while buy_qty > 0:
		var new_comm: int = comm_res - buy_qty
		@warning_ignore("integer_division")
		var new_coin: int = (k_prod + new_comm - 1) / new_comm
		var coin_cost: int = maxi(1, new_coin - coin_res)
		@warning_ignore("integer_division")
		var avg_price_bp: int = (coin_cost * 1000) / buy_qty
		if avg_price_bp <= limit_price_bp:
			pool["commodity_reserve"] = new_comm
			pool["coin_reserve"] = new_coin
			@warning_ignore("integer_division")
			pool["price_bp"] = clampi((new_coin * 1000) / new_comm, 100, 100000)
			return {"filled": buy_qty, "coin_cost": coin_cost, "exec_price_bp": avg_price_bp}
		@warning_ignore("integer_division")
		buy_qty = buy_qty / 2

	return {"filled": 0, "coin_cost": 0, "exec_price_bp": _to_int(pool.get("price_bp", 1000), 1000)}


func _execute_amm_sell(pool: Dictionary, max_qty: int, limit_price_bp: int) -> Dictionary:
	var comm_res: int = maxi(1, _to_int(pool.get("commodity_reserve", 1000), 1000))
	var coin_res: int = maxi(100, _to_int(pool.get("coin_reserve", 1000000), 1000000))
	var k_prod: int = _to_int(pool.get("k_product", comm_res * coin_res), comm_res * coin_res)

	var sell_qty: int = max_qty
	while sell_qty > 0:
		var new_comm: int = comm_res + sell_qty
		@warning_ignore("integer_division")
		var new_coin: int = maxi(1, k_prod / new_comm)
		var coin_out: int = maxi(0, coin_res - new_coin)
		@warning_ignore("integer_division")
		var avg_price_bp: int = (coin_out * 1000) / sell_qty
		if avg_price_bp >= limit_price_bp and coin_out > 0:
			pool["commodity_reserve"] = new_comm
			pool["coin_reserve"] = new_coin
			@warning_ignore("integer_division")
			pool["price_bp"] = clampi((new_coin * 1000) / new_comm, 100, 100000)
			return {"filled": sell_qty, "coin_out": coin_out, "exec_price_bp": avg_price_bp}
		@warning_ignore("integer_division")
		sell_qty = sell_qty / 2

	return {"filled": 0, "coin_out": 0, "exec_price_bp": _to_int(pool.get("price_bp", 1000), 1000)}


func match_node_orders(node_id: String, tick_id: int) -> Dictionary:
	var pools: Dictionary = _ensure_node_market(node_id)
	var trades: Array[Dictionary] = []
	var total_matched_qty: int = 0

	for comm: String in COMMODITIES:
		var bids: Array[Dictionary] = []
		var asks: Array[Dictionary] = []
		var oids: Array[String] = []
		for k: Variant in orders.keys():
			oids.append(str(k))
		oids.sort()

		for oid: String in oids:
			var ord: Dictionary = orders[oid]
			if str(ord.get("node_id", "")) != node_id:
				continue
			if str(ord.get("commodity", "")) != comm:
				continue
			if str(ord.get("status", "")) != "OPEN":
				continue
			var rem: int = _to_int(ord.get("quantity", 0), 0) - _to_int(ord.get("filled_quantity", 0), 0)
			if rem <= 0:
				ord["status"] = "FILLED"
				continue
			if str(ord.get("side", "")) == "BID":
				bids.append(ord)
			else:
				asks.append(ord)

		bids.sort_custom(Callable(RegionalMarket, "_compare_bids"))
		asks.sort_custom(Callable(RegionalMarket, "_compare_asks"))

		var pool: Dictionary = pools[comm]
		var bi: int = 0
		var ai: int = 0

		# Step 1: Price-time priority P2P matching
		while bi < bids.size() and ai < asks.size():
			var b_ord: Dictionary = bids[bi]
			var a_ord: Dictionary = asks[ai]
			var b_price: int = _to_int(b_ord.get("price_bp", 0), 0)
			var a_price: int = _to_int(a_ord.get("price_bp", 0), 0)
			if b_price < a_price:
				break

			var b_rem: int = _to_int(b_ord["quantity"], 0) - _to_int(b_ord["filled_quantity"], 0)
			var a_rem: int = _to_int(a_ord["quantity"], 0) - _to_int(a_ord["filled_quantity"], 0)
			var fill: int = mini(b_rem, a_rem)
			if fill <= 0:
				break

			# Execution price favors resting earlier order (or midpoint)
			var exec_price_bp: int = a_price if _to_int(a_ord["seq"], 0) < _to_int(b_ord["seq"], 0) else b_price
			b_ord["filled_quantity"] = _to_int(b_ord["filled_quantity"], 0) + fill
			a_ord["filled_quantity"] = _to_int(a_ord["filled_quantity"], 0) + fill
			if _to_int(b_ord["filled_quantity"], 0) >= _to_int(b_ord["quantity"], 0):
				b_ord["status"] = "FILLED"
				bi += 1
			if _to_int(a_ord["filled_quantity"], 0) >= _to_int(a_ord["quantity"], 0):
				a_ord["status"] = "FILLED"
				ai += 1

			pool["price_bp"] = clampi(exec_price_bp, 100, 100000)
			total_matched_qty += fill
			var tr: Dictionary = {
				"tick_id": tick_id,
				"node_id": node_id,
				"commodity": comm,
				"type": "BOOK_MATCH",
				"bid_order_id": str(b_ord["order_id"]),
				"ask_order_id": str(a_ord["order_id"]),
				"quantity": fill,
				"price_bp": exec_price_bp
			}
			trades.append(tr)
			trade_history.append(tr)

		# Step 2: AMM Baseline Reserve liquidity fill for remaining open orders crossing AMM spot
		for rem_bi: int in range(bi, bids.size()):
			var b_ord: Dictionary = bids[rem_bi]
			var rem_b: int = _to_int(b_ord["quantity"], 0) - _to_int(b_ord["filled_quantity"], 0)
			if rem_b <= 0:
				continue
			var b_limit: int = _to_int(b_ord["price_bp"], 0)
			var spot_b: int = _to_int(pool.get("price_bp", 1000), 1000)
			if b_limit >= spot_b:
				var amm_res_b: Dictionary = _execute_amm_buy(pool, rem_b, b_limit)
				var filled_b: int = _to_int(amm_res_b.get("filled", 0), 0)
				if filled_b > 0:
					b_ord["filled_quantity"] = _to_int(b_ord["filled_quantity"], 0) + filled_b
					if _to_int(b_ord["filled_quantity"], 0) >= _to_int(b_ord["quantity"], 0):
						b_ord["status"] = "FILLED"
					total_matched_qty += filled_b
					var tr_amm_b: Dictionary = {
						"tick_id": tick_id,
						"node_id": node_id,
						"commodity": comm,
						"type": "AMM_BUY",
						"bid_order_id": str(b_ord["order_id"]),
						"quantity": filled_b,
						"price_bp": _to_int(amm_res_b.get("exec_price_bp", spot_b), spot_b),
						"coin_cost": _to_int(amm_res_b.get("coin_cost", 0), 0)
					}
					trades.append(tr_amm_b)
					trade_history.append(tr_amm_b)

		for rem_ai: int in range(ai, asks.size()):
			var a_ord: Dictionary = asks[rem_ai]
			var rem_a: int = _to_int(a_ord["quantity"], 0) - _to_int(a_ord["filled_quantity"], 0)
			if rem_a <= 0:
				continue
			var a_limit: int = _to_int(a_ord["price_bp"], 0)
			var spot_a: int = _to_int(pool.get("price_bp", 1000), 1000)
			if a_limit <= spot_a:
				var amm_res_a: Dictionary = _execute_amm_sell(pool, rem_a, a_limit)
				var filled_a: int = _to_int(amm_res_a.get("filled", 0), 0)
				if filled_a > 0:
					a_ord["filled_quantity"] = _to_int(a_ord["filled_quantity"], 0) + filled_a
					if _to_int(a_ord["filled_quantity"], 0) >= _to_int(a_ord["quantity"], 0):
						a_ord["status"] = "FILLED"
					total_matched_qty += filled_a
					var tr_amm_a: Dictionary = {
						"tick_id": tick_id,
						"node_id": node_id,
						"commodity": comm,
						"type": "AMM_SELL",
						"ask_order_id": str(a_ord["order_id"]),
						"quantity": filled_a,
						"price_bp": _to_int(amm_res_a.get("exec_price_bp", spot_a), spot_a),
						"coin_out": _to_int(amm_res_a.get("coin_out", 0), 0)
					}
					trades.append(tr_amm_a)
					trade_history.append(tr_amm_a)

	var updated_prices: Dictionary = {}
	for c: String in COMMODITIES:
		updated_prices[c] = get_node_price_bp(node_id, c)

	return {
		"node_id": node_id,
		"tick_id": tick_id,
		"matched_qty": total_matched_qty,
		"trades": trades,
		"prices_bp": updated_prices
	}


func settle_caravan_trade(caravan: Dictionary, node_id: String, tick_id: int) -> Dictionary:
	var pools: Dictionary = _ensure_node_market(node_id)
	var cargo_var: Variant = caravan.get("cargo", {})
	var cargo: Dictionary = cargo_var if cargo_var is Dictionary else {}

	var total_coin_earned: int = 0
	var sold_items: Dictionary = {}

	for c: String in COMMODITIES:
		var qty: int = maxi(0, _to_int(cargo.get(c, 0), 0))
		if qty <= 0:
			continue
		var pool: Dictionary = pools[c]
		var res_sell: Dictionary = _execute_amm_sell(pool, qty, 100)
		var filled: int = _to_int(res_sell.get("filled", 0), 0)
		var coin_out: int = _to_int(res_sell.get("coin_out", 0), 0)
		if filled > 0:
			cargo[c] = maxi(0, qty - filled)
			total_coin_earned += coin_out
			sold_items[c] = {"quantity": filled, "coin_earned": coin_out}
			trade_history.append({
				"tick_id": tick_id,
				"node_id": node_id,
				"commodity": c,
				"type": "CARAVAN_SETTLE",
				"entity_id": str(caravan.get("entity_id", "")),
				"quantity": filled,
				"coin_out": coin_out,
				"price_bp": get_node_price_bp(node_id, c)
			})

	caravan["carried_coin"] = _to_int(caravan.get("carried_coin", 0), 0) + total_coin_earned
	return {
		"node_id": node_id,
		"tick_id": tick_id,
		"coin_earned": total_coin_earned,
		"sold_items": sold_items,
		"updated_grain_price_bp": get_node_price_bp(node_id, "GRAIN"),
		"updated_iron_price_bp": get_node_price_bp(node_id, "IRON")
	}


func sync_prices_to_world_graph(world_graph: WorldGraph) -> void:
	if world_graph == null:
		return
	for nid: String in world_graph.get_node_ids():
		if node_markets.has(nid):
			world_graph.update_node_prices(
				nid,
				get_node_price_bp(nid, "GRAIN"),
				get_node_price_bp(nid, "IRON")
			)


func to_dict() -> Dictionary:
	var nm_copy: Dictionary = {}
	var nids: Array[String] = []
	for k: Variant in node_markets.keys():
		nids.append(str(k))
	nids.sort()
	for nid: String in nids:
		var pools_v: Variant = node_markets[nid]
		if pools_v is Dictionary:
			var pools_d: Dictionary = pools_v
			nm_copy[nid] = pools_d.duplicate(true)

	var orders_arr: Array[Dictionary] = []
	var oids: Array[String] = []
	for ok: Variant in orders.keys():
		oids.append(str(ok))
	oids.sort()
	for oid: String in oids:
		orders_arr.append(get_order(oid))

	var hist_copy: Array[Dictionary] = []
	for th: Dictionary in trade_history:
		hist_copy.append(th.duplicate(true))

	return {
		"next_order_seq": _next_order_seq,
		"node_markets": nm_copy,
		"orders": orders_arr,
		"trade_history": hist_copy
	}


static func from_dict(data: Dictionary) -> RegionalMarket:
	var m: RegionalMarket = RegionalMarket.new()
	m._next_order_seq = maxi(1, _to_int(data.get("next_order_seq", 1), 1))

	var nm_var: Variant = data.get("node_markets", {})
	if nm_var is Dictionary:
		var nm_d: Dictionary = nm_var
		for nid_v: Variant in nm_d.keys():
			var nid: String = str(nid_v)
			var pools_v: Variant = nm_d[nid_v]
			if pools_v is Dictionary:
				var pools_d: Dictionary = pools_v
				var clean_pools: Dictionary = {}
				for c: String in COMMODITIES:
					var pv: Variant = pools_d.get(c, {})
					if pv is Dictionary:
						var pd: Dictionary = pv
						var cr: int = maxi(10, _to_int(pd.get("commodity_reserve", 2000), 2000))
						var cor: int = maxi(100, _to_int(pd.get("coin_reserve", 2000000), 2000000))
						clean_pools[c] = {
							"commodity_reserve": cr,
							"coin_reserve": cor,
							"k_product": _to_int(pd.get("k_product", cr * cor), cr * cor),
							"price_bp": clampi(_to_int(pd.get("price_bp", 1000), 1000), 100, 100000)
						}
				m.node_markets[nid] = clean_pools

	var ord_var: Variant = data.get("orders", [])
	if ord_var is Array:
		var ord_arr: Array = ord_var
		for item: Variant in ord_arr:
			if item is Dictionary:
				var od: Dictionary = item
				var oid: String = str(od.get("order_id", ""))
				if not oid.is_empty():
					m.orders[oid] = od.duplicate(true)

	var hist_var: Variant = data.get("trade_history", [])
	if hist_var is Array:
		var hist_arr: Array = hist_var
		for h_item: Variant in hist_arr:
			if h_item is Dictionary:
				var hd: Dictionary = h_item
				m.trade_history.append(hd.duplicate(true))

	return m
