extends RefCounted
class_name EventInfo

const TYPE_DIAGONAL_LASERS := 0
const TYPE_SQUARE_LASERS := 1
const TYPE_LEFT_WAVING_LASERS := 2
const TYPE_RIGHT_WAVING_LASERS := 3
const TYPE_FLOOR_LIGHTS := 4

const VALUE_LIGHTS_OFF := 0
const VALUE_LIGHTS_RIGHT_ON := 1
const VALUE_LIGHTS_RIGHT_FLASH := 2
const VALUE_LIGHTS_RIGHT_FADE := 3
const VALUE_LIGHTS_FADE_TO_RIGHT := 4
const VALUE_LIGHTS_LEFT_ON := 5
const VALUE_LIGHTS_LEFT_FLASH := 6
const VALUE_LIGHTS_LEFT_FADE := 7
const VALUE_LIGHTS_FADE_TO_LEFT := 8
const VALUE_LIGHTS_WHITE_ON := 9
const VALUE_LIGHTS_WHITE_FLASH := 10
const VALUE_LIGHTS_WHITE_FADE := 11
const VALUE_LIGHTS_FADE_TO_WHITE := 12
const VALUE_EARLY_LANE_ROTATION := 14
const VALUE_LATE_LANE_ROTATION := 15

var beat: float
var type: int
var value: int
var float_value: float
var custom_color := Utils.NO_COLOR # Chroma, alpha 0 = none
# The next event of the same type, linked by Map after loading.
var next_same_type: EventInfo

@warning_ignore("shadowed_variable")
func _init(beat: float, type: int, value: int, float_value: float) -> void:
	self.beat = beat
	self.type = type
	self.value = value
	self.float_value = float_value

static func new_v2(event_dict: Dictionary) -> EventInfo:
	var info := EventInfo.new(
		Utils.get_float(event_dict, "_time", 0.0),
		int(Utils.get_float(event_dict, "_type", 0)),
		int(Utils.get_float(event_dict, "_value", 0)),
		Utils.get_float(event_dict, "_floatValue", -1.0)
	)
	info.custom_color = Utils.get_custom_color(event_dict, true)
	return info

static func new_v3(event_dict: Dictionary) -> EventInfo:
	var info := EventInfo.new(
		Utils.get_float(event_dict, "b", 0.0),
		int(Utils.get_float(event_dict, "et", 0)),
		int(Utils.get_float(event_dict, "i", 0)),
		Utils.get_float(event_dict, "f", -1.0)
	)
	info.custom_color = Utils.get_custom_color(event_dict, false)
	return info
