class_name TestRegionalMarket
extends HarnessTestCase


func _as_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		var iv: int = v
		return iv
	if v is float:
		var fv: float = v
		return int(fv)
	return fallback


func _as_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		var bv: bool = v
		return bv
	return fallback


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		var arr: Array = v
		return arr
	return []


func test_order_book_price_time_priority_and_node_isolation() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var market: RegionalMarket = RegionalMarket.new(wg)

	# Place resting ASKs at luoyang out of order to verify price-time priority:
	# 1. p_s1 ASK 10 @ 1200 bp, tick 1 (lower price, earlier -> 1st match)
	# 2. p_s2 ASK 10 @ 1100 bp, tick 2 (lowest price -> should match BEFORE 1200 even if placed later!)
	# 3. p_s3 ASK 10 @ 1100 bp, tick 1 (same lowest price 1100, earlier tick 1 -> matches BEFORE p_s2!)
	var r_s1: Dictionary = market.place_order("luoyang", "p_s1", "GRAIN", "ASK", 1200, 10, 1)
	var r_s2: Dictionary = market.place_order("luoyang", "p_s2", "GRAIN", "ASK", 1100, 10, 2)
	var r_s3: Dictionary = market.place_order("luoyang", "p_s3", "GRAIN", "ASK", 1100, 10, 1)
	assert_true(_as_bool(r_s1.get("ok", false), false), "ASK 1 placed")
	assert_true(_as_bool(r_s2.get("ok", false), false), "ASK 2 placed")
	assert_true(_as_bool(r_s3.get("ok", false), false), "ASK 3 placed")

	var oid_s1: String = str(_as_dict(r_s1.get("order", {})).get("order_id", ""))
	var oid_s2: String = str(_as_dict(r_s2.get("order", {})).get("order_id", ""))
	var oid_s3: String = str(_as_dict(r_s3.get("order", {})).get("order_id", ""))

	# Place BID at changan (different node -> must NOT match luoyang orders)
	var r_other_node: Dictionary = market.place_order("changan", "p_b_other", "GRAIN", "BID", 1500, 20, 1)
	assert_true(_as_bool(r_other_node.get("ok", false), false), "Other node BID placed")

	# Place two BIDs at luoyang:
	# p_b1 BID 15 @ 1150 bp, tick 3 -> crosses both 1100 ASKs (fills 10 from p_s3 + 5 from p_s2)
	# p_b2 BID 10 @ 1250 bp, tick 4 -> higher BID price 1250 matches before 1150, fills 10 from p_s3 first!
	var r_b1: Dictionary = market.place_order("luoyang", "p_b1", "GRAIN", "BID", 1150, 15, 3)
	var r_b2: Dictionary = market.place_order("luoyang", "p_b2", "GRAIN", "BID", 1250, 10, 4)
	var oid_b1: String = str(_as_dict(r_b1.get("order", {})).get("order_id", ""))
	var oid_b2: String = str(_as_dict(r_b2.get("order", {})).get("order_id", ""))

	var match_res: Dictionary = market.match_node_orders("luoyang", 5)
	var trades: Array = _as_array(match_res.get("trades", []))
	assert_gte(trades.size(), 2, "At least 2 book trades executed")

	# First trade must match highest BID (p_b2 @ 1250) with lowest/earliest ASK (p_s3 @ 1100, tick 1)
	var t0: Dictionary = _as_dict(trades[0])
	assert_eq(str(t0.get("type", "")), "BOOK_MATCH", "First trade is BOOK_MATCH")
	assert_eq(str(t0.get("bid_order_id", "")), oid_b2, "Highest price BID fills first")
	assert_eq(str(t0.get("ask_order_id", "")), oid_s3, "Lowest price & earliest tick ASK fills first")
	assert_eq(_as_int(t0.get("quantity", 0), 0), 10, "Trade 0 fills 10 units")
	assert_eq(_as_int(t0.get("price_bp", 0), 0), 1100, "Executes at resting earlier ASK price 1100")

	# Second trade matches p_b1 with p_s2 (1100 bp, tick 2) for remaining 10
	var t1: Dictionary = _as_dict(trades[1])
	assert_eq(str(t1.get("bid_order_id", "")), oid_b1, "Second BID fills second")
	assert_eq(str(t1.get("ask_order_id", "")), oid_s2, "Second ASK at 1100 (tick 2) fills second")
	assert_eq(_as_int(t1.get("quantity", 0), 0), 10, "Trade 1 fills 10 units")

	assert_eq(str(market.get_order(oid_s3).get("status", "")), "FILLED", "ASK s3 filled")
	assert_eq(str(market.get_order(oid_s2).get("status", "")), "FILLED", "ASK s2 filled")
	assert_eq(str(market.get_order(oid_s1).get("status", "")), "OPEN", "ASK s1 (1200) did not cross BIDs (1150) and stays OPEN")
	assert_eq(_as_int(market.get_order(oid_b1).get("filled_quantity", 0), 0), 10, "p_b1 partially filled 10 of 15")

	# Verify changan BID was completely untouched by luoyang matching
	var oid_other: String = str(_as_dict(r_other_node.get("order", {})).get("order_id", ""))
	assert_eq(str(market.get_order(oid_other).get("status", "")), "OPEN", "Cross-node order untouched")


func test_amm_baseline_fill_and_sync_prices_to_world_graph() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var market: RegionalMarket = RegionalMarket.new(wg)

	var pool_before: Dictionary = market.get_amm_pool("xuchang", "IRON")
	var comm_before: int = _as_int(pool_before.get("commodity_reserve", 0), 0)
	var coin_before: int = _as_int(pool_before.get("coin_reserve", 0), 0)
	var k_before: int = _as_int(pool_before.get("k_product", 0), 0)
	var price_before: int = market.get_node_price_bp("xuchang", "IRON")
	assert_eq(price_before, 2100, "xuchang base IRON price is 2100 bp")

	# Large BID above spot price should buy from AMM reserve and push spot price UP
	var _r_buy: Dictionary = market.place_order("xuchang", "buyer_amm", "IRON", "BID", 3000, 500, 6)
	var res_buy: Dictionary = market.match_node_orders("xuchang", 6)
	var trades_buy: Array = _as_array(res_buy.get("trades", []))
	assert_gt(trades_buy.size(), 0, "AMM_BUY trade executed")
	assert_eq(str(_as_dict(trades_buy[0]).get("type", "")), "AMM_BUY", "Trade type is AMM_BUY")

	var pool_after_buy: Dictionary = market.get_amm_pool("xuchang", "IRON")
	var comm_after: int = _as_int(pool_after_buy.get("commodity_reserve", 0), 0)
	var coin_after: int = _as_int(pool_after_buy.get("coin_reserve", 0), 0)
	assert_lt(comm_after, comm_before, "AMM commodity_reserve decreased on buy")
	assert_gt(coin_after, coin_before, "AMM coin_reserve increased on buy")
	assert_gte(comm_after * coin_after, k_before, "AMM constant product k invariant holds (>= k_before)")
	var price_after_buy: int = market.get_node_price_bp("xuchang", "IRON")
	assert_gt(price_after_buy, price_before, "Spot price rises after AMM buy")

	# Sync discovered prices back to WorldGraph
	market.sync_prices_to_world_graph(wg)
	var node_xu: Dictionary = wg.get_node("xuchang")
	assert_eq(_as_int(node_xu.get("iron_price_bp", 0), 0), price_after_buy, "WorldGraph node iron_price_bp synced")

	# Large ASK below spot price on GRAIN sells into AMM pool and lowers price
	var grain_before: int = market.get_node_price_bp("xuchang", "GRAIN")
	var _r_sell: Dictionary = market.place_order("xuchang", "seller_amm", "GRAIN", "ASK", 700, 3000, 7)
	var res_sell: Dictionary = market.match_node_orders("xuchang", 7)
	var saw_amm_sell: bool = false
	for tr_v: Variant in _as_array(res_sell.get("trades", [])):
		if str(_as_dict(tr_v).get("type", "")) == "AMM_SELL":
			saw_amm_sell = true
	assert_true(saw_amm_sell, "AMM_SELL trade executed")
	assert_lt(market.get_node_price_bp("xuchang", "GRAIN"), grain_before, "GRAIN spot price drops after AMM sell")


func test_order_cancellation_invalid_rejection_and_caravan_arbitrage() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var market: RegionalMarket = RegionalMarket.new(wg)

	# Invalid order rejections
	var bad_node: Dictionary = market.place_order("", "p1", "GRAIN", "BID", 1000, 10, 1)
	assert_false(_as_bool(bad_node.get("ok", true), true), "Empty node_id rejected")
	assert_eq(str(bad_node.get("error_code", "")), DtoSchemas.ERR_SCHEMA, "Empty node_id gives ERR_SCHEMA")

	var bad_comm: Dictionary = market.place_order("luoyang", "p1", "DIAMONDS", "BID", 1000, 10, 1)
	assert_false(_as_bool(bad_comm.get("ok", true), true), "Unknown commodity rejected")

	var bad_side: Dictionary = market.place_order("luoyang", "p1", "GRAIN", "HOLD", 1000, 10, 1)
	assert_false(_as_bool(bad_side.get("ok", true), true), "Invalid side rejected")

	var bad_price: Dictionary = market.place_order("luoyang", "p1", "GRAIN", "BID", 50, 10, 1)
	assert_false(_as_bool(bad_price.get("ok", true), true), "Price < 100 rejected")

	var bad_qty: Dictionary = market.place_order("luoyang", "p1", "GRAIN", "BID", 1000, 0, 1)
	assert_false(_as_bool(bad_qty.get("ok", true), true), "Zero qty rejected")

	# Order cancellation & authorization
	var placed: Dictionary = market.place_order("luoyang", "owner_p", "WOOD", "ASK", 1800, 50, 2)
	var oid: String = str(_as_dict(placed.get("order", {})).get("order_id", ""))
	var cancel_unauth: Dictionary = market.cancel_order(oid, "thief_p")
	assert_false(_as_bool(cancel_unauth.get("ok", true), true), "Other player cannot cancel order")
	assert_eq(str(cancel_unauth.get("error_code", "")), DtoSchemas.ERR_UNAUTHORIZED, "Unauthorized cancel returns ERR_UNAUTHORIZED")

	var cancel_ok: Dictionary = market.cancel_order(oid, "owner_p")
	assert_true(_as_bool(cancel_ok.get("ok", false), false), "Owner can cancel OPEN order")
	assert_eq(str(market.get_order(oid).get("status", "")), "CANCELLED", "Order status becomes CANCELLED")

	var cancel_again: Dictionary = market.cancel_order(oid, "owner_p")
	assert_false(_as_bool(cancel_again.get("ok", true), true), "Already cancelled order cannot be cancelled again")
	assert_eq(str(cancel_again.get("error_code", "")), DtoSchemas.ERR_INVALID_STATE, "Non-OPEN cancel returns ERR_INVALID_STATE")

	# Arbitrage caravan settlement: hulao_pass has GRAIN 1200 bp vs chengdu GRAIN 800 bp
	var caravan_high: Dictionary = {
		"entity_id": "car_high",
		"carried_coin": 100,
		"cargo": {"GRAIN": 500, "IRON": 100}
	}
	var caravan_low: Dictionary = {
		"entity_id": "car_low",
		"carried_coin": 100,
		"cargo": {"GRAIN": 500, "IRON": 100}
	}
	var settle_high: Dictionary = market.settle_caravan_trade(caravan_high, "hulao_pass", 10)
	var settle_low: Dictionary = market.settle_caravan_trade(caravan_low, "chengdu", 10)

	var earned_high: int = _as_int(settle_high.get("coin_earned", 0), 0)
	var earned_low: int = _as_int(settle_low.get("coin_earned", 0), 0)
	assert_gt(earned_high, 0, "Caravan earns coin at hulao_pass")
	assert_gt(earned_low, 0, "Caravan earns coin at chengdu")
	assert_gt(earned_high, earned_low, "Arbitrage: high-price market yields strictly more coin than low-price market")
	assert_eq(_as_int(caravan_high.get("carried_coin", 0), 0), 100 + earned_high, "Caravan carried_coin credited")
	assert_eq(_as_int(_as_dict(caravan_high.get("cargo", {})).get("GRAIN", -1), -1), 0, "Sold GRAIN cargo cleared")


func test_to_dict_from_dict_parity_and_zero_floats() -> void:
	var wg: WorldGraph = WorldGraph.load_from_json_file("res://data/macro_map_3k.json")
	var market: RegionalMarket = RegionalMarket.new(wg)

	var _o1: Dictionary = market.place_order("luoyang", "p1", "GRAIN", "BID", 1100, 100, 1)
	var _o2: Dictionary = market.place_order("luoyang", "p2", "GRAIN", "ASK", 1050, 60, 2)
	var _m: Dictionary = market.match_node_orders("luoyang", 3)

	var d1: Dictionary = market.to_dict()
	assert_false(StateHasher.has_floats(d1), "RegionalMarket.to_dict() contains zero floats")
	assert_true(StateHasher.validate_deterministic_types(d1), "RegionalMarket.to_dict() uses deterministic types")

	var market2: RegionalMarket = RegionalMarket.from_dict(d1)
	var d2: Dictionary = market2.to_dict()
	assert_eq(StateHasher.sha256_dict(d1), StateHasher.sha256_dict(d2), "RegionalMarket to_dict/from_dict SHA-256 parity")

	# Verify order sequence continuity
	var next1: Dictionary = market.place_order("luoyang", "p3", "IRON", "BID", 2200, 10, 4)
	var next2: Dictionary = market2.place_order("luoyang", "p3", "IRON", "BID", 2200, 10, 4)
	assert_eq(
		str(_as_dict(next1.get("order", {})).get("order_id", "")),
		str(_as_dict(next2.get("order", {})).get("order_id", "")),
		"Order ID sequence preserved across restore"
	)
