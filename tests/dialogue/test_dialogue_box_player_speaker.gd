## Headless smoke test for [DialogueBox]'s branch "speaker" support, using
## the "meeting Kelly" introductory conversation (see
## data/conversations/meeting_kelly.yml) and its response card deck (see
## data/response_cards_introductions.yml).
##
## Verifies that playing a card at a branch with "speaker: player" shows the
## card's text as the player's line (with the player's name and portrait),
## that the next tap follows the branch option that card chose, that
## letting a branch time out plays no card (so no player line is shown),
## and that every card in the deck can be played through to the end of the
## conversation.
##
## The project must have imported its resources at least once (e.g. via a
## prior editor run, or `godot --headless --import`). Run with:
##
##   godot --headless --import
##   godot --headless --script res://tests/dialogue/test_dialogue_box_player_speaker.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree

const CONVERSATION_PATH := "res://data/conversations/meeting_kelly.yml"
const CHARACTERS_PATH := "res://data/characters.yml"
const RESPONSE_CARDS_PATH := "res://data/response_cards_introductions.yml"

## Upper bound on taps/card plays per run, so a broken conversation can't
## loop forever.
const MAX_STEPS := 100


## Note: uses [method MainLoop._initialize] rather than [method Object._init],
## since [method SceneTree.quit]'s exit code is only honored when called from
## [method MainLoop._initialize] onward.
func _initialize() -> void:
	var failures: Array[String] = []

	var dialogue_box := (load("res://scenes/dialogue/dialogue_box.tscn") as PackedScene).instantiate()
	get_root().add_child(dialogue_box)
	await process_frame

	var dialogue_text: RichTextLabel = dialogue_box.get_node("DialogueBox/DialogueText")
	var speaker_label: Label = dialogue_box.get_node("SpeakerTab/SpeakerLabel")
	var speaker_portrait: TextureRect = dialogue_box.get_node("SpeakerPortrait")
	var branch_options: CardSwiper = dialogue_box.get_node("BranchOptions")

	_start(dialogue_box)
	if speaker_label.text != "Kelly":
		failures.append("Expected Kelly to open the conversation, got '%s'." % speaker_label.text)
	if not dialogue_text.text.begins_with("Hey! You're new, right?"):
		failures.append("Expected Kelly's opening line, got '%s'." % dialogue_text.text)

	# Tap on to the first branch and play the "shy" card.
	_simulate_tap(dialogue_box)
	_simulate_tap(dialogue_box)
	if not branch_options.visible:
		failures.append("Expected the first branch's cards after Kelly introduces herself.")
	var shy_index := _card_index_with_tags(dialogue_box, ["shy"])
	dialogue_box.play_response_card(shy_index)
	if branch_options.visible:
		failures.append("Expected the cards to hide once a card is played.")
	if speaker_label.text != "You":
		failures.append("Expected the played card to be spoken by the player, got speaker '%s'." % speaker_label.text)
	if not speaker_portrait.visible:
		failures.append("Expected the player's portrait to be shown for their line.")
	if dialogue_text.text != dialogue_box.response_cards[shy_index]["text"]:
		failures.append("Expected the played card's text as the player's line, got '%s'." % dialogue_text.text)

	# The next tap follows the option the card chose.
	_simulate_tap(dialogue_box)
	if speaker_label.text != "Kelly" or not dialogue_text.text.begins_with("It's okay, I was super nervous"):
		failures.append("Expected Kelly's reply to a shy card, got %s: '%s'." % [speaker_label.text, dialogue_text.text])

	# Letting a branch time out plays no card: Kelly reacts to the silence
	# directly, without a player line in between.
	_start(dialogue_box)
	dialogue_box.branch_timeout_seconds = 0.05
	_simulate_tap(dialogue_box)
	_simulate_tap(dialogue_box)
	await create_timer(0.3).timeout
	if speaker_label.text != "Kelly" or not dialogue_text.text.begins_with("Helloooo? Earth to new kid!"):
		failures.append("Expected a timeout to go straight to Kelly's 'quiet' reply, got %s: '%s'." % [speaker_label.text, dialogue_text.text])
	dialogue_box.branch_timeout_seconds = 10.0

	# Every card must carry the conversation through to its end, speaking as
	# the player at each branch.
	for card_index in dialogue_box.response_cards.size():
		_start(dialogue_box)
		var card_text: String = dialogue_box.response_cards[card_index]["text"]
		var steps := 0
		while dialogue_box.visible and steps < MAX_STEPS:
			steps += 1
			if branch_options.visible:
				dialogue_box.play_response_card(card_index)
				if speaker_label.text != "You" or dialogue_text.text != card_text:
					failures.append("Expected card '%s' to be spoken by the player, got %s: '%s'." % [card_text, speaker_label.text, dialogue_text.text])
			else:
				if dialogue_text.text.is_empty():
					failures.append("Unexpected empty line playing card '%s'." % card_text)
				_simulate_tap(dialogue_box)
		if dialogue_box.visible:
			failures.append("Expected the conversation to end when always playing card '%s'." % card_text)

	await process_frame

	if failures.is_empty():
		print("PASS: branch speaker shows played cards as the player's lines in the meeting Kelly conversation.")
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
