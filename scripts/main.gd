extends Control

@onready var version_label: Label = $VersionLabel

func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = "Version %s" % version
