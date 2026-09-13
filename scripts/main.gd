extends Control

const EXAMPLE_CONVERSATION := "res://data/conversations/balaam_and_donkey.yml"

@onready var version_label: Label = $VersionLabel
@onready var start_conversation_button: Button = $StartConversationButton
@onready var dialogue_box: Control = $DialogueBox

func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = "Version %s" % version
	start_conversation_button.pressed.connect(_on_start_conversation_button_pressed)
	dialogue_box.conversation_finished.connect(_on_conversation_finished)


func _on_start_conversation_button_pressed() -> void:
	start_conversation_button.visible = false
	dialogue_box.start_conversation(EXAMPLE_CONVERSATION)


func _on_conversation_finished() -> void:
	start_conversation_button.visible = true
