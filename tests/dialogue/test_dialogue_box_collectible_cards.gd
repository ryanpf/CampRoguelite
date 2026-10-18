## Headless smoke test for [DialogueBox]'s collectible response cards, using
## the "meeting Kelly" introductory conversation (see
## data/conversations/meeting_kelly.yml) and its response card deck (see
## data/response_cards_introductions.yml).
##
## Verifies that the collect icon is shown only on segments offering a
## card, that tapping it adds the card to the player's inventory without
## advancing the dialogue, that the collected card is offered at later
## branches (and stays in the inventory across conversations), that a
## card already held isn't offered again, and that an offered card's
## draining bar runs out after which its icon grays and (outside debug
## mode) can no longer be collected.
##
## The project must have imported its resources at least once (e.g. via a
## prior editor run, or `godot --headless --import`). Run with:
##
##   godot --headless --import
##   godot --headless --script res://tests/dialogue/test_dialogue_box_collectible_cards.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree

const CONVERSATION_PATH := "res://data/conversations/meeting_kelly.yml"
const CHARACTERS_PATH := "res://data/characters.yml"
const RESPONSE_CARDS_PATH := "res://data/response_cards_introductions.yml"

const GLOW_STICKS_CARD_TEXT := "Psst... which counselor gives out the extra glow sticks?"


func _initialize() -> void:
	var failures: Array[String] = []

	var dialogue_box := (load("res://scenes/dialogue/dialogue_box.tscn") as PackedScene).instantiate()
	get_root().add_child(dialogue_box)
	await process_frame

	var dialogue_text: RichTextLabel = dialogue_box.get_node("DialogueBox/DialogueText")
	var branch_options: CardSwiper = dialogue_box.get_node("BranchOptions")
	var collect_card_button: Button = dialogue_box.get_node("CollectCardButton")

	var collected: Array[Dictionary] = []
	dialogue_box.response_card_collected.connect(func(card: Dictionary) -> void: collected.append(card))

	_start(dialogue_box)
	var deck_size: int = dialogue_box.response_cards.size()
	if collect_card_button.visible:
		failures.append("Expected no collect icon on Kelly's opening line.")

	# Kelly's reply to a curious card offers the glow sticks card.
	_simulate_tap(dialogue_box)
	_simulate_tap(dialogue_box)
	if collect_card_button.visible:
		failures.append("Expected no collect icon while a branch's cards are shown.")
	dialogue_box.play_response_card(_card_index_with_tags(dialogue_box, ["curious", "friendly"]))
	if collect_card_button.visible:
		failures.append("Expected no collect icon on the player's own line.")
	_simulate_tap(dialogue_box)
	if not dialogue_text.text.begins_with("Seriously! Like, I know which bunk"):
		failures.append("Expected Kelly's reply to a curious card, got '%s'." % dialogue_text.text)
	if not collect_card_button.visible:
		failures.append("Expected a collect icon on Kelly's glow sticks line.")

	# Collecting it adds the card without advancing the dialogue.
	collect_card_button.pressed.emit()
	if collect_card_button.visible:
		failures.append("Expected the collect icon to hide once its card is collected.")
	if not dialogue_text.text.begins_with("Seriously! Like, I know which bunk"):
		failures.append("Expected collecting a card not to advance the dialogue, got '%s'." % dialogue_text.text)
	if dialogue_box.response_cards.size() != deck_size + 1:
		failures.append("Expected the collected card to join the %d-card deck, got %d cards." % [deck_size, dialogue_box.response_cards.size()])
	elif dialogue_box.response_cards[deck_size]["text"] != GLOW_STICKS_CARD_TEXT \
			or Array(dialogue_box.response_cards[deck_size]["tags"]) != ["curious", "friendly"]:
		failures.append("Unexpected collected card: %s." % [dialogue_box.response_cards[deck_size]])
	if collected.size() != 1 or collected[0].get("text") != GLOW_STICKS_CARD_TEXT:
		failures.append("Expected response_card_collected to fire once with the glow sticks card, got %s." % [collected])
	dialogue_box.collect_response_card()
	if dialogue_box.response_cards.size() != deck_size + 1 or collected.size() != 1:
		failures.append("Expected a card to be collectible only once.")

	# The collected card is offered (and playable) at the next branch.
	_simulate_tap(dialogue_box)
	_simulate_tap(dialogue_box)
	if not branch_options.visible:
		failures.append("Expected the pudding branch after Kelly's pudding line.")
	elif branch_options.card_count() != deck_size + 2:
		failures.append("Expected the collected card (plus the debug timeout card) at the next branch, got %d cards." % branch_options.card_count())
	dialogue_box.play_response_card(deck_size)
	if dialogue_text.text != GLOW_STICKS_CARD_TEXT:
		failures.append("Expected the collected card to be playable as the player's line, got '%s'." % dialogue_text.text)
	_simulate_tap(dialogue_box)
	if not dialogue_text.text.begins_with("Okay, so. Some people think it's banana."):
		failures.append("Expected the collected card's 'curious' tag to pick the pudding branch, got '%s'." % dialogue_text.text)

	# Collected cards stay in the inventory for later conversations, and a
	# card already held isn't offered again.
	_start(dialogue_box)
	if dialogue_box.response_cards.size() != deck_size + 1 \
			or dialogue_box.response_cards[deck_size]["text"] != GLOW_STICKS_CARD_TEXT:
		failures.append("Expected the collected card to stay in the deck for the next conversation.")
	_simulate_tap(dialogue_box)
	_simulate_tap(dialogue_box)
	dialogue_box.play_response_card(_card_index_with_tags(dialogue_box, ["curious", "friendly"]))
	_simulate_tap(dialogue_box)
	if collect_card_button.visible:
		failures.append("Expected no collect icon for a card the player already holds.")

	# An offered card's bar drains; once it runs out the icon grays and,
	# outside debug mode, can no longer be collected.
	var collect_card_bar: ProgressBar = collect_card_button.get_node("CollectCardBar")
	dialogue_box.collected_response_cards.clear()
	dialogue_box.collect_card_seconds = 0.2
	for debug_on in [false, true]:
		dialogue_box.debug_collect_expired_cards = debug_on
		_start(dialogue_box)
		deck_size = dialogue_box.response_cards.size()
		_simulate_tap(dialogue_box)
		_simulate_tap(dialogue_box)
		dialogue_box.play_response_card(_card_index_with_tags(dialogue_box, ["curious", "friendly"]))
		_simulate_tap(dialogue_box)
		if not collect_card_button.visible or not collect_card_bar.visible:
			failures.append("Expected the collect icon and its bar on Kelly's glow sticks line.")
		if collect_card_button.disabled or collect_card_button.modulate != Color.WHITE:
			failures.append("Expected a freshly offered card's icon to be enabled and not grayed.")
		await create_timer(0.1).timeout
		await process_frame
		if collect_card_bar.value <= 0.0 or collect_card_bar.value >= 1.0:
			failures.append("Expected the collect bar to be partway drained, got %f." % collect_card_bar.value)
		await create_timer(0.3).timeout
		if not collect_card_button.visible:
			failures.append("Expected an expired card's icon to stay shown (grayed).")
		if collect_card_button.modulate == Color.WHITE or collect_card_bar.value != 0.0:
			failures.append("Expected an expired card's icon to gray out with an empty bar.")
		if collect_card_button.disabled == debug_on:
			failures.append("Expected an expired card's icon to be %s with debug mode %s." % ["enabled" if debug_on else "disabled", "on" if debug_on else "off"])
		dialogue_box.collect_response_card()
		var expected_size := deck_size + (1 if debug_on else 0)
		if dialogue_box.response_cards.size() != expected_size:
			failures.append("Expected an expired card %s with debug mode %s." % ["to still be collectible" if debug_on else "not to be collectible", "on" if debug_on else "off"])

	await process_frame

	if failures.is_empty():
		print("PASS: dialogue box lets the player collect response cards offered by dialogue lines.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _start(dialogue_box: Control) -> void:
	dialogue_box.start_conversation(CONVERSATION_PATH, CHARACTERS_PATH, RESPONSE_CARDS_PATH)


## Returns the index (into [param dialogue_box]'s response card inventory)
## of the first card whose tags are exactly [param tags], or [code]-1[/code].
func _card_index_with_tags(dialogue_box: Control, tags: Array) -> int:
	var cards: Array[Dictionary] = dialogue_box.response_cards
	for i in cards.size():
		if Array(cards[i]["tags"]) == tags:
			return i
	return -1


## Simulates a single physical tap/click (a touch plus its emulated mouse
## press, then both releases), as in test_dialogue_box_branching.gd.
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
