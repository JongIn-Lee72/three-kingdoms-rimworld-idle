class_name AudioManager
extends Node

const MANIFEST_PATH: String = "res://data/assets_manifest.json"
const SFX_POOL_SIZE: int = 8

const FALLBACK_SFX_MAP: Dictionary = {
	"UI_CLICK": "res://assets/audio/sfx/confirmation_002.ogg",
	"UI_ERROR": "res://assets/audio/sfx/error_006.ogg",
	"TAB_SWITCH": "res://assets/audio/sfx/page-turn.wav",
	"BUILD_UPGRADE": "res://assets/audio/sfx/chop.ogg",
	"DOOR_MANOR": "res://assets/audio/sfx/door-close-1.wav",
	"COIN_TRADE": "res://assets/audio/sfx/coin-drop.wav",
	"MARCH_DISPATCH": "res://assets/audio/sfx/footstep-wood-1.wav",
	"DOCTRINE_BANNER": "res://assets/audio/sfx/cloth-1.wav",
	"DUEL_CLASH": "res://assets/audio/sfx/oga_sword_sound.wav",
	"METAL_FORGE": "res://assets/audio/sfx/metal-clang.wav",
	"SIEGE_IMPACT": "res://assets/audio/sfx/impactWood_light_002.ogg",
	"MELEE_STRIKE": "res://assets/audio/sfx/oga_melee_sound.wav",
	"BANQUET_CHEER": "res://assets/audio/sfx/glass-clink.wav",
	"AWAKENING_CHIME": "res://assets/audio/sfx/bell-ding.wav",
	"GAZETTE_OPEN": "res://assets/audio/sfx/book-flip.wav",
	"SEAL_VERIFY": "res://assets/audio/sfx/drop_002.ogg"
}

const FALLBACK_BGM_TRACKS: Dictionary = {
	"MAIN_THREE_KINGDOMS": "res://assets/audio/bgm/east_asian_theme.ogg"
}

var _sfx_event_paths: Dictionary = {}
var _bgm_track_paths: Dictionary = {}
var _sfx_streams: Dictionary = {}
var _bgm_streams: Dictionary = {}

var _bgm_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0

var _muted: bool = false
var _bgm_volume_db: float = -8.0
var _sfx_volume_db: float = -4.0
var _current_bgm_id: String = ""
var played_events: Array[String] = []


func _init() -> void:
	name = "AudioManager"
	_init_players()
	_load_manifest_maps()
	_preload_all_streams()


func _init_players() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BgmPlayer"
	_bgm_player.volume_db = _bgm_volume_db
	add_child(_bgm_player)

	_sfx_pool.clear()
	for i: int in range(SFX_POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SfxPlayer_%d" % i
		player.volume_db = _sfx_volume_db
		add_child(player)
		_sfx_pool.append(player)


func _load_manifest_maps() -> void:
	_sfx_event_paths = FALLBACK_SFX_MAP.duplicate()
	_bgm_track_paths = FALLBACK_BGM_TRACKS.duplicate()

	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return

	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		return
	if not (parser.data is Dictionary):
		return
	var root: Dictionary = parser.data

	var sfx_v: Variant = root.get("sfx_event_map", null)
	if sfx_v is Dictionary:
		var sfx_dict: Dictionary = sfx_v
		for key_v: Variant in sfx_dict.keys():
			var key_str: String = str(key_v)
			var path_str: String = str(sfx_dict[key_v])
			if not key_str.is_empty() and not path_str.is_empty():
				_sfx_event_paths[key_str] = path_str

	var bgm_v: Variant = root.get("bgm_tracks", null)
	if bgm_v is Dictionary:
		var bgm_dict: Dictionary = bgm_v
		for key_v: Variant in bgm_dict.keys():
			var key_str: String = str(key_v)
			var path_str: String = str(bgm_dict[key_v])
			if not key_str.is_empty() and not path_str.is_empty():
				_bgm_track_paths[key_str] = path_str


func _load_audio_stream(res_path: String, enable_loop: bool) -> AudioStream:
	if res_path.is_empty():
		return null

	if ResourceLoader.exists(res_path):
		var loaded: Resource = ResourceLoader.load(res_path)
		if loaded is AudioStream:
			var stream: AudioStream = loaded
			if stream is AudioStreamOggVorbis:
				var ogg_res: AudioStreamOggVorbis = stream
				ogg_res.loop = enable_loop
			elif stream is AudioStreamWAV and enable_loop:
				var wav_res: AudioStreamWAV = stream
				wav_res.loop_mode = AudioStreamWAV.LOOP_FORWARD
			return stream

	var lower: String = res_path.to_lower()
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null

	if lower.ends_with(".ogg"):
		var ogg: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_file(abs_path)
		if ogg != null:
			ogg.loop = enable_loop
			return ogg
	elif lower.ends_with(".wav"):
		var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(abs_path)
		if wav != null:
			if enable_loop:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			return wav
	return null


func _preload_all_streams() -> void:
	_sfx_streams.clear()
	for event_v: Variant in _sfx_event_paths.keys():
		var event_id: String = str(event_v)
		var res_path: String = str(_sfx_event_paths[event_v])
		var stream: AudioStream = _load_audio_stream(res_path, false)
		if stream != null:
			_sfx_streams[event_id] = stream

	_bgm_streams.clear()
	for track_v: Variant in _bgm_track_paths.keys():
		var track_id: String = str(track_v)
		var res_path: String = str(_bgm_track_paths[track_v])
		var stream: AudioStream = _load_audio_stream(res_path, true)
		if stream != null:
			_bgm_streams[track_id] = stream


func play_bgm(track_id: String = "MAIN_THREE_KINGDOMS") -> bool:
	var stream_v: Variant = _bgm_streams.get(track_id, null)
	if not (stream_v is AudioStream):
		if not _bgm_track_paths.has(track_id):
			return false
		var loaded: AudioStream = _load_audio_stream(str(_bgm_track_paths[track_id]), true)
		if loaded == null:
			return false
		_bgm_streams[track_id] = loaded
		stream_v = loaded

	var stream: AudioStream = stream_v
	_current_bgm_id = track_id
	if _bgm_player == null:
		return false

	_bgm_player.stream = stream
	_bgm_player.volume_db = _bgm_volume_db
	if _muted:
		if _bgm_player.playing:
			_bgm_player.stop()
		return true

	if is_inside_tree():
		_bgm_player.play()
	return true


func stop_bgm() -> void:
	_current_bgm_id = ""
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()


func play_sfx(event_id: String) -> bool:
	var stream_v: Variant = _sfx_streams.get(event_id, null)
	if not (stream_v is AudioStream):
		if not _sfx_event_paths.has(event_id):
			return false
		var loaded: AudioStream = _load_audio_stream(str(_sfx_event_paths[event_id]), false)
		if loaded == null:
			return false
		_sfx_streams[event_id] = loaded
		stream_v = loaded

	var stream: AudioStream = stream_v
	played_events.append(event_id)
	if _muted or _sfx_pool.is_empty():
		return true

	var chosen: AudioStreamPlayer = null
	for i: int in range(_sfx_pool.size()):
		var idx: int = (_sfx_cursor + i) % _sfx_pool.size()
		var candidate: AudioStreamPlayer = _sfx_pool[idx]
		if not candidate.playing:
			chosen = candidate
			_sfx_cursor = (idx + 1) % _sfx_pool.size()
			break
	if chosen == null:
		chosen = _sfx_pool[_sfx_cursor]
		_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()

	chosen.stream = stream
	chosen.volume_db = _sfx_volume_db
	if is_inside_tree():
		chosen.play()
	return true


func set_muted(muted: bool) -> void:
	_muted = muted
	if _muted:
		if _bgm_player != null and _bgm_player.playing:
			_bgm_player.stop()
		for player: AudioStreamPlayer in _sfx_pool:
			if player.playing:
				player.stop()
	else:
		if not _current_bgm_id.is_empty() and _bgm_player != null and is_inside_tree():
			if _bgm_player.stream != null and not _bgm_player.playing:
				_bgm_player.play()


func is_muted() -> bool:
	return _muted


func set_bgm_volume_db(db: float) -> void:
	_bgm_volume_db = db
	if _bgm_player != null:
		_bgm_player.volume_db = _bgm_volume_db


func set_sfx_volume_db(db: float) -> void:
	_sfx_volume_db = db
	for player: AudioStreamPlayer in _sfx_pool:
		player.volume_db = _sfx_volume_db


func get_loaded_sfx_count() -> int:
	return _sfx_streams.size()


func get_loaded_bgm_count() -> int:
	return _bgm_streams.size()


func get_played_events() -> Array[String]:
	return played_events.duplicate()


func clear_played_events() -> void:
	played_events.clear()
