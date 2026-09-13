## Headless smoke test for the dialogue box.
##
## Loads the dialogue box scene, starts the Balaam/donkey conversation, and
## verifies that the first segment's speaker name, portrait, and text are all
## populated. Also simulates a real tap/click - which, thanks to Godot's
## default "emulate_mouse_from_touch" project setting, delivers both an
## [InputEventScreenTouch] and a synthetic [InputEventMouseButton] for a
## single physical tap - to confirm the dialogue box advances exactly one
## segment per tap (regression test for a bug where every tap silently
## advanced two segments, hiding every other line, e.g. all of Balaam's
## lines since he only speaks on odd-indexed segments).
##
## The project must have imported its resources at least once (e.g. via a
## prior editor run, or `godot --headless --import`) so that portrait PNGs
## have associated .import files; otherwise texture loading will fail
## regardless of this fix. Run with:
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

		_simulate_tap(dialogue_box)
		if speaker_label.text != "Balaam":
			failures.append(
				"Expected one tap to advance to speaker 'Balaam', got '%s' (each tap likely advanced more than one segment)." % speaker_label.text
			)

	if failures.is_empty():
		print("PASS: dialogue box shows speaker portrait and text, advancing once per tap.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


## Simulates a single physical tap/click by delivering both an
## [InputEventScreenTouch] and a synthetic [InputEventMouseButton] press
## (followed by their releases), mirroring what Godot's default
## "input_devices/pointing/emulate_mouse_from_touch" project setting does
## for a real tap on a touch-capable device.
func _simulate_tap(dialogue_box: Control) -> void:
	var touch_press := InputEventScreenTouch.new()
	touch_press.pressed = true
	dialogue_box._on_gui_input(touch_press)

	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	dialogue_box._on_gui_input(mouse_press)

	var touch_release := InputEventScreenTouch.new()
	touch_release.pressed = false
	dialogue_box._on_gui_input(touch_release)

	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.pressed = false
	dialogue_box._on_gui_input(mouse_release)
