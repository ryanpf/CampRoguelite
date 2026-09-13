## UI component that plays back a conversation loaded via [DialogueParser].
## Displays the active speaker's portrait above the dialogue text box, along
## with their name on a visual "tab", and advances to the next segment when
## tapped/clicked.
extends Control

signal conversation_finished

## Default character file used to resolve conversation "speaker" ids to
## display names and portraits.
const DEFAULT_CHARACTERS_PATH := "res://data/characters.yml"

@onready var speaker_tab: Panel = $SpeakerTab
@onready var speaker_label: Label = $SpeakerTab/SpeakerLabel
@onready var speaker_portrait: TextureRect = $SpeakerPortrait
@onready var dialogue_text: RichTextLabel = $DialogueBox/DialogueText
@onready var dialogue_box: Panel = $DialogueBox

var _segments: Array[Dictionary] = []
var _characters: Dictionary = {}
var _index: int = -1

## Whether a press is currently being tracked, waiting for its matching
## release. Guards against advancing twice per tap: by default Godot's
## "input_devices/pointing/emulate_mouse_from_touch" project setting makes a
## single touch also emit a synthetic mouse button event, so a tap/click can
## otherwise deliver two "pressed" events to [method _on_gui_input].
var _awaiting_release: bool = false


func _ready() -> void:
	gui_input.connect(_on_gui_input)


## Loads the conversation at [param path] and starts playing it back,
## resolving speakers against the character file at [param characters_path].
func start_conversation(path: String, characters_path: String = DEFAULT_CHARACTERS_PATH) -> void:
	_characters = CharacterParser.load_characters(characters_path)
	_segments = DialogueParser.load_conversation(path)
	_index = -1
	visible = not _segments.is_empty()
	advance()


## Advances to the next dialogue segment, or hides the box and emits
## [signal conversation_finished] once the conversation is complete.
func advance() -> void:
	_index += 1
	if _index >= _segments.size():
		visible = false
		conversation_finished.emit()
		return

	var segment := _segments[_index]
	var character_id := str(segment.get("speaker", ""))
	var character: Dictionary = _characters.get(character_id, {})
	speaker_label.text = str(character.get("name", character_id))
	var portrait: Texture2D = character.get("portrait")
	speaker_portrait.texture = portrait
	speaker_portrait.visible = portrait != null
	dialogue_text.text = str(segment.get("text", ""))


func _on_gui_input(event: InputEvent) -> void:
	var is_press: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	var is_release: bool = (event is InputEventMouseButton and not event.pressed) \
		or (event is InputEventScreenTouch and not event.pressed)
	if is_press and not _awaiting_release:
		_awaiting_release = true
		advance()
	elif is_release:
		_awaiting_release = false
