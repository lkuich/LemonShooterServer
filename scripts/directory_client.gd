extends Node

signal public_servers_changed(servers: Array)
signal directory_error(message: String)

const DEFAULT_DIRECTORY_URL := "https://lemonshooter-web-staging.loren-jk3.workers.dev/api/v1"
const HEARTBEAT_INTERVAL := 60.0

var directory_url := DEFAULT_DIRECTORY_URL
var lease_id := ""
var lease_token := ""
var heartbeat_remaining := 0.0
var _request: HTTPRequest
var _list_request: HTTPRequest
var _operation := ""
var _pending_registration := false
var _pending_delete := false

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 12.0
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	_list_request = HTTPRequest.new()
	_list_request.timeout = 12.0
	add_child(_list_request)
	_list_request.request_completed.connect(_on_list_completed)
	_load_directory_url()
	NetworkSession.lobby_changed.connect(_on_lobby_changed)
	set_process(true)

func _process(delta: float) -> void:
	if lease_id.is_empty():
		return
	heartbeat_remaining -= delta
	if heartbeat_remaining <= 0.0 and _operation.is_empty():
		_send_heartbeat()

func list_public(filters: Dictionary = {}) -> void:
	if _list_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_list_request.cancel_request()
	var query_parts: Array[String] = []
	for key in ["text", "mode", "map", "region", "phase", "modded", "open", "limit"]:
		if filters.has(key) and not str(filters[key]).is_empty():
			query_parts.append("%s=%s" % [key.uri_encode(), str(filters[key]).uri_encode()])
	var url := "%s/servers" % directory_url
	if not query_parts.is_empty():
		url += "?" + "&".join(query_parts)
	var error := _list_request.request(url, ["Accept: application/json"])
	if error != OK:
		directory_error.emit("Could not contact the public directory.")

func request_registration() -> void:
	if not NetworkSession.is_host or not NetworkSession.public_listing:
		return
	if not lease_id.is_empty():
		return
	if not _operation.is_empty():
		_pending_registration = true
		return
	_operation = "register"
	var error := _request.request(
		"%s/servers/register" % directory_url,
		["Content-Type: application/json", "Accept: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(NetworkSession.get_server_metadata())
	)
	if error != OK:
		_operation = ""
		directory_error.emit("Public directory registration could not start.")

func deregister() -> void:
	if lease_id.is_empty():
		return
	if _operation != "":
		_pending_delete = true
		_pending_registration = false
		return
	_operation = "delete"
	var error := _request.request(
		"%s/servers/%s" % [directory_url, lease_id],
		["Authorization: Bearer %s" % lease_token],
		HTTPClient.METHOD_DELETE
	)
	if error != OK:
		_operation = ""
		_clear_lease()

func _send_heartbeat() -> void:
	if lease_id.is_empty():
		return
	_operation = "heartbeat"
	var error := _request.request(
		"%s/servers/%s/heartbeat" % [directory_url, lease_id],
		["Authorization: Bearer %s" % lease_token, "Content-Type: application/json"],
		HTTPClient.METHOD_PUT,
		JSON.stringify(NetworkSession.get_server_metadata())
	)
	if error != OK:
		_operation = ""
		heartbeat_remaining = 10.0

func _on_lobby_changed(_snapshot: Dictionary) -> void:
	if NetworkSession.is_host and NetworkSession.public_listing:
		if lease_id.is_empty():
			request_registration()
		elif _operation.is_empty():
			heartbeat_remaining = minf(heartbeat_remaining, 2.0)
	elif not lease_id.is_empty():
		deregister()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var completed_operation := _operation
	_operation = ""
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_directory_failure(completed_operation, "Public directory request failed.")
	elif completed_operation == "register" and response_code == 201 and parsed is Dictionary:
		lease_id = str(parsed.get("id", ""))
		lease_token = str(parsed.get("lease_token", ""))
		heartbeat_remaining = float(parsed.get("heartbeat_seconds", HEARTBEAT_INTERVAL))
		if lease_id.is_empty() or lease_token.is_empty():
			_clear_lease()
			directory_error.emit("Public directory returned an invalid lease.")
	elif completed_operation == "heartbeat" and response_code == 200:
		heartbeat_remaining = HEARTBEAT_INTERVAL
	elif completed_operation == "delete":
		_clear_lease()
	else:
		var message := str(parsed.get("message", "Public directory rejected the request.")) if parsed is Dictionary else "Public directory rejected the request."
		_handle_directory_failure(completed_operation, message)
	if _pending_delete:
		_pending_delete = false
		deregister()
	elif _pending_registration:
		_pending_registration = false
		request_registration()

func _on_list_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		directory_error.emit("Public server list is unavailable.")
		public_servers_changed.emit([])
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is not Dictionary or parsed.get("servers", []) is not Array:
		directory_error.emit("Public directory response was malformed.")
		public_servers_changed.emit([])
		return
	public_servers_changed.emit(parsed["servers"])

func _handle_directory_failure(operation: String, message: String) -> void:
	if operation in ["register", "heartbeat"]:
		_clear_lease()
		heartbeat_remaining = 15.0
	directory_error.emit(message)

func _clear_lease() -> void:
	lease_id = ""
	lease_token = ""
	heartbeat_remaining = 0.0

func _load_directory_url() -> void:
	if DedicatedServer.active:
		directory_url = str(DedicatedServer.settings.get("directory_url", DEFAULT_DIRECTORY_URL)).trim_suffix("/")
		if NetworkSession.public_listing:
			call_deferred("request_registration")
		return
	var file := ConfigFile.new()
	if file.load("user://server_browser.cfg") == OK:
		var configured := str(file.get_value("directory", "url", DEFAULT_DIRECTORY_URL)).strip_edges()
		if configured.begins_with("https://"):
			directory_url = configured.trim_suffix("/")
