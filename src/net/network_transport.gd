class_name NetworkTransport
extends RefCounted

const MODE_LOOPBACK: String = "LOOPBACK_MEMORY"
const MODE_WEBSOCKET: String = "WEBSOCKET"
const MODE_ENET: String = "ENET"
const MAX_PACKET_BYTES: int = 65536

var mode: String = MODE_LOOPBACK

# Deterministic in-memory loopback queues
var _loopback_peers: Dictionary = {}        # canonical_peer_id -> original_peer_id
var _loopback_client_inboxes: Dictionary = {} # canonical_peer_id -> Array[Dictionary]
var _loopback_server_inbox: Array[Dictionary] = []

# Real WebSocket / TCPServer state
var _tcp_server: TCPServer = null
var _ws_server_peers: Dictionary = {}   # canonical_peer_id -> WebSocketPeer
var _ws_client_peer: WebSocketPeer = null
var _ws_client_url: String = ""
var _ws_client_inbox: Array[Dictionary] = []
var _next_ws_peer_seq: int = 1

# Real ENetMultiplayerPeer state
var _enet_peer: ENetMultiplayerPeer = null
var _enet_is_server: bool = false
var _enet_connected_peers: Dictionary = {} # int peer_id -> true
var _enet_client_inbox: Array[Dictionary] = []


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


static func _peer_key(peer_id: Variant) -> String:
	return str(peer_id)


func _init(p_mode: String = MODE_LOOPBACK) -> void:
	mode = p_mode if (p_mode == MODE_LOOPBACK or p_mode == MODE_WEBSOCKET or p_mode == MODE_ENET) else MODE_LOOPBACK


func create_loopback() -> NetworkTransport:
	close()
	mode = MODE_LOOPBACK
	_loopback_peers.clear()
	_loopback_client_inboxes.clear()
	_loopback_server_inbox.clear()
	return self


func register_loopback_peer(peer_id: Variant) -> String:
	var pkey: String = _peer_key(peer_id)
	if pkey.is_empty():
		return ""
	_loopback_peers[pkey] = peer_id
	if not _loopback_client_inboxes.has(pkey):
		var empty_arr: Array[Dictionary] = []
		_loopback_client_inboxes[pkey] = empty_arr
	return pkey


func has_peer(peer_id: Variant) -> bool:
	var pkey: String = _peer_key(peer_id)
	if mode == MODE_LOOPBACK:
		return _loopback_peers.has(pkey)
	if mode == MODE_WEBSOCKET:
		return _ws_server_peers.has(pkey)
	if mode == MODE_ENET:
		return _enet_connected_peers.has(_to_int(peer_id, -1))
	return false


func get_connected_peer_ids() -> Array[String]:
	var out: Array[String] = []
	if mode == MODE_LOOPBACK:
		for k: Variant in _loopback_peers.keys():
			out.append(str(k))
	elif mode == MODE_WEBSOCKET:
		for k: Variant in _ws_server_peers.keys():
			out.append(str(k))
	elif mode == MODE_ENET:
		for k: Variant in _enet_connected_peers.keys():
			out.append(str(k))
	out.sort()
	return out


func client_send_raw(peer_id: Variant, raw_utf8: String) -> bool:
	var pkey: String = _peer_key(peer_id)
	if pkey.is_empty():
		return false
	if mode == MODE_LOOPBACK:
		var resolved_id: Variant = _loopback_peers.get(pkey, peer_id)
		_loopback_server_inbox.append({
			"peer_id": resolved_id,
			"peer_key": pkey,
			"raw_utf8": raw_utf8
		})
		return true
	if mode == MODE_WEBSOCKET:
		if _ws_client_peer != null:
			if _ws_client_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				var err: Error = _ws_client_peer.send_text(raw_utf8)
				return err == OK
		return false
	if mode == MODE_ENET:
		if _enet_peer != null and not _enet_is_server:
			_enet_peer.set_target_peer(1)
			var err: Error = _enet_peer.put_packet(raw_utf8.to_utf8_buffer())
			return err == OK
		return false
	return false


func client_send_envelope(peer_id: Variant, envelope: Dictionary) -> bool:
	var raw_json: String = StateHasher.canonical_json(envelope)
	return client_send_raw(peer_id, raw_json)


func server_drain_incoming() -> Array[Dictionary]:
	if mode == MODE_LOOPBACK:
		var drained: Array[Dictionary] = _loopback_server_inbox.duplicate()
		_loopback_server_inbox.clear()
		return drained
	if mode == MODE_WEBSOCKET:
		poll()
		var out_ws: Array[Dictionary] = []
		var pkeys: Array[String] = []
		for k: Variant in _ws_server_peers.keys():
			pkeys.append(str(k))
		pkeys.sort()
		for pkey: String in pkeys:
			var ws_var: Variant = _ws_server_peers[pkey]
			if ws_var is WebSocketPeer:
				var ws: WebSocketPeer = ws_var
				while ws.get_available_packet_count() > 0:
					var pkt: PackedByteArray = ws.get_packet()
					if pkt.size() <= MAX_PACKET_BYTES and ws.was_string_packet():
						out_ws.append({
							"peer_id": pkey,
							"peer_key": pkey,
							"raw_utf8": pkt.get_string_from_utf8()
						})
		return out_ws
	if mode == MODE_ENET:
		poll()
		var out_enet: Array[Dictionary] = []
		if _enet_peer != null and _enet_is_server:
			while _enet_peer.get_available_packet_count() > 0:
				var sender_id: int = _enet_peer.get_packet_peer()
				var pkt: PackedByteArray = _enet_peer.get_packet()
				if pkt.size() <= MAX_PACKET_BYTES:
					out_enet.append({
						"peer_id": sender_id,
						"peer_key": str(sender_id),
						"raw_utf8": pkt.get_string_from_utf8()
					})
		return out_enet
	return []


func _sanitize_outgoing_dict(msg_dict: Dictionary) -> Dictionary:
	var txt: String = JSON.stringify(msg_dict)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
		if norm is Dictionary:
			var d: Dictionary = norm
			return d
	return msg_dict.duplicate(true)


func server_send_to_peer(peer_id: Variant, msg_dict: Dictionary) -> bool:
	var pkey: String = _peer_key(peer_id)
	if pkey.is_empty():
		return false
	if mode == MODE_LOOPBACK:
		if not _loopback_client_inboxes.has(pkey):
			var empty_arr: Array[Dictionary] = []
			_loopback_client_inboxes[pkey] = empty_arr
		var inbox_var: Variant = _loopback_client_inboxes[pkey]
		if inbox_var is Array:
			var inbox: Array = inbox_var
			inbox.append(_sanitize_outgoing_dict(msg_dict))
			return true
		return false
	if mode == MODE_WEBSOCKET:
		if not _ws_server_peers.has(pkey):
			return false
		var ws_var: Variant = _ws_server_peers[pkey]
		if ws_var is WebSocketPeer:
			var ws: WebSocketPeer = ws_var
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				var raw_json: String = StateHasher.canonical_json(msg_dict)
				var err: Error = ws.send_text(raw_json)
				return err == OK
		return false
	if mode == MODE_ENET:
		if _enet_peer != null and _enet_is_server:
			var target_id: int = _to_int(peer_id, -1)
			if target_id <= 0:
				return false
			_enet_peer.set_target_peer(target_id)
			var raw_bytes: PackedByteArray = StateHasher.canonical_json(msg_dict).to_utf8_buffer()
			var err: Error = _enet_peer.put_packet(raw_bytes)
			return err == OK
		return false
	return false


func server_broadcast(msg_dict: Dictionary) -> void:
	for pkey: String in get_connected_peer_ids():
		var target_id: Variant = _loopback_peers.get(pkey, pkey) if mode == MODE_LOOPBACK else pkey
		var _ok: bool = server_send_to_peer(target_id, msg_dict)


func client_drain_incoming(peer_id: Variant) -> Array[Dictionary]:
	var pkey: String = _peer_key(peer_id)
	if mode == MODE_LOOPBACK:
		if not _loopback_client_inboxes.has(pkey):
			return []
		var inbox_var: Variant = _loopback_client_inboxes[pkey]
		if inbox_var is Array:
			var inbox: Array = inbox_var
			var out: Array[Dictionary] = []
			for item: Variant in inbox:
				if item is Dictionary:
					var d: Dictionary = item
					out.append(d)
			inbox.clear()
			return out
		return []
	if mode == MODE_WEBSOCKET:
		poll()
		var out_ws: Array[Dictionary] = _ws_client_inbox.duplicate()
		_ws_client_inbox.clear()
		return out_ws
	if mode == MODE_ENET:
		poll()
		var out_enet: Array[Dictionary] = _enet_client_inbox.duplicate()
		_enet_client_inbox.clear()
		return out_enet
	return []


func listen_websocket(port: int, bind_address: String = "127.0.0.1") -> Error:
	close()
	mode = MODE_WEBSOCKET
	_tcp_server = TCPServer.new()
	var err: Error = _tcp_server.listen(port, bind_address)
	if err != OK:
		_tcp_server = null
	return err


func connect_websocket(url: String) -> Error:
	close()
	mode = MODE_WEBSOCKET
	_ws_client_url = url
	_ws_client_peer = WebSocketPeer.new()
	var err: Error = _ws_client_peer.connect_to_url(url)
	if err != OK:
		_ws_client_peer = null
	return err


func listen_enet(port: int, max_clients: int = 64) -> Error:
	close()
	mode = MODE_ENET
	_enet_peer = ENetMultiplayerPeer.new()
	_enet_is_server = true
	var err: Error = _enet_peer.create_server(port, maxi(1, max_clients))
	if err != OK:
		_enet_peer = null
		_enet_is_server = false
	return err


func connect_enet(address: String, port: int) -> Error:
	close()
	mode = MODE_ENET
	_enet_peer = ENetMultiplayerPeer.new()
	_enet_is_server = false
	var err: Error = _enet_peer.create_client(address, port)
	if err != OK:
		_enet_peer = null
	return err


func is_ws_client_open() -> bool:
	return _ws_client_peer != null and _ws_client_peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func poll() -> void:
	if mode == MODE_WEBSOCKET:
		if _tcp_server != null and _tcp_server.is_listening():
			while _tcp_server.is_connection_available():
				var stream: StreamPeerTCP = _tcp_server.take_connection()
				if stream != null:
					var ws: WebSocketPeer = WebSocketPeer.new()
					var err: Error = ws.accept_stream(stream)
					if err == OK:
						var pkey: String = "ws_%06d" % _next_ws_peer_seq
						_next_ws_peer_seq += 1
						_ws_server_peers[pkey] = ws
		var closed_keys: Array[String] = []
		for k: Variant in _ws_server_peers.keys():
			var pkey: String = str(k)
			var ws_var: Variant = _ws_server_peers[pkey]
			if ws_var is WebSocketPeer:
				var ws: WebSocketPeer = ws_var
				ws.poll()
				if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
					closed_keys.append(pkey)
		for ck: String in closed_keys:
			var _er: bool = _ws_server_peers.erase(ck)

		if _ws_client_peer != null:
			_ws_client_peer.poll()
			while _ws_client_peer.get_available_packet_count() > 0:
				var pkt: PackedByteArray = _ws_client_peer.get_packet()
				if pkt.size() <= MAX_PACKET_BYTES and _ws_client_peer.was_string_packet():
					var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
					if parsed is Dictionary:
						var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
						if norm is Dictionary:
							var d: Dictionary = norm
							_ws_client_inbox.append(d)

	elif mode == MODE_ENET and _enet_peer != null:
		_enet_peer.poll()
		if not _enet_is_server:
			while _enet_peer.get_available_packet_count() > 0:
				var pkt: PackedByteArray = _enet_peer.get_packet()
				if pkt.size() <= MAX_PACKET_BYTES:
					var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
					if parsed is Dictionary:
						var norm: Variant = DtoSchemas.normalize_json_ints(parsed)
						if norm is Dictionary:
							var d: Dictionary = norm
							_enet_client_inbox.append(d)


func close() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null
	for k: Variant in _ws_server_peers.keys():
		var ws_var: Variant = _ws_server_peers[k]
		if ws_var is WebSocketPeer:
			var ws: WebSocketPeer = ws_var
			ws.close()
	_ws_server_peers.clear()
	if _ws_client_peer != null:
		_ws_client_peer.close()
		_ws_client_peer = null
	_ws_client_inbox.clear()
	if _enet_peer != null:
		_enet_peer.close()
		_enet_peer = null
	_enet_is_server = false
	_enet_connected_peers.clear()
	_enet_client_inbox.clear()
