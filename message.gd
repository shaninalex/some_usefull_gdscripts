# Usage ( look for network.gd ):
#	msg = Message.new("session.hello", {"some": "dictionary data"}, player_str_id)
#	Network.send_message(msg)

class_name Message
extends RefCounted

var action: String
var timestamp: String
var initiator: String
var data: Dictionary

func _init(
	p_action: String,
	p_data: Dictionary = {},
	p_initiator: String = "",
) -> void:
	action = p_action
	data = p_data
	initiator = p_initiator
	timestamp = Time.get_datetime_string_from_system()

func to_dict() -> Dictionary:
	return {
		"action": action,
		"timestamp": timestamp,
		"initiator": initiator,
		"data": data,
	}



