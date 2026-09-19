## Headless smoke test for [DialogueBox]'s conversation branching support.
##
## Loads the dialogue box scene, starts the "crossroads" branching
## conversation (see data/conversations/crossroads.yml), advances to the
## branch node, verifies it shows a card-select UI with one card per option
## instead of a dialogue line, selects the second option, and verifies
## playback jumps to that option's target segment and later converges back
## onto the shared closing line via its "next".
##
## The project must have imported its resources at least once (e.g. via a
## prior editor run, or `godot --headless --import`). Run with:
##
##   godot --headless --import
##   godot --headless --script res://tests/dialogue/test_dialogue_box_branching.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree

const CONVERSATION_PATH := "res://data/conversations/crossroads.yml"


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
	var dialogue_panel: Panel = dialogue_box.get_node("DialogueBox")

	if dialogue_text.text != "Which path shall we take?":
		failures.append("Expected the opening line, got '%s'." % dialogue_text.text)
	if branch_options.visible:
		failures.append("Expected branch options to be hidden before reaching the branch node.")

	# Advance (tap) from the opening line onto the branch node.
	_simulate_tap(dialogue_box)

	if not branch_options.visible:
		failures.append("Expected branch options to be visible at the branch node.")
	if dialogue_panel.visible:
		failures.append("Expected the normal dialogue panel to be hidden while a branch is active.")

	# Tapping/clicking to advance must do nothing while a branch is active;
	# the player must select a card instead.
	_simulate_tap(dialogue_box)
	if not branch_options.visible:
		failures.append("Expected tapping to be ignored while a branch's cards await selection.")

	# Select the second option ("river").
	dialogue_box.select_branch_option(1)

	if branch_options.visible:
		failures.append("Expected branch options to hide again after a selection.")
	if dialogue_text.text != "The river runs swift and cold.":
		failures.append(
			"Expected playback to jump to the 'river' branch, got '%s'." % dialogue_text.text
		)

	# The "river" segment's "next: reunited" should converge back onto the
	# shared closing line on the very next advance.
	_simulate_tap(dialogue_box)
	if dialogue_text.text != "Onward, regardless of the path taken.":
		failures.append(
			"Expected the 'river' branch to converge onto the shared closing line, got '%s'." % dialogue_text.text
		)

	# Let in-flight card fade tweens (from CardSwiper's selection animation)
	# finish before tearing down the tree, to avoid benign "freed before
	# starting" tween warnings on exit.
	await process_frame

	if failures.is_empty():
		print("PASS: dialogue box shows a card select at branch nodes and follows the selected branch.")
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
