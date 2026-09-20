## Headless smoke test for [DialogueBox]'s branch response timeout: verifies
## a countdown is shown while a branch's cards await selection, and that
## letting it run out (rather than tapping a card) automatically selects the
## option flagged "special: true" (see data/conversations/branch_timeout.yml),
## jumping playback to that option's target exactly as a manual selection
## would.
##
## The project must have imported its resources at least once (e.g. via a
## prior editor run, or `godot --headless --import`). Run with:
##
##   godot --headless --import
##   godot --headless --script res://tests/dialogue/test_dialogue_box_branch_timeout.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree

const CONVERSATION_PATH := "res://data/conversations/branch_timeout.yml"


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

	dialogue_box.start_conversation(CONVERSATION_PATH)

	var dialogue_text: RichTextLabel = dialogue_box.get_node("DialogueBox/DialogueText")
	var branch_options: CardSwiper = dialogue_box.get_node("BranchOptions")
	var branch_timeout_label: Label = dialogue_box.get_node("BranchTimeoutLabel")
	var branch_timer: Timer = dialogue_box.get_node("BranchTimer")

	if branch_timeout_label.visible:
		failures.append("Expected the timeout countdown to be hidden before reaching the branch node.")

	# Advance (tap) from the opening line onto the branch node, whose
	# "timeout: 0.05" overrides the default countdown to a fraction of a
	# second so this test doesn't have to wait long.
	_simulate_tap(dialogue_box)

	if not branch_options.visible:
		failures.append("Expected branch options to be visible at the branch node.")
	if not branch_timeout_label.visible:
		failures.append("Expected the timeout countdown to become visible once a branch is shown.")
	if branch_timer.is_stopped():
		failures.append("Expected the branch timeout timer to be running once a branch is shown.")

	# Let the branch's overridden 0.05s timeout run out without selecting a
	# card, then give the timer's signal a moment to fire.
	await create_timer(0.2).timeout

	if branch_options.visible:
		failures.append("Expected branch options to hide once the timeout auto-selected an option.")
	if branch_timeout_label.visible:
		failures.append("Expected the timeout countdown to hide once the timeout auto-selected an option.")
	if dialogue_text.text != "Perhaps it is wiser to turn back for camp.":
		failures.append(
			"Expected the timeout to auto-select the 'special: true' option ('turn_back'), got '%s'." % dialogue_text.text
		)

	# The "turn_back" segment's "next: end" should finish the conversation
	# immediately on the next advance, same as a manual selection would.
	_simulate_tap(dialogue_box)
	if dialogue_box.visible:
		failures.append(
			"Expected 'next: end' to finish the conversation after the auto-selected branch, but the dialogue box is still visible (text: '%s')." % dialogue_text.text
		)

	# Let in-flight card fade tweens (from CardSwiper's selection animation)
	# finish before tearing down the tree, to avoid benign "freed before
	# starting" tween warnings on exit.
	await process_frame

	if failures.is_empty():
		print("PASS: dialogue box shows a countdown at branch nodes and auto-selects the special option once it runs out.")
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
