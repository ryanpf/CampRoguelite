extends Control

const EXAMPLE_CONVERSATION := "res://data/conversations/balaam_and_donkey.yml"

@onready var version_label: Label = $VersionLabel
@onready var dialogue_box: Control = $DialogueBox

func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = "Version %s" % version
	dialogue_box.start_conversation(EXAMPLE_CONVERSATION)
