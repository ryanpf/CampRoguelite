## UI component that plays back a conversation loaded via [DialogueParser].
## Displays the speaker's name on a visual "tab" above the dialogue text box,
## and advances to the next segment when tapped/clicked.
extends Control

signal conversation_finished

@onready var speaker_tab: Panel = $SpeakerTab
@onready var speaker_label: Label = $SpeakerTab/SpeakerLabel
@onready var dialogue_text: RichTextLabel = $DialogueBox/DialogueText
@onready var dialogue_box: Panel = $DialogueBox

var _segments: Array[Dictionary] = []
var _index: int = -1


func _ready() -> void:
	gui_input.connect(_on_gui_input)


## Loads the conversation at [param path] and starts playing it back.
func start_conversation(path: String) -> void:
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
	speaker_label.text = str(segment.get("speaker", ""))
	dialogue_text.text = str(segment.get("text", ""))


func _on_gui_input(event: InputEvent) -> void:
	var is_press: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if is_press:
		advance()
