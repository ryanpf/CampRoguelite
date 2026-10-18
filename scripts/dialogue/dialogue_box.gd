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
## matches (as is always the case for a card with no tags).
##
## With [member show_debug_tags] on, each card also shows its tags, and a
## label above the cards lists every option at the fork with its tags and
## target.
##
## Branch responses have a visible time limit ([member
## branch_timeout_seconds], overridable per-branch with a "timeout" key on
## the segment): a countdown is shown while the cards await selection, and
## if it runs out before the player plays one, the option flagged "timeout:
## true" (or the first option, if none is flagged) is followed
## automatically, without any card being played.
##
## If the branch segment names a "speaker", a played card's text is first
## shown as that speaker's line (so the player's dialogue comes from the
## cards they play), and the chosen option is followed on the next advance.
##
## For debugging, [member debug_timeout_card] turns the countdown off and
## instead adds an extra card after the player's own ones that, when played,
## follows the timeout option just as if the timer had run out.
##
## A segment's "next" (or a branch option's "target") may also be the
## special id "end" to finish the conversation immediately after that
## segment, regardless of what other segments follow it in the file - useful
## for a branch that cuts a conversation short instead of continuing on to
## its normal ending.
##
## A dialogue segment with a "card" key (see [DialogueParser]) offers a
## collectible response card: while it's on screen, an icon ([member
## collect_card_button]) is shown on the dialogue box, and tapping it adds
## the card to the player's [member response_cards] (and [member
## collected_response_cards], so it stays in their inventory for later
## conversations too) without advancing the dialogue. The icon isn't shown
## if the player already holds a card with the same text.
##
## A card can only be grabbed for a limited time ([member
## collect_card_seconds]): a bar on the icon drains as the time runs out,
## after which the icon grays out and can no longer be tapped - unless
## [member debug_collect_expired_cards] is on, in which case it stays
## collectible (but still grayed, to show the window has passed).
extends Control

signal conversation_finished

## Emitted when the player collects [param card] (shaped like an entry of
## [member response_cards]) from a dialogue segment's icon.
signal response_card_collected(card: Dictionary)

## Default character file used to resolve conversation "speaker" ids to
## display names and portraits.
const DEFAULT_CHARACTERS_PATH := "res://data/characters.yml"

## Default response card inventory offered to the player at branch nodes.
const DEFAULT_RESPONSE_CARDS_PATH := "res://data/response_cards.yml"

## Special "next"/branch option "target" id that ends the conversation
## immediately, regardless of the segment's position in the file.
const END_TARGET := "end"

## Default time limit, in seconds, a branch's cards are shown before the
## timeout/fallback option is selected automatically. Overridable per-branch
## with a "timeout" key on the branch segment (see [DialogueParser]).
@export var branch_timeout_seconds: float = 10.0

## Debug aid: shows each response card's tags on the card, and lists every
## branch option's tags and target at a dialogue fork.
@export var show_debug_tags: bool = true

## Debug aid: disables the branch countdown (see [member
## branch_timeout_seconds]) and instead offers an extra "timeout" card at
## every branch, after the player's [member response_cards], that follows
## the branch's timeout option as if the timer had run out.
@export var debug_timeout_card: bool = true

## Time, in seconds, a dialogue segment's collectible card can be grabbed
## via [member collect_card_button] before it expires. Non-positive means
## no time limit (and no draining bar).
@export var collect_card_seconds: float = 3.0

## Debug aid: lets an expired collectible card (see [member
## collect_card_seconds]) still be collected, though its icon is grayed.
@export var debug_collect_expired_cards: bool = true

## Tint applied to [member collect_card_button] once its card has expired,
## on top of swapping its gold styles for gray ones.
const EXPIRED_CARD_MODULATE := Color(0.8, 0.8, 0.8, 1.0)

## Background color of [member collect_card_button] once its card has
## expired.
const EXPIRED_CARD_COLOR := Color(0.55, 0.55, 0.55, 1.0)

## [member collect_card_button]'s style states swapped to gray on expiry.
const _COLLECT_CARD_STYLE_STATES := ["normal", "hover", "pressed", "disabled"]

## Text shown on the [member debug_timeout_card] card.
const DEBUG_TIMEOUT_CARD_TEXT := "[DEBUG] Timeout\n(say nothing)"

@onready var speaker_label: Label = $SpeakerTab/SpeakerLabel
@onready var speaker_portrait: TextureRect = $SpeakerPortrait
@onready var dialogue_text: RichTextLabel = $DialogueBox/DialogueText
@onready var branch_options: CardSwiper = $BranchOptions
@onready var branch_timeout_label: Label = $BranchTimeoutLabel
@onready var branch_debug_label: Label = $BranchDebugLabel
@onready var branch_timer: Timer = $BranchTimer
@onready var collect_card_button: Button = $CollectCardButton
@onready var collect_card_bar: ProgressBar = $CollectCardButton/CollectCardBar
@onready var collect_card_timer: Timer = $CollectCardTimer

var _segments: Array[Dictionary] = []
var _characters: Dictionary = {}
var _index: int = -1

## The player's inventory of response cards, shaped like {"text": String,
## "tags": PackedStringArray} (see [ResponseCardParser]), offered as the cards at every
## branch node. Loaded by [method start_conversation].
var response_cards: Array[Dictionary] = []

## Response cards the player has collected from dialogue segments (see
## [method collect_response_card]), in the order collected. Unlike the rest
## of [member response_cards], these survive [method start_conversation]:
## they're added back on top of each newly loaded inventory.
var collected_response_cards: Array[Dictionary] = []

## The collectible card offered by the segment currently on screen (see
## [method DialogueParser.get_collectible_card]), or an empty [Dictionary]
## if there's none to collect (or it was already collected).
var _collectible_card: Dictionary = {}

## Whether [member _collectible_card]'s time to be grabbed (see [member
## collect_card_seconds]) has run out.
var _collectible_card_expired: bool = false

## [member collect_card_button]'s own styles, keyed by state (see [constant
## _COLLECT_CARD_STYLE_STATES]), restored when a new card is offered.
var _collect_card_styles: Dictionary = {}

## Gray stand-in for [member collect_card_button]'s styles once its card
## has expired.
var _expired_card_style: StyleBox

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

## Index (into the current branch segment's "options") of the option to
## follow on the next advance, while a played card's text is shown as the
## branch's "speaker" line, or [code]-1[/code] if no such line is showing.
var _pending_branch_option_index: int = -1

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
	collect_card_button.pressed.connect(collect_response_card)
	collect_card_button.visible = false
	collect_card_timer.one_shot = true
	collect_card_timer.timeout.connect(_on_collect_card_timer_timeout)
	for state in _COLLECT_CARD_STYLE_STATES:
		_collect_card_styles[state] = collect_card_button.get_theme_stylebox(state)
	_expired_card_style = _collect_card_styles["normal"].duplicate()
	if _expired_card_style is StyleBoxFlat:
		_expired_card_style.bg_color = EXPIRED_CARD_COLOR


func _process(_delta: float) -> void:
	if branch_timeout_label.visible and not branch_timer.is_stopped():
		branch_timeout_label.text = str(ceili(branch_timer.time_left))
	if collect_card_bar.visible and not collect_card_timer.is_stopped():
		collect_card_bar.value = collect_card_timer.time_left / collect_card_timer.wait_time


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
	for card in collected_response_cards:
		if not _has_card_with_text(str(card.get("text", ""))):
			response_cards.append(card)
	_segments = DialogueParser.load_conversation(path)
	_id_to_index = _build_id_index(_segments)
	_index = -1
	_pending_branch_option_index = -1
	visible = not _segments.is_empty()
	_advance_from_index(_index)


## Advances to the next dialogue segment (or, if the current segment names a
## "next" segment id, jumps there instead - see [DialogueParser]), or hides
## the box and emits [signal conversation_finished] once the conversation is
## complete. Does nothing while a branch's cards are awaiting selection; use
## [method play_response_card] (or a card tap) to proceed past a branch.
## While a played card is shown as the branch speaker's line, follows the
## branch option that card chose instead.
func advance() -> void:
	if _awaiting_branch_selection:
		return
	if _pending_branch_option_index != -1:
		var option_index := _pending_branch_option_index
		_pending_branch_option_index = -1
		_follow_branch_option(option_index)
		return
	_advance_from_index(_index)


## Plays response card [param index] (into [member response_cards]) as if
## its card had been double-tapped/double-clicked, jumping playback to the
## target of the branch option matching its tags. Does nothing if
## the current segment is not a branch awaiting selection, or if [param
## index] is out of range. With [member debug_timeout_card] on, [param
## index] [code]response_cards.size()[/code] plays the debug timeout card.
func play_response_card(index: int) -> void:
	if not _awaiting_branch_selection:
		return
	branch_options.select_card(index)


## Adds the card offered by the segment currently on screen (see [member
## collect_card_button]) to [member response_cards] and [member
## collected_response_cards], hides the icon and emits [signal
## response_card_collected]. Does nothing if there's no card to collect,
## or if it has expired (unless [member debug_collect_expired_cards] is on).
func collect_response_card() -> void:
	if _collectible_card.is_empty():
		return
	if _collectible_card_expired and not debug_collect_expired_cards:
		return
	var card := _collectible_card
	_set_collectible_card({})
	response_cards.append(card)
	collected_response_cards.append(card)
	response_card_collected.emit(card)


## Returns whether [member response_cards] already holds a card whose text
## is [param text].
func _has_card_with_text(text: String) -> bool:
	for card in response_cards:
		if str(card.get("text", "")) == text:
			return true
	return false


## Offers [param card] (see [method DialogueParser.get_collectible_card])
## for collection via [member collect_card_button], starting its [member
## collect_card_seconds] countdown, or hides the icon if [param card] is
## empty or the player already holds a card with its text.
func _set_collectible_card(card: Dictionary) -> void:
	if not card.is_empty() and _has_card_with_text(str(card.get("text", ""))):
		card = {}
	_collectible_card = card
	_collectible_card_expired = false
	collect_card_button.visible = not card.is_empty()
	collect_card_button.disabled = false
	collect_card_button.modulate = Color.WHITE
	_set_collect_card_styles(_collect_card_styles)
	var timed := not card.is_empty() and collect_card_seconds > 0.0
	collect_card_bar.visible = timed
	collect_card_bar.value = 1.0
	if timed:
		collect_card_timer.wait_time = collect_card_seconds
		collect_card_timer.start()
	else:
		collect_card_timer.stop()


## Called when [member collect_card_timer] runs out while a collectible
## card is offered: grays out [member collect_card_button] and, unless
## [member debug_collect_expired_cards] is on, stops it being tapped.
func _on_collect_card_timer_timeout() -> void:
	if _collectible_card.is_empty():
		return
	_collectible_card_expired = true
	collect_card_bar.value = 0.0
	collect_card_button.modulate = EXPIRED_CARD_MODULATE
	var expired_styles := {}
	for state in _COLLECT_CARD_STYLE_STATES:
		expired_styles[state] = _expired_card_style
	_set_collect_card_styles(expired_styles)
	collect_card_button.disabled = not debug_collect_expired_cards


## Overrides [member collect_card_button]'s styles with [param styles],
## keyed by state (see [constant _COLLECT_CARD_STYLE_STATES]).
func _set_collect_card_styles(styles: Dictionary) -> void:
	for state in styles:
		collect_card_button.add_theme_stylebox_override(state, styles[state])


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
		_set_collectible_card({})
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
	_set_collectible_card(DialogueParser.get_collectible_card(segment))


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
	if debug_timeout_card:
		cards.append(_build_response_card({"text": DEBUG_TIMEOUT_CARD_TEXT}))
	_branch_timeout_option_index = DialogueParser.find_fallback_option(options)
	branch_debug_label.visible = show_debug_tags
	branch_debug_label.text = _describe_branch_options(options)
	# [method CardSwiper.set_cards] itself clears out the previous deck; do
	# so here rather than as part of hiding the branch UI (in [method
	# _set_branch_active]) so a just-selected card isn't freed out from
	# under its own selection fade-out tween.
	branch_options.set_cards(cards)
	branch_options.clear_selection()
	if debug_timeout_card:
		branch_timer.stop()
		branch_timeout_label.visible = false
	else:
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
	if show_debug_tags and response_card.has("tags"):
		var tags_label := Label.new()
		var tags: PackedStringArray = response_card.get("tags", PackedStringArray())
		tags_label.text = "[%s]" % (", ".join(tags) if not tags.is_empty() else "no tags")
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
## countdown; turning it on also hides [member collect_card_button]. The
## normal dialogue panel and speaker tab stay visible the whole time, so
## the card component and dialog box are visible together
## (the branch's cards are shown alongside, not instead of, the last
## dialogue line, per [DialogueParser]).
func _set_branch_active(active: bool) -> void:
	_awaiting_branch_selection = active
	branch_options.visible = active
	if active:
		_set_collectible_card({})
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
## [member _branch_timeout_option_index]) if none matches. If the branch
## names a "speaker", the card's text is first shown as their line, and the
## option is followed on the next advance instead.
func _on_branch_option_selected(index: int) -> void:
	if not _awaiting_branch_selection:
		return
	if debug_timeout_card and index == response_cards.size():
		_on_branch_timer_timeout()
		return
	if index < 0 or index >= response_cards.size():
		return
	var tags: PackedStringArray = response_cards[index].get("tags", PackedStringArray())
	var segment := _segments[_index]
	var options: Array = segment.get("options", [])
	var option_index := DialogueParser.find_option_for_tags(options, tags)
	if option_index == -1:
		option_index = _branch_timeout_option_index
	if segment.has("speaker"):
		_show_dialogue({
			"speaker": segment["speaker"],
			"text": response_cards[index].get("text", ""),
		})
		_pending_branch_option_index = option_index
		return
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
