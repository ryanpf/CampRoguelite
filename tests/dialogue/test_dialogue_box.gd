## Headless smoke test for the dialogue box.
##
## Loads the dialogue box scene, starts the Balaam/donkey conversation, and
## verifies that the first segment's speaker name, portrait, and text are all
## populated. The project must have imported its resources at least once
## (e.g. via a prior editor run, or `godot --headless --import`) so that
## portrait PNGs have associated .import files; otherwise texture loading
## will fail regardless of this fix. Run with:
##
##   godot --headless --import
##   godot --headless --script res://tests/dialogue/test_dialogue_box.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree

const CONVERSATION_PATH := "res://data/conversations/balaam_and_donkey.yml"


## Note: uses [method MainLoop._initialize] rather than [method Object._init],
## since [method SceneTree.quit]'s exit code is only honored when called from
## [method MainLoop._initialize] onward (calling it from [method Object._init]
## always results in a zero exit code).
func _initialize() -> void:
	var failures: Array[String] = []

	var dialogue_box := (load("res://scenes/dialogue/dialogue_box.tscn") as PackedScene).instantiate()
	get_root().add_child(dialogue_box)
	# Wait a frame so the dialogue box's own _ready() (and its @onready node
	# references) run before we start a conversation on it.
	await process_frame

	if not dialogue_box.has_method("start_conversation"):
		failures.append(
			"DialogueBox is missing start_conversation() - its script likely failed to parse/load."
		)
	else:
		dialogue_box.start_conversation(CONVERSATION_PATH)

		var speaker_label: Label = dialogue_box.get_node("SpeakerTab/SpeakerLabel")
		var speaker_portrait: TextureRect = dialogue_box.get_node("SpeakerPortrait")
		var dialogue_text: RichTextLabel = dialogue_box.get_node("DialogueBox/DialogueText")

		if speaker_label.text != "Balaam's Donkey":
			failures.append(
				"Expected speaker label 'Balaam's Donkey', got '%s'" % speaker_label.text
			)
		if dialogue_text.text.is_empty():
			failures.append("Expected dialogue text to be populated, but it was empty.")
		if speaker_portrait.texture == null:
			failures.append("Expected speaker portrait texture to be set, but it was null.")
		if not speaker_portrait.visible:
			failures.append("Expected speaker portrait to be visible, but it was hidden.")

	if failures.is_empty():
		print("PASS: dialogue box shows speaker portrait and text.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
