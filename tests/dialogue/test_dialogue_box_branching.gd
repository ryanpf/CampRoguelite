## Headless smoke test for [DialogueBox]'s conversation branching support.
##
## Loads the dialogue box scene, starts the "crossroads" branching
## conversation (see data/conversations/crossroads.yml), advances to the
## branch node, verifies it shows a card-select UI with one card per
## response card in the player's inventory (see data/response_cards.yml)
## alongside (not instead of) the still-visible dialogue text, plays a card
## with hidden value 2, and verifies playback jumps to the value-2 option's
## target segment and later converges back onto the shared closing line via
## its "next". Also restarts the conversation and plays a value-1 card to
## verify its branch's "next: end" ends the conversation immediately rather
## than converging onto the shared closing line.
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

	if not dialogue_text.text.begins_with("Which path shall we take?"):
		failures.append("Expected the opening line, got '%s'." % dialogue_text.text)
	if branch_options.visible:
		failures.append("Expected branch options to be hidden before reaching the branch node.")

	# Advance (tap) from the opening line onto the branch node.
	_simulate_tap(dialogue_box)

	if not branch_options.visible:
		failures.append("Expected branch options to be visible at the branch node.")
	var inventory_size: int = dialogue_box.response_cards.size()
	if inventory_size == 0:
		failures.append("Expected the player's response card inventory to be loaded.")
	if branch_options.card_count() != inventory_size:
		failures.append(
			"Expected one card per response card in the inventory (%d), got %d." % [inventory_size, branch_options.card_count()]
		)
	if not dialogue_panel.visible:
		failures.append("Expected the normal dialogue panel to stay visible alongside a branch's cards.")

	# Tapping/clicking to advance must do nothing while a branch is active;
	# the player must select a card instead.
	_simulate_tap(dialogue_box)
	if not branch_options.visible:
		failures.append("Expected tapping to be ignored while a branch's cards await selection.")

	# Play a response card with hidden value 2 (the "river" branch).
	dialogue_box.play_response_card(_card_index_with_value(dialogue_box, 2))

	if branch_options.visible:
		failures.append("Expected branch options to hide again after a card is played.")
	if dialogue_text.text != "The river road, then. Slow and gentle, as the saints intended.":
		failures.append(
			"Expected a value-2 card to jump to the 'river' branch, got '%s'." % dialogue_text.text
		)

	# The "river" segment's "next: reunited" should converge back onto the
	# shared closing line on the very next advance.
	_simulate_tap(dialogue_box)
	if dialogue_text.text != "Onward, regardless of the path taken.":
		failures.append(
			"Expected the 'river' branch to converge onto the shared closing line, got '%s'." % dialogue_text.text
		)

	# Once the conversation has converged onto its natural ending, one more
	# tap should finish it normally (baseline for comparison with the early
	# ending exercised below).
	_simulate_tap(dialogue_box)
	if dialogue_box.visible:
		failures.append("Expected the conversation to finish (hide) after its natural ending line.")

	# Restart the conversation and this time play a value-1 card, whose
	# "refuse" branch ends with "next: end" - verify that ends the
	# conversation immediately, skipping the shared closing line entirely.
	dialogue_box.start_conversation(CONVERSATION_PATH)
	_simulate_tap(dialogue_box)
	dialogue_box.play_response_card(_card_index_with_value(dialogue_box, 1))
	if dialogue_text.text != "Not one more hoof forward. Back to camp, and be quick about it.":
		failures.append(
			"Expected a value-1 card to jump to the 'refuse' branch, got '%s'." % dialogue_text.text
		)
	if not dialogue_box.visible:
		failures.append("Expected the dialogue box to still be visible on the 'refuse' line.")

	_simulate_tap(dialogue_box)
	if dialogue_box.visible:
		failures.append(
			"Expected 'next: end' to finish the conversation immediately, but the dialogue box is still visible (text: '%s')." % dialogue_text.text
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


## Returns the index (into [param dialogue_box]'s response card inventory)
## of the first card with hidden value [param value], or [code]-1[/code].
func _card_index_with_value(dialogue_box: Control, value: int) -> int:
	var cards: Array[Dictionary] = dialogue_box.response_cards
	for i in cards.size():
		if int(cards[i]["value"]) == value:
			return i
	return -1


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
