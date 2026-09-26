## UI component that plays back a conversation loaded via [DialogueParser].
## Displays the active speaker's portrait above the dialogue text box, along
## with their name on a visual "tab", and advances to the next segment when
## tapped/clicked.
##
## Conversations may branch: when playback reaches a branch segment (see
## [DialogueParser]), a [CardSwiper] is shown alongside the still-visible
## dialogue text/speaker tab, holding the player's inventory of response
## cards (see [ResponseCardParser] and [member response_cards]). Tapping/
## clicking to advance is disabled until the player plays a card (double-
## tap/double-click, per [CardSwiper]), at which point playback jumps to the
## target of the branch option matching that card's tags (see [method
## DialogueParser.find_option_for_tags]), or to the fallback option if none
## matches.
##
## With [member show_debug_tags] on, each card also shows its tags, and a
## label above the cards lists every option at the fork with its tags and
## target.
##
## Branch responses have a visible time limit ([member
## branch_timeout_seconds], overridable per-branch with a "timeout" key on
## the segment): a countdown is shown while the cards await selection, and
## if it runs out before the player plays one, the option flagged "special:
## true" (or the first option, if none is flagged) is followed
## automatically, without any card being played.
##
## A segment's "next" (or a branch option's "target") may also be the
## special id "end" to finish the conversation immediately after that
## segment, regardless of what other segments follow it in the file - useful
## for a branch that cuts a conversation short instead of continuing on to
## its normal ending.
extends Control

signal conversation_finished

## Default character file used to resolve conversation "speaker" ids to
## display names and portraits.
const DEFAULT_CHARACTERS_PATH := "res://data/characters.yml"

## Default response card inventory offered to the player at branch nodes.
const DEFAULT_RESPONSE_CARDS_PATH := "res://data/response_cards.yml"

## Special "next"/branch option "target" id that ends the conversation
## immediately, regardless of the segment's position in the file.
const END_TARGET := "end"

## Default time limit, in seconds, a branch's cards are shown before the
## special/fallback option is selected automatically. Overridable per-branch
## with a "timeout" key on the branch segment (see [DialogueParser]).
@export var branch_timeout_seconds: float = 10.0

## Debug aid: shows each response card's tags on the card, and lists every
## branch option's tags and target at a dialogue fork.
@export var show_debug_tags: bool = true

@onready var speaker_label: Label = $SpeakerTab/SpeakerLabel
@onready var speaker_portrait: TextureRect = $SpeakerPortrait
@onready var dialogue_text: RichTextLabel = $DialogueBox/DialogueText
@onready var branch_options: CardSwiper = $BranchOptions
@onready var branch_timeout_label: Label = $BranchTimeoutLabel
@onready var branch_debug_label: Label = $BranchDebugLabel
@onready var branch_timer: Timer = $BranchTimer

var _segments: Array[Dictionary] = []
var _characters: Dictionary = {}
var _index: int = -1

## The player's inventory of response cards, shaped like {"text": String,
## "tags": PackedStringArray} (see [ResponseCardParser]), offered as the cards at every
## branch node. Loaded by [method start_conversation].
var response_cards: Array[Dictionary] = []

## Maps a segment's "id" (see [DialogueParser]) to its index in [member
## _segments], used to resolve branch "target"s and segment "next"s.
var _id_to_index: Dictionary = {}

## Whether the segment currently on screen is a branch, i.e. [member
## branch_options] is showing cards and waiting for a selection rather than
## a tap/click to advance.
var _awaiting_branch_selection: bool = false

## Index (into the current branch segment's "options") of the option to
## follow automatically if [member branch_timer] runs out, or [code]-1[/code]
## if the current segment is not a branch (or its options list is empty).
var _branch_timeout_option_index: int = -1

## Whether a press is currently being tracked, waiting for its matching
## release. Guards against advancing twice per tap: by default Godot's
## "input_devices/pointing/emulate_mouse_from_touch" project setting makes a
## single touch also emit a synthetic mouse button event, so a tap/click can
## otherwise deliver two "pressed" events to [method _on_gui_input].
var _awaiting_release: bool = false


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	branch_options.card_selected.connect(_on_branch_option_selected)
	branch_options.visible = false
	branch_timeout_label.visible = false
	branch_debug_label.visible = false
	branch_timer.one_shot = true
	branch_timer.timeout.connect(_on_branch_timer_timeout)


func _process(_delta: float) -> void:
	if branch_timeout_label.visible and not branch_timer.is_stopped():
		branch_timeout_label.text = str(ceili(branch_timer.time_left))


## Loads the conversation at [param path] and starts playing it back,
## resolving speakers against the character file at [param characters_path]
## and offering the response cards in [param response_cards_path] at branch
## nodes.
func start_conversation(
	path: String,
	characters_path: String = DEFAULT_CHARACTERS_PATH,
	response_cards_path: String = DEFAULT_RESPONSE_CARDS_PATH
) -> void:
	_characters = CharacterParser.load_characters(characters_path)
	response_cards = ResponseCardParser.load_cards(response_cards_path)
	_segments = DialogueParser.load_conversation(path)
	_id_to_index = _build_id_index(_segments)
	_index = -1
	visible = not _segments.is_empty()
	_advance_from_index(_index)


## Advances to the next dialogue segment (or, if the current segment names a
## "next" segment id, jumps there instead - see [DialogueParser]), or hides
## the box and emits [signal conversation_finished] once the conversation is
## complete. Does nothing while a branch's cards are awaiting selection; use
## [method play_response_card] (or a card tap) to proceed past a branch.
func advance() -> void:
	if _awaiting_branch_selection:
		return
	_advance_from_index(_index)


## Plays response card [param index] (into [member response_cards]) as if
## its card had been double-tapped/double-clicked, jumping playback to the
## target of the branch option matching its tags. Does nothing if
## the current segment is not a branch awaiting selection, or if [param
## index] is out of range.
func play_response_card(index: int) -> void:
	if not _awaiting_branch_selection:
		return
	branch_options.select_card(index)


func _advance_from_index(from_index: int) -> void:
	var next_index := from_index + 1
	if from_index >= 0 and from_index < _segments.size():
		var previous_segment: Dictionary = _segments[from_index]
		if previous_segment.has("next"):
			next_index = _resolve_target(str(previous_segment["next"]), next_index)
	_show_segment(next_index)


func _show_segment(index: int) -> void:
	_index = index
	if _index >= _segments.size():
		_set_branch_active(false)
		visible = false
		conversation_finished.emit()
		return

	var segment := _segments[_index]
	if DialogueParser.is_branch(segment):
		_show_branch(segment)
	else:
		_show_dialogue(segment)


func _show_dialogue(segment: Dictionary) -> void:
	_set_branch_active(false)
	var character_id := str(segment.get("speaker", ""))
	var character: Dictionary = _characters.get(character_id, {})
	speaker_label.text = str(character.get("name", character_id))
	var portrait: Texture2D = character.get("portrait")
	speaker_portrait.texture = portrait
	speaker_portrait.visible = portrait != null
	dialogue_text.text = str(segment.get("text", ""))


## Displays the player's [member response_cards] as cards in [member
## branch_options] alongside the still-visible dialogue text, until one is
## played (or, per [member branch_timer], [param segment]'s timeout option
## is followed automatically). Tapping/clicking to advance past the dialogue
## text stays disabled the whole time (see [member _awaiting_branch_selection]).
func _show_branch(segment: Dictionary) -> void:
	_set_branch_active(true)
	var options: Array = segment.get("options", [])
	var cards: Array[Control] = []
	for response_card in response_cards:
		cards.append(_build_response_card(response_card))
	_branch_timeout_option_index = DialogueParser.find_fallback_option(options)
	branch_debug_label.visible = show_debug_tags
	branch_debug_label.text = _describe_branch_options(options)
	# [method CardSwiper.set_cards] itself clears out the previous deck; do
	# so here rather than as part of hiding the branch UI (in [method
	# _set_branch_active]) so a just-selected card isn't freed out from
	# under its own selection fade-out tween.
	branch_options.set_cards(cards)
	branch_options.clear_selection()
	_start_branch_timer(segment)


## Starts [member branch_timer] counting down towards automatically
## selecting [member _branch_timeout_option_index], showing the countdown in
## [member branch_timeout_label], unless the current branch has no options
## to fall back on or its (possibly per-segment-overridden, see
## [DialogueParser]) timeout is non-positive.
func _start_branch_timer(segment: Dictionary) -> void:
	var timeout := branch_timeout_seconds
	if segment.has("timeout"):
		timeout = float(str(segment["timeout"]))
	if _branch_timeout_option_index == -1 or timeout <= 0.0:
		branch_timer.stop()
		branch_timeout_label.visible = false
		return
	branch_timer.wait_time = timeout
	branch_timer.start()
	branch_timeout_label.visible = true
	branch_timeout_label.text = str(ceili(timeout))


## Debug text listing each of [param options] (a branch segment's
## "options") as "tags -> target", marking the timeout/fallback option.
func _describe_branch_options(options: Array) -> String:
	var parts: PackedStringArray = []
	for i in options.size():
		var tags := ResponseCardParser.parse_tags(options[i])
		var tag_text := ", ".join(tags) if not tags.is_empty() else "(no tags)"
		if i == _branch_timeout_option_index:
			tag_text += " / (timeout)"
		parts.append("%s -> %s" % [tag_text, str(options[i].get("target", ""))])
	return "Branches: " + " | ".join(parts)


func _build_response_card(response_card: Dictionary) -> Control:
	var card := Panel.new()
	var label := Label.new()
	label.text = str(response_card.get("text", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)
	if show_debug_tags:
		var tags_label := Label.new()
		tags_label.text = "[%s]" % ", ".join(response_card.get("tags", PackedStringArray()))
		tags_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tags_label.add_theme_font_size_override("font_size", 12)
		tags_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		tags_label.offset_top = -24.0
		tags_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tags_label)
	return card


## Shows/hides the branch UI over the still-visible dialogue text/speaker
## tab: [param active] toggles [member _awaiting_branch_selection] and
## [member branch_options]' visibility, and (when turning it off) stops the
## countdown. The normal dialogue panel and speaker tab stay visible the
## whole time, so the card component and dialog box are visible together
## (the branch's cards are shown alongside, not instead of, the last
## dialogue line, per [DialogueParser]).
func _set_branch_active(active: bool) -> void:
	_awaiting_branch_selection = active
	branch_options.visible = active
	if not active:
		branch_timer.stop()
		branch_timeout_label.visible = false
		branch_debug_label.visible = false


## Called when [member branch_timer] runs out while a branch's cards are
## still awaiting selection: follows [member _branch_timeout_option_index]
## without any card being played.
func _on_branch_timer_timeout() -> void:
	if not _awaiting_branch_selection or _branch_timeout_option_index == -1:
		return
	_follow_branch_option(_branch_timeout_option_index)


## Called when response card [param index] is played: follows the current
## branch's option matching that card's tags, or the fallback option (see
## [member _branch_timeout_option_index]) if none matches.
func _on_branch_option_selected(index: int) -> void:
	if not _awaiting_branch_selection:
		return
	if index < 0 or index >= response_cards.size():
		return
	var tags: PackedStringArray = response_cards[index].get("tags", PackedStringArray())
	var options: Array = _segments[_index].get("options", [])
	var option_index := DialogueParser.find_option_for_tags(options, tags)
	if option_index == -1:
		option_index = _branch_timeout_option_index
	_follow_branch_option(option_index)


## Jumps playback to the target of the current branch segment's option
## [param option_index], or falls through to the following segment if it's
## out of range (e.g. the branch has no options at all).
func _follow_branch_option(option_index: int) -> void:
	if _index < 0 or _index >= _segments.size():
		return
	var options: Array = _segments[_index].get("options", [])
	var target := ""
	if option_index >= 0 and option_index < options.size():
		target = str(options[option_index].get("target", ""))
	_show_segment(_resolve_target(target, _index + 1))


## Resolves segment id [param target] to its index (via [member
## _id_to_index]), falling back to [param default_index] if [param target]
## is empty or unknown. The special id [constant END_TARGET] resolves to an
## index past the end of [member _segments], ending the conversation.
func _resolve_target(target: String, default_index: int) -> int:
	if target == END_TARGET:
		return _segments.size()
	if target.is_empty() or not _id_to_index.has(target):
		return default_index
	return _id_to_index[target]


func _build_id_index(segments: Array[Dictionary]) -> Dictionary:
	var id_to_index := {}
	for i in segments.size():
		var id := str(segments[i].get("id", ""))
		if not id.is_empty():
			id_to_index[id] = i
	return id_to_index


func _on_gui_input(event: InputEvent) -> void:
	var is_press: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	var is_release: bool = (event is InputEventMouseButton and not event.pressed) \
		or (event is InputEventScreenTouch and not event.pressed)
	if is_press and not _awaiting_release:
		_awaiting_release = true
		advance()
	elif is_release:
		_awaiting_release = false
