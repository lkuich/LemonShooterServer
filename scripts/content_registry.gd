extends Node

signal registry_changed(content_set_hash: String)

const PACK_SCHEMA_VERSION := 1
const MAX_PACK_BYTES := 256 * 1024 * 1024
const MAX_JOIN_BYTES := 512 * 1024 * 1024
const MAX_CACHE_BYTES := 2 * 1024 * 1024 * 1024
const MAX_FILES_PER_PACK := 4096
const MAX_FILE_BYTES := 128 * 1024 * 1024
const MAX_MAP_NODES := 12000
const MAX_MAP_TRIANGLES := 1500000
const CACHE_DIRECTORY := "user://community_packs"
const CACHE_INDEX_PATH := "user://community_packs/cache_index.json"
const ALLOWED_EXTENSIONS := ["json", "glb", "png", "jpg", "jpeg", "webp", "ogg", "wav", "mp3", "svg"]
const FORBIDDEN_EXTENSIONS := ["gd", "gdc", "gdshader", "shader", "dll", "dylib", "so", "exe", "bat", "cmd", "ps1", "sh", "pck", "zip"]
const COMMUNITY_WEAPON_ARCHETYPES := ["automatic", "semi_automatic", "shotgun", "sniper"]
const REQUIRED_HUMANOID_BONES := [
	"hips", "spine", "chest", "head", "upleg.L", "leg.L", "foot.L",
	"upleg.R", "leg.R", "foot.R", "arm.L", "forearm.L", "hand.L",
	"arm.R", "forearm.R", "hand.R"
]

var _maps: Dictionary = {}
var _weapons: Dictionary = {}
var _models: Dictionary = {}
var _packs: Dictionary = {}
var _active_pack_ids: Array[String] = ["core"]
var _pack_readers: Dictionary = {}
var _cache_index: Dictionary = {}
var _content_set_hash := ""

func _ready() -> void:
	_register_core_pack()
	_load_cache_index()
	_recompute_content_set_hash()

func _register_core_pack() -> void:
	_packs["core"] = {
		"id": "core",
		"version": "1.0.0",
		"sha256": "",
		"size": 0,
		"url": "",
		"display_name": "LemonShooter Core",
		"author": "LemonShooter",
		"trusted": true
	}
	_maps = {
		"training_arena": _core_map("Training Arena", ["ffa", "tdm", "juggernaut", "infection", "koth"], "programmatic"),
		"warehouse": _core_map("Warehouse", ["ffa", "tdm", "juggernaut", "infection", "koth"], "programmatic"),
		"twin_bastion": _core_map("Twin Bastion", ["ffa", "tdm", "juggernaut", "infection", "koth"], "programmatic"),
		"highrise": _core_map("Highrise", ["ffa", "tdm", "juggernaut", "infection", "koth"], "programmatic"),
		"city": _core_map("City District", ["ffa", "tdm", "juggernaut", "infection", "koth"], "programmatic"),
		"suburban_test_site": _core_map("Suburban Test Site", ["ffa", "tdm", "juggernaut", "infection", "koth"], "scene")
	}
	_weapons = {
		"ak47": _core_weapon("AK-47", "automatic", 36.0, 10.0, 30, 90, 1.65, 120.0, 82, 68, 0.97, 1.1, 0.16, 1.0, true),
		"ar15": _core_weapon("AR-15", "automatic", 32.0, 11.0, 30, 120, 1.55, 135.0, 87, 76, 1.0, 1.0, 0.13, 0.82, true),
		"smg": _core_weapon("Uzi", "automatic", 22.0, 14.0, 32, 128, 1.3, 78.0, 68, 92, 1.08, 1.55, 0.3, 0.64, true),
		"pistol": _core_weapon("Service Pistol", "semi_automatic", 45.0, 7.5, 12, 48, 1.05, 72.0, 88, 96, 1.1, 0.85, 0.12, 1.18, false),
		"shotgun": _core_weapon("Maverick Shotgun", "shotgun", 14.0, 1.35, 8, 32, 2.2, 75.0, 65, 58, 0.93, 3.2, 1.35, 2.0, false, 8),
		"sniper": _core_weapon("Longshot SR", "sniper", 90.0, 0.85, 5, 25, 2.4, 180.0, 98, 42, 0.87, 3.5, 0.025, 2.15, false),
		"knife": _core_weapon("Combat Knife", "core_only", 65.0, 4.545, 0, 0, 0.0, 2.4, 100, 100, 1.12, 0.0, 0.0, 0.0, false),
		"coil_gun": _core_weapon("Coil Gun", "core_only", 10000.0, 0.34, 0, 0, 0.0, 22.0, 100, 35, 0.84, 0.0, 0.0, 1.8, false),
		"portal_gun": _core_weapon("Portal Gun", "core_only", 0.0, 3.0, 0, 0, 0.0, 160.0, 100, 88, 1.02, 0.0, 0.0, 0.25, false),
		"suicide_vest": _core_weapon("C4 Vest", "core_only", 10000.0, 0.5, 0, 0, 0.0, 18.0, 100, 70, 0.96, 0.0, 0.0, 0.0, false)
	}
	var bot_tactics := {
		"ak47": {"interval": 0.27, "damage": 12.0, "accuracy": 1.0, "pitch": 0.92, "range": 30.0, "pellets": 1},
		"ar15": {"interval": 0.22, "damage": 11.0, "accuracy": 1.12, "pitch": 1.0, "range": 30.0, "pellets": 1},
		"smg": {"interval": 0.19, "damage": 8.0, "accuracy": 0.88, "pitch": 1.08, "range": 24.0, "pellets": 1},
		"pistol": {"interval": 0.42, "damage": 18.0, "accuracy": 1.08, "pitch": 1.03, "range": 26.0, "pellets": 1},
		"shotgun": {"interval": 0.82, "damage": 8.5, "accuracy": 0.82, "pitch": 1.0, "range": 17.0, "pellets": 7},
		"sniper": {"interval": 1.05, "damage": 78.0, "accuracy": 1.28, "pitch": 1.0, "range": 30.0, "pellets": 1}
	}
	for weapon_id in bot_tactics:
		_weapons[weapon_id]["bot"] = bot_tactics[weapon_id]
	_models = {
		"soldier": {
			"id": "soldier", "pack_id": "core", "name": "Core Soldier",
			"asset": "res://models/soldier/soldier1.glb", "humanoid": true,
			"required_bones": REQUIRED_HUMANOID_BONES.duplicate(), "weapon_attachment": "hand.R"
		},
		"zombie": {
			"id": "zombie", "pack_id": "core", "name": "Core Infected",
			"asset": "res://models/zombie/zombie.glb", "humanoid": true,
			"infection_only": true
		}
	}

func _core_map(display_name: String, modes: Array[String], provider: String) -> Dictionary:
	return {
		"id": display_name.to_snake_case(), "pack_id": "core", "name": display_name,
		"provider": provider, "supported_modes": modes, "trusted": true
	}

func _core_weapon(
	display_name: String,
	archetype: String,
	damage: float,
	rate: float,
	magazine: int,
	reserve: int,
	reload_time: float,
	max_range: float,
	accuracy: int,
	mobility: int,
	move_multiplier: float,
	hip_spread: float,
	ads_spread: float,
	recoil: float,
	automatic: bool,
	pellets := 1
) -> Dictionary:
	return {
		"name": display_name, "pack_id": "core", "archetype": archetype,
		"damage": damage, "rate": rate, "mag": magazine, "reserve": reserve,
		"reload": reload_time, "range": max_range, "accuracy": accuracy,
		"mobility": mobility, "move": move_multiplier, "hip": hip_spread,
		"ads": ads_spread, "recoil": recoil, "automatic": automatic,
		"pellets": pellets, "loadout": archetype != "core_only",
		"akimbo": archetype != "core_only", "trusted": true
	}

func enumerate_maps(mode_id := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for map_id in _sorted_keys(_maps):
		var definition: Dictionary = _maps[map_id]
		if mode_id.is_empty() or mode_id in definition.get("supported_modes", []):
			var item := definition.duplicate(true)
			item["id"] = map_id
			result.append(item)
	return result

func enumerate_weapons(loadout_only := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for weapon_id in _sorted_keys(_weapons):
		var definition: Dictionary = _weapons[weapon_id]
		if not loadout_only or definition.get("loadout", false):
			var item := definition.duplicate(true)
			item["id"] = weapon_id
			result.append(item)
	return result

func enumerate_models(include_infection_override := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for model_id in _sorted_keys(_models):
		var definition: Dictionary = _models[model_id]
		if include_infection_override or not definition.get("infection_only", false):
			var item := definition.duplicate(true)
			item["id"] = model_id
			result.append(item)
	return result

func resolve_map(map_id: String) -> Dictionary:
	return _maps.get(map_id, {}).duplicate(true)

func resolve_weapon(weapon_id: String) -> Dictionary:
	return _weapons.get(weapon_id, {}).duplicate(true)

func resolve_model(model_id: String) -> Dictionary:
	return _models.get(model_id, {}).duplicate(true)

func has_map(map_id: String) -> bool:
	return _maps.has(map_id)

func has_weapon(weapon_id: String) -> bool:
	return _weapons.has(weapon_id)

func has_model(model_id: String) -> bool:
	return _models.has(model_id)

func get_map_options(mode_id := "") -> Array:
	var options: Array = []
	for definition in enumerate_maps(mode_id):
		options.append([str(definition["name"]).to_upper(), definition["id"]])
	return options

func get_loadout_weapon_ids() -> Array[String]:
	var result: Array[String] = []
	for definition in enumerate_weapons(true):
		result.append(str(definition["id"]))
	return result

func get_akimbo_weapon_ids() -> Array[String]:
	var result: Array[String] = []
	for definition in enumerate_weapons(true):
		if definition.get("akimbo", false):
			result.append(str(definition["id"]))
	return result

func get_bot_loadout_weapon_ids() -> Array[String]:
	var result: Array[String] = []
	for definition in enumerate_weapons(true):
		if definition.has("bot"):
			result.append(str(definition["id"]))
	return result

func resolve_bot_tactics(weapon_id: String) -> Dictionary:
	var definition := resolve_weapon(weapon_id)
	var tactics = definition.get("bot", {})
	if tactics is Dictionary and not tactics.is_empty():
		return tactics.duplicate(true)
	return resolve_weapon("ak47").get("bot", {}).duplicate(true)

func get_pack_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for pack_id in _active_pack_ids:
		if pack_id != "core" and _packs.has(pack_id):
			descriptors.append(_public_pack_descriptor(_packs[pack_id]))
	return descriptors

func get_content_set_hash() -> String:
	return _content_set_hash

func is_modded() -> bool:
	return _active_pack_ids.size() > 1

func validate_pack(path: String, expected_sha256 := "") -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["Pack file does not exist."], "warnings": []}
	var pack_file := FileAccess.open(path, FileAccess.READ)
	var pack_size := pack_file.get_length() if pack_file else 0
	if pack_size > MAX_PACK_BYTES:
		errors.append("Pack exceeds the 256 MB limit.")
	if not expected_sha256.is_empty():
		var actual_hash := FileAccess.get_sha256(path).to_lower()
		if actual_hash != expected_sha256.to_lower():
			errors.append("SHA-256 does not match the advertised pack hash.")
	var reader := ZIPReader.new()
	var open_error := reader.open(path)
	if open_error != OK:
		errors.append("Pack is not a readable ZIP archive.")
		return {"ok": false, "errors": errors, "warnings": warnings}
	var files := reader.get_files()
	if files.size() > MAX_FILES_PER_PACK:
		errors.append("Pack contains too many files.")
	var total_uncompressed := 0
	for entry in files:
		if str(entry).ends_with("/"):
			continue
		var path_error := _validate_archive_path(str(entry))
		if not path_error.is_empty():
			errors.append(path_error)
			continue
		var extension := str(entry).get_extension().to_lower()
		if extension in FORBIDDEN_EXTENSIONS or extension not in ALLOWED_EXTENSIONS:
			errors.append("Forbidden file type: %s" % entry)
			continue
		var bytes := reader.read_file(entry)
		total_uncompressed += bytes.size()
		if bytes.size() > MAX_FILE_BYTES:
			errors.append("File exceeds the per-file limit: %s" % entry)
		if total_uncompressed > MAX_PACK_BYTES:
			errors.append("Uncompressed pack data exceeds 256 MB.")
			break
	if "manifest.json" not in files:
		errors.append("Pack is missing manifest.json.")
	if not errors.is_empty():
		reader.close()
		return {"ok": false, "errors": errors, "warnings": warnings}
	var manifest_value = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	if manifest_value is not Dictionary:
		errors.append("manifest.json is not a JSON object.")
		reader.close()
		return {"ok": false, "errors": errors, "warnings": warnings}
	var manifest: Dictionary = manifest_value
	_validate_manifest(manifest, files, reader, errors, warnings)
	reader.close()
	return {
		"ok": errors.is_empty(), "errors": errors, "warnings": warnings,
		"manifest": manifest, "sha256": FileAccess.get_sha256(path).to_lower(),
		"size": pack_size
	}

func activate_pack(path: String, descriptor: Dictionary = {}) -> Dictionary:
	var expected_hash := str(descriptor.get("sha256", ""))
	var report := validate_pack(path, expected_hash)
	if not report.get("ok", false):
		return report
	var advertised_size := int(descriptor.get("size", 0))
	if advertised_size > 0 and int(report.get("size", -1)) != advertised_size:
		return {"ok": false, "errors": ["Pack size does not match the reviewed descriptor."], "warnings": []}
	var manifest: Dictionary = report["manifest"]
	var pack_id := str(manifest["id"])
	if pack_id == "core":
		return {"ok": false, "errors": ["The core pack ID is reserved."], "warnings": []}
	_remove_pack_content(pack_id)
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"ok": false, "errors": ["Pack could not be reopened."], "warnings": []}
	for definition_path in manifest.get("definitions", []):
		var parsed = JSON.parse_string(reader.read_file(str(definition_path)).get_string_from_utf8())
		if parsed is Dictionary:
			_register_community_definition(pack_id, parsed)
	reader.close()
	var stored := descriptor.duplicate(true)
	stored.merge({
		"id": pack_id,
		"version": str(manifest["version"]),
		"sha256": report["sha256"],
		"size": report["size"],
		"display_name": str(manifest["name"]),
		"author": str(manifest["author"]),
		"path": path,
		"trusted": false
	}, true)
	_packs[pack_id] = stored
	if pack_id not in _active_pack_ids:
		_active_pack_ids.append(pack_id)
	_active_pack_ids.sort()
	_touch_cache_entry(stored)
	_recompute_content_set_hash()
	return report

func deactivate_community_packs() -> void:
	for pack_id in _active_pack_ids.duplicate():
		if pack_id != "core":
			_remove_pack_content(pack_id)
			_packs.erase(pack_id)
	_active_pack_ids = ["core"]
	_recompute_content_set_hash()

func cache_verified_pack(source_path: String, descriptor: Dictionary) -> Dictionary:
	var report := validate_pack(source_path, str(descriptor.get("sha256", "")))
	if not report.get("ok", false):
		return report
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIRECTORY))
	var destination := "%s/%s.lemonpack" % [CACHE_DIRECTORY, report["sha256"]]
	if source_path != destination:
		var copy_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(source_path),
			ProjectSettings.globalize_path(destination)
		)
		if copy_error != OK:
			return {"ok": false, "errors": ["Could not copy the verified pack into the cache."], "warnings": []}
	var stored := descriptor.duplicate(true)
	stored["sha256"] = report["sha256"]
	stored["size"] = report["size"]
	stored["path"] = destination
	_touch_cache_entry(stored)
	_prune_cache()
	report["path"] = destination
	return report

func cached_pack_path(sha256: String) -> String:
	var normalized := sha256.to_lower()
	var entry: Dictionary = _cache_index.get(normalized, {})
	var path := str(entry.get("path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	entry["last_used"] = Time.get_unix_time_from_system()
	_cache_index[normalized] = entry
	_save_cache_index()
	return path

func instantiate_pack_glb(pack_id: String, asset_path: String) -> Node3D:
	if pack_id == "core" or not _packs.has(pack_id):
		return null
	var pack_path := str(_packs[pack_id].get("path", ""))
	var reader := ZIPReader.new()
	if reader.open(pack_path) != OK:
		return null
	var bytes := reader.read_file(asset_path)
	reader.close()
	if bytes.is_empty():
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes, "", state) != OK:
		return null
	return document.generate_scene(state)

func load_pack_audio(pack_id: String, asset_path: String) -> AudioStream:
	if pack_id == "core" or not _packs.has(pack_id):
		return null
	var pack_path := str(_packs[pack_id].get("path", ""))
	var reader := ZIPReader.new()
	if reader.open(pack_path) != OK:
		return null
	var bytes := reader.read_file(asset_path)
	reader.close()
	if bytes.is_empty():
		return null
	match asset_path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null

func _validate_manifest(manifest: Dictionary, files: PackedStringArray, reader: ZIPReader, errors: Array[String], warnings: Array[String]) -> void:
	if int(manifest.get("schema_version", -1)) != PACK_SCHEMA_VERSION:
		errors.append("Unsupported pack schema version.")
	var pack_id := str(manifest.get("id", ""))
	if not _valid_pack_id(pack_id):
		errors.append("Pack ID must use lowercase letters, digits, dots, underscores, or hyphens.")
	if not _valid_semver(str(manifest.get("version", ""))):
		errors.append("Pack version must be semantic versioning (major.minor.patch).")
	for field in ["name", "author"]:
		var value := str(manifest.get(field, "")).strip_edges()
		if value.is_empty() or value.length() > 80:
			errors.append("Manifest field '%s' is missing or too long." % field)
	var definitions = manifest.get("definitions", [])
	if definitions is not Array or definitions.is_empty():
		errors.append("Manifest must list at least one JSON definition.")
		return
	var seen_ids: Array[String] = []
	for raw_path in definitions:
		var definition_path := str(raw_path)
		if definition_path not in files or definition_path.get_extension().to_lower() != "json":
			errors.append("Missing JSON definition: %s" % definition_path)
			continue
		var parsed = JSON.parse_string(reader.read_file(definition_path).get_string_from_utf8())
		if parsed is not Dictionary:
			errors.append("Definition is not a JSON object: %s" % definition_path)
			continue
		_validate_definition(pack_id, parsed, files, reader, seen_ids, errors, warnings)

func _validate_definition(pack_id: String, definition: Dictionary, files: PackedStringArray, reader: ZIPReader, seen_ids: Array[String], errors: Array[String], warnings: Array[String]) -> void:
	var kind := str(definition.get("kind", ""))
	if kind not in ["weapon", "map", "model"]:
		errors.append("Definition kind must be weapon, map, or model.")
		return
	var local_id := str(definition.get("id", ""))
	if not _valid_local_id(local_id):
		errors.append("Definition ID '%s' is invalid." % local_id)
		return
	var scoped_id := "%s:%s" % [pack_id, local_id]
	if scoped_id in seen_ids:
		errors.append("Duplicate definition ID: %s" % scoped_id)
	seen_ids.append(scoped_id)
	var asset := str(definition.get("asset", ""))
	if asset.is_empty() or asset not in files or asset.get_extension().to_lower() != "glb":
		errors.append("%s must reference an embedded-texture .glb asset." % scoped_id)
		return
	var asset_scene := _parse_glb_scene(reader, asset, scoped_id, errors)
	if not asset_scene:
		return
	if kind == "weapon":
		_validate_weapon_definition(scoped_id, definition, files, errors)
	elif kind == "map":
		_validate_map_definition(scoped_id, definition, asset_scene, errors, warnings)
	else:
		_validate_model_definition(scoped_id, definition, asset_scene, errors)
	asset_scene.free()

func _validate_weapon_definition(scoped_id: String, definition: Dictionary, files: PackedStringArray, errors: Array[String]) -> void:
	if str(definition.get("archetype", "")) not in COMMUNITY_WEAPON_ARCHETYPES:
		errors.append("%s uses an unsupported weapon archetype." % scoped_id)
	for field in ["damage", "rate", "mag", "reserve", "reload", "range", "hip", "ads", "recoil"]:
		if not definition.has(field) or not (definition[field] is int or definition[field] is float):
			errors.append("%s is missing numeric weapon field '%s'." % [scoped_id, field])
	var damage := float(definition.get("damage", 0.0))
	var rate := float(definition.get("rate", 0.0))
	if damage <= 0.0 or damage > 250.0 or rate <= 0.0 or rate > 20.0:
		errors.append("%s has weapon stats outside safe limits." % scoped_id)
	for transform_name in ["first_person_transform", "third_person_transform"]:
		var transform = definition.get(transform_name, {})
		if transform is not Dictionary or not _valid_transform_definition(transform):
			errors.append("%s has an invalid %s." % [scoped_id, transform_name])
	var sounds = definition.get("sounds", {})
	if sounds is not Dictionary:
		errors.append("%s sounds must be an object." % scoped_id)
	else:
		for sound_name in sounds:
			var sound_path := str(sounds[sound_name])
			if sound_path not in files or sound_path.get_extension().to_lower() not in ["ogg", "wav", "mp3"]:
				errors.append("%s sound '%s' is missing or unsupported." % [scoped_id, sound_name])

func _validate_map_definition(scoped_id: String, definition: Dictionary, asset_scene: Node, errors: Array[String], warnings: Array[String]) -> void:
	for marker in ["ffa_spawns", "team_a_spawns", "team_b_spawns", "waypoints"]:
		var entries = definition.get(marker, [])
		if entries is not Array or entries.is_empty():
			errors.append("%s is missing required map marker array '%s'." % [scoped_id, marker])
	for marker in ["ffa_spawns", "team_a_spawns", "team_b_spawns", "waypoints", "hills", "pickups", "vehicles"]:
		var entries = definition.get(marker, [])
		if entries is not Array:
			errors.append("%s map field '%s' must be an array." % [scoped_id, marker])
			continue
		for entry in entries:
			if not _valid_vector_definition(entry):
				errors.append("%s has an invalid vector in '%s'." % [scoped_id, marker])
				break
	var supported_modes = definition.get("supported_modes", [])
	if supported_modes is not Array or supported_modes.is_empty():
		errors.append("%s must support at least one game mode." % scoped_id)
	else:
		for mode in supported_modes:
			if str(mode) not in ["ffa", "tdm", "juggernaut", "infection", "koth"]:
				errors.append("%s has an unsupported game mode." % scoped_id)
	if supported_modes is Array and "koth" in supported_modes and definition.get("hills", []).is_empty():
		errors.append("%s supports KOTH but declares no hill positions." % scoped_id)
	var measured := _measure_scene(asset_scene)
	if int(definition.get("node_count", 0)) != int(measured["nodes"]):
		warnings.append("%s declared node count differs from its measured count." % scoped_id)
	if int(measured["nodes"]) > MAX_MAP_NODES:
		errors.append("%s exceeds the map node limit." % scoped_id)
	if int(definition.get("triangle_count", 0)) != int(measured["triangles"]):
		warnings.append("%s declared triangle count differs from its measured count." % scoped_id)
	if int(measured["triangles"]) > MAX_MAP_TRIANGLES:
		errors.append("%s exceeds the map triangle limit." % scoped_id)
	if definition.get("portal_surfaces", []) is Array and definition.get("portal_surfaces", []).is_empty():
		warnings.append("%s has no portal-compatible surfaces." % scoped_id)

func _validate_model_definition(scoped_id: String, definition: Dictionary, asset_scene: Node, errors: Array[String]) -> void:
	var bones = definition.get("bones", [])
	if bones is not Array:
		errors.append("%s must declare its humanoid bones." % scoped_id)
		return
	var skeleton := _find_skeleton(asset_scene)
	if not skeleton:
		errors.append("%s has no humanoid skeleton." % scoped_id)
		return
	for required_bone in REQUIRED_HUMANOID_BONES:
		if required_bone not in bones:
			errors.append("%s is missing required bone '%s'." % [scoped_id, required_bone])
		if skeleton.find_bone(required_bone) < 0:
			errors.append("%s asset is missing required bone '%s'." % [scoped_id, required_bone])
	if str(definition.get("weapon_attachment", "")) != "hand.R":
		errors.append("%s must use hand.R as its weapon attachment." % scoped_id)

func _parse_glb_scene(reader: ZIPReader, asset_path: String, scoped_id: String, errors: Array[String]) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(reader.read_file(asset_path), "", state) != OK:
		errors.append("%s contains an invalid or externally dependent GLB asset." % scoped_id)
		return null
	var scene := document.generate_scene(state)
	if not scene:
		errors.append("%s GLB asset could not generate a scene." % scoped_id)
	return scene

func _measure_scene(root: Node) -> Dictionary:
	var nodes := 0
	var triangles := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		nodes += 1
		if node is MeshInstance3D and node.mesh:
			for surface_index in node.mesh.get_surface_count():
				if node.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
					continue
				var index_count: int = node.mesh.surface_get_array_index_len(surface_index)
				triangles += (index_count if index_count > 0 else node.mesh.surface_get_array_len(surface_index)) / 3
		for child in node.get_children():
			pending.append(child)
	return {"nodes": nodes, "triangles": triangles}

func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _valid_transform_definition(transform: Dictionary) -> bool:
	for field in ["position", "rotation"]:
		var value = transform.get(field, [])
		if value is not Array or value.size() != 3:
			return false
		for component in value:
			if component is not int and component is not float:
				return false
	var scale = transform.get("scale", 1.0)
	return (scale is int or scale is float) and float(scale) > 0.0 and float(scale) <= 20.0

func _valid_vector_definition(value: Variant) -> bool:
	if value is not Array or value.size() != 3:
		return false
	for component in value:
		if component is not int and component is not float:
			return false
		if not is_finite(float(component)) or absf(float(component)) > 100000.0:
			return false
	return true

func _register_community_definition(pack_id: String, definition: Dictionary) -> void:
	var scoped_id := "%s:%s" % [pack_id, str(definition["id"])]
	var copy := definition.duplicate(true)
	copy["id"] = scoped_id
	copy["pack_id"] = pack_id
	copy["trusted"] = false
	match str(definition["kind"]):
		"weapon":
			copy["automatic"] = str(copy.get("archetype", "")) == "automatic"
			copy["pellets"] = int(copy.get("pellets", 8 if copy.get("archetype") == "shotgun" else 1))
			copy["loadout"] = true
			copy["akimbo"] = bool(copy.get("akimbo", false))
			copy["accuracy"] = clampi(int(copy.get("accuracy", 75)), 1, 100)
			copy["mobility"] = clampi(int(copy.get("mobility", 70)), 1, 100)
			copy["move"] = clampf(float(copy.get("move", 1.0)), 0.75, 1.15)
			var bot = copy.get("bot", {})
			if bot is not Dictionary or bot.is_empty():
				copy["bot"] = {
					"interval": clampf(1.0 / maxf(float(copy.get("rate", 5.0)), 0.1), 0.12, 1.2),
					"damage": minf(float(copy.get("damage", 20.0)) * 0.38, 80.0),
					"accuracy": 1.0, "pitch": 1.0,
					"range": minf(float(copy.get("range", 30.0)), 30.0),
					"pellets": int(copy.get("pellets", 1))
				}
			_weapons[scoped_id] = copy
		"map":
			copy["provider"] = "pack"
			copy["supported_modes"] = copy.get("supported_modes", ["ffa"])
			_maps[scoped_id] = copy
		"model":
			_models[scoped_id] = copy

func _remove_pack_content(pack_id: String) -> void:
	for collection in [_maps, _weapons, _models]:
		for content_id in collection.keys():
			if str(collection[content_id].get("pack_id", "")) == pack_id:
				collection.erase(content_id)

func _public_pack_descriptor(pack: Dictionary) -> Dictionary:
	return {
		"id": str(pack.get("id", "")),
		"version": str(pack.get("version", "")),
		"sha256": str(pack.get("sha256", "")),
		"size": int(pack.get("size", 0)),
		"url": str(pack.get("url", "")),
		"display_name": str(pack.get("display_name", "")),
		"author": str(pack.get("author", ""))
	}

func validate_pack_descriptors(descriptors: Array) -> Dictionary:
	var errors: Array[String] = []
	var total_size := 0
	var seen_ids: Array[String] = []
	var seen_hashes: Array[String] = []
	for raw_descriptor in descriptors:
		if raw_descriptor is not Dictionary:
			errors.append("Pack descriptor is not an object.")
			continue
		var descriptor: Dictionary = raw_descriptor
		var pack_id := str(descriptor.get("id", ""))
		var url := str(descriptor.get("url", ""))
		var sha256 := str(descriptor.get("sha256", "")).to_lower()
		if not _valid_pack_id(pack_id) or pack_id in seen_ids:
			errors.append("Pack descriptor has an invalid or duplicate ID.")
		seen_ids.append(pack_id)
		if not _valid_https_url(url):
			errors.append("%s must use an HTTPS download URL." % pack_id)
		if sha256.length() != 64 or not sha256.is_valid_hex_number(false):
			errors.append("%s has an invalid SHA-256 hash." % pack_id)
		elif sha256 in seen_hashes:
			errors.append("%s duplicates another pack hash." % pack_id)
		seen_hashes.append(sha256)
		var size := int(descriptor.get("size", 0))
		if size <= 0 or size > MAX_PACK_BYTES:
			errors.append("%s has an invalid advertised size." % pack_id)
		total_size += maxi(size, 0)
	if total_size > MAX_JOIN_BYTES:
		errors.append("Required downloads exceed the 512 MB per-join limit.")
	return {"ok": errors.is_empty(), "errors": errors, "total_size": total_size}

func _validate_archive_path(path: String) -> String:
	if path.is_empty() or path.begins_with("/") or path.begins_with("\\") or path.contains("\\"):
		return "Unsafe archive path: %s" % path
	for component in path.split("/"):
		if component in ["", ".", ".."]:
			return "Unsafe archive path: %s" % path
	if path.length() > 240:
		return "Archive path is too long: %s" % path
	return ""

func _valid_pack_id(value: String) -> bool:
	if value.is_empty() or value.length() > 48 or value != value.to_lower():
		return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789._-":
			return false
	return true

func _valid_https_url(value: String) -> bool:
	if not value.begins_with("https://"):
		return false
	var authority := value.trim_prefix("https://").get_slice("/", 0)
	return not authority.is_empty() and "@" not in authority and "." in authority

func _valid_local_id(value: String) -> bool:
	if value.is_empty() or value.length() > 48 or ":" in value or value != value.to_lower():
		return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true

func _valid_semver(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int() or int(part) < 0:
			return false
	return true

func _recompute_content_set_hash() -> void:
	var descriptors: Array = []
	for pack_id in _active_pack_ids:
		var pack: Dictionary = _packs.get(pack_id, {})
		descriptors.append({
			"id": pack_id,
			"version": str(pack.get("version", "")),
			"sha256": str(pack.get("sha256", "core"))
		})
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_stable_json(descriptors).to_utf8_buffer())
	_content_set_hash = context.finish().hex_encode()
	registry_changed.emit(_content_set_hash)

func _stable_json(value: Variant) -> String:
	if value is Dictionary:
		var parts: Array[String] = []
		for key in _sorted_keys(value):
			parts.append("%s:%s" % [JSON.stringify(str(key)), _stable_json(value[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(_stable_json(item))
		return "[%s]" % ",".join(parts)
	return JSON.stringify(value)

func _sorted_keys(dictionary: Dictionary) -> Array:
	var keys := dictionary.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	return keys

func _load_cache_index() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIRECTORY))
	if not FileAccess.file_exists(CACHE_INDEX_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CACHE_INDEX_PATH))
	if parsed is Dictionary:
		_cache_index = parsed

func _touch_cache_entry(descriptor: Dictionary) -> void:
	var sha256 := str(descriptor.get("sha256", "")).to_lower()
	if sha256.is_empty():
		return
	_cache_index[sha256] = {
		"path": str(descriptor.get("path", "%s/%s.lemonpack" % [CACHE_DIRECTORY, sha256])),
		"size": int(descriptor.get("size", 0)),
		"last_used": Time.get_unix_time_from_system(),
		"id": str(descriptor.get("id", "")),
		"version": str(descriptor.get("version", ""))
	}
	_save_cache_index()

func _prune_cache() -> void:
	var total_size := 0
	var entries: Array[Dictionary] = []
	for sha256 in _cache_index:
		var entry: Dictionary = _cache_index[sha256]
		total_size += int(entry.get("size", 0))
		var sortable := entry.duplicate(true)
		sortable["sha256"] = sha256
		entries.append(sortable)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("last_used", 0)) < float(b.get("last_used", 0)))
	for entry in entries:
		if total_size <= MAX_CACHE_BYTES:
			break
		var path := str(entry.get("path", ""))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		total_size -= int(entry.get("size", 0))
		_cache_index.erase(str(entry["sha256"]))
	_save_cache_index()

func _save_cache_index() -> void:
	var file := FileAccess.open(CACHE_INDEX_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_cache_index, "\t"))
