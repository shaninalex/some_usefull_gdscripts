extends Node

## UDP client. Idle until connect_to_server() is called:
## no socket is open and nothing is polled while DISCONNECTED.

enum State {DISCONNECTED, CONNECTING, CONNECTED}

signal state_changed(state: State)
signal connected(player_id: String)
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal snapshot_received(snapshot: Dictionary)
signal message_received(type: String, data: Variant)
signal server_error(code: int, msg: String)

var ping_interval := 1.0
var hello_interval := 1.0
var connect_timeout := 5.0
var server_timeout := 5.0

var state := State.DISCONNECTED
var player_id := ""

var _udp := PacketPeerUDP.new()
var _hello: Message
var _ping_timer := 0.0
var _hello_timer := 0.0
var _connect_timer := 0.0
var _silence_timer := 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	poll_events()

	match state:
		State.CONNECTING:
			_connect_timer += delta
			if _connect_timer >= connect_timeout:
				_close()
				connection_failed.emit("timeout")
				return

			_hello_timer += delta
			if _hello_timer >= hello_interval:
				_hello_timer = 0.0
				send_message(_hello)

		State.CONNECTED:
			_silence_timer += delta
			if _silence_timer >= server_timeout:
				disconnect_from_server("timeout")
				return

			_ping_timer += delta
			if _ping_timer >= ping_interval:
				_ping_timer = 0.0
				send_command("session.ping", {})


func _exit_tree() -> void:
	_close()


func connect_to_server(host: String, port: int, nickname: String) -> Error:
	if state != State.DISCONNECTED:
		push_warning("network: already %s" % State.keys()[state])
		return ERR_ALREADY_IN_USE

	var err := _udp.connect_to_host(host, port)
	if err != OK:
		push_error("network: cannot open UDP socket to %s:%d (%s)" % [host, port, error_string(err)])
		return err

	_hello = Message.new("session.hello", {"ip": host, "nickname": nickname})
	_connect_timer = 0.0
	_hello_timer = 0.0
	_set_state(State.CONNECTING)
	set_process(true)
	send_message(_hello)
	return OK


func disconnect_from_server(reason:="client") -> void:
	if state == State.DISCONNECTED:
		return

	var was_connected := state == State.CONNECTED
	_close()
	if was_connected:
		disconnected.emit(reason)
	else:
		connection_failed.emit(reason)


func is_online() -> bool:
	return state == State.CONNECTED


func send_command(type: String, payload: Dictionary) -> void:
	if not is_online():
		push_warning("network: dropping %s, not connected" % type)
		return

	send_message(Message.new(type, payload, player_id))


func send_message(message: Message) -> void:
	if state == State.DISCONNECTED:
		return

	var packet := JSON.stringify(message.to_dict()).to_utf8_buffer()
	_udp.put_packet(packet)


func poll_events() -> void:
	if state == State.DISCONNECTED:
		return

	while state != State.DISCONNECTED and _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		if _udp.get_packet_error() != OK:
			continue

		var message = JSON.parse_string(packet.get_string_from_utf8())
		if not message is Dictionary:
			push_warning("network: malformed packet dropped")
			continue

		_silence_timer = 0.0

		# Server errors come without a "type" field: { msg, code }.
		if not message.has("type"):
			if message.has("msg"):
				server_error.emit(int(message.get("code", 0)), str(message.msg))
			continue

		match message.type:
			"session.welcome":
				_on_welcome(message.get("data", {}))
			"session.pong":
				pass # keepalive only; receiving it already reset _silence_timer
			"snapshot":
				if is_online():
					snapshot_received.emit(message.get("data"))
			var type:
				if is_online():
					message_received.emit(type, message.get("data"))


func _on_welcome(data: Dictionary) -> void:
	# Late welcome for a retried hello; we already have a session.
	if state != State.CONNECTING:
		return

	player_id = str(data.get("player_id", ""))
	if player_id.is_empty():
		push_warning("network: welcome without player_id")
		return

	_ping_timer = 0.0
	_silence_timer = 0.0
	_set_state(State.CONNECTED)
	connected.emit(player_id)

	if data.has("snapshot"):
		snapshot_received.emit(data.snapshot)


func _close() -> void:
	_udp.close()
	player_id = ""
	_hello = null
	set_process(false)
	_set_state(State.DISCONNECTED)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
