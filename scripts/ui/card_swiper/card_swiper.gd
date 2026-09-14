## Generic, reusable UI component for swiping horizontally through a deck of
## "cards" (arbitrary [Control] nodes). Supports drag/swipe via mouse or
## touch, optional prev/next buttons and page dots, and optional infinite
## wrapping (swiping past the last card returns to the first, and vice
## versa).
##
## Cards are supplied by the owner via [method add_card] (or [method
## set_cards]); this component only lays them out and animates transitions
## between them, it has no opinion on card content.
class_name CardSwiper
extends Control

## Emitted after a swipe/programmatic transition settles on a new card.
signal card_changed(index: int)

## Whether swiping past the last card wraps around to the first (and
## swiping before the first wraps to the last). When [code]false[/code], the
## swiper stops at the first/last card.
@export var wrap: bool = true

## Whether to show the built-in previous/next buttons.
@export var show_nav_buttons: bool = true:
	set(value):
		show_nav_buttons = value
		if is_node_ready():
			_update_nav_buttons()

## Whether to show the built-in page dots indicator.
@export var show_page_dots: bool = true:
	set(value):
		show_page_dots = value
		if is_node_ready():
			_dots.visible = value

## Fraction of the swiper's width a drag must cross before it counts as a
## swipe to the next/previous card rather than snapping back.
@export_range(0.05, 0.9, 0.05) var swipe_threshold_ratio: float = 0.25

## Duration, in seconds, of the snap animation played after a drag ends or
## after [method next]/[method previous]/[method go_to] is called.
@export var snap_duration: float = 0.25

@onready var _prev_button: Button = $PrevButton
@onready var _next_button: Button = $NextButton
@onready var _dots: HBoxContainer = $Dots

var _cards: Array[Control] = []
## Continuous, unbounded "which card is centered" value. Whole numbers mean a
## card is centered/settled; it grows or shrinks without wrapping so that
## repeated swipes in the same direction keep animating in that direction
## instead of jumping backwards. Wrapping only happens when mapping this to
## an actual card index (see [method _wrapped_delta] and [method
## current_index]).
var _position: float = 0.0
var _dragging: bool = false
var _drag_start_x: float = 0.0
var _position_at_drag_start: float = 0.0
var _tween: Tween


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	resized.connect(_update_positions)
	_prev_button.pressed.connect(previous)
	_next_button.pressed.connect(next)
	_update_nav_buttons()
	_dots.visible = show_page_dots
	_update_dots()
	_update_positions()


## Adds [param card] as the newest card in the deck, taking ownership of it
## (reparenting it under this swiper) if needed.
func add_card(card: Control) -> void:
	if card.get_parent() != self:
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	# Anchor to the top-left so we can freely control each card's position
	# and size in [method _update_positions] (a "full rect" preset would
	# fight our manual sizing since it keeps opposite anchors equal).
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cards.append(card)
	if is_node_ready():
		move_child(_prev_button, -1)
		move_child(_next_button, -1)
		move_child(_dots, -1)
		_update_dots()
		_update_positions()


## Replaces the current deck of cards with [param cards], resetting the
## swiper to the first card.
func set_cards(cards: Array[Control]) -> void:
	clear_cards()
	for card in cards:
		add_card(card)
	_position = 0.0
	if is_node_ready():
		_update_positions()


## Removes and frees all current cards.
func clear_cards() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	_position = 0.0


## Index (into the current deck) of the card that is currently centered.
func current_index() -> int:
	if _cards.is_empty():
		return -1
	return _wrapi(roundi(_position), _cards.size())


## Advances to the next card, animating the transition unless [param
## animated] is [code]false[/code].
func next(animated: bool = true) -> void:
	_go_to_position(_position + 1.0, animated)


## Returns to the previous card, animating the transition unless [param
## animated] is [code]false[/code].
func previous(animated: bool = true) -> void:
	_go_to_position(_position - 1.0, animated)


## Jumps to the card at [param index], taking the shortest wrap-around path
## when [member wrap] is enabled, animating the transition unless [param
## animated] is [code]false[/code].
func go_to(index: int, animated: bool = true) -> void:
	if _cards.is_empty():
		return
	var count := _cards.size()
	var delta := 0.0
	if wrap:
		delta = _wrapped_delta(index, _position)
	else:
		delta = float(index) - _position
	_go_to_position(_position + delta, animated)


func _go_to_position(target_position: float, animated: bool) -> void:
	if _cards.is_empty():
		return
	if not wrap:
		target_position = clampf(target_position, 0.0, float(_cards.size() - 1))
	if _tween:
		_tween.kill()
	if not animated or snap_duration <= 0.0:
		_position = target_position
		_update_positions()
		_update_dots()
		card_changed.emit(current_index())
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_display_position, _position, target_position, snap_duration)
	_tween.tween_callback(_on_settle)


func _set_display_position(value: float) -> void:
	_position = value
	_update_positions()


func _on_settle() -> void:
	_update_dots()
	card_changed.emit(current_index())


func _on_gui_input(event: InputEvent) -> void:
	if _cards.size() <= 1:
		return
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) \
			or event is InputEventScreenTouch:
		if event.pressed:
			_start_drag(event.position.x)
		else:
			_end_drag()
	elif _dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		_update_drag(event.relative.x)


func _start_drag(x: float) -> void:
	if _tween:
		_tween.kill()
	_dragging = true
	_drag_start_x = x
	_position_at_drag_start = _position


func _update_drag(relative_x: float) -> void:
	var width := size.x
	if width <= 0.0:
		return
	_position -= relative_x / width
	if not wrap:
		_position = clampf(_position, 0.0, float(_cards.size() - 1))
	_update_positions()


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	var moved := _position - _position_at_drag_start
	var target := roundi(_position_at_drag_start)
	if absf(moved) >= swipe_threshold_ratio:
		target = roundi(_position_at_drag_start) + (1 if moved > 0.0 else -1)
	_go_to_position(float(target), true)


func _update_positions() -> void:
	var width := size.x
	for i in _cards.size():
		var card := _cards[i]
		var delta := _wrapped_delta(i, _position) if wrap else float(i) - _position
		card.position = Vector2(delta * width, 0.0)
		card.size = size
		card.visible = absf(delta) <= 1.5


func _update_nav_buttons() -> void:
	var visible_buttons := show_nav_buttons and _cards.size() > 1
	_prev_button.visible = visible_buttons
	_next_button.visible = visible_buttons


func _update_dots() -> void:
	_update_nav_buttons()
	for child in _dots.get_children():
		child.queue_free()
	if _cards.size() <= 1:
		return
	var active_index := current_index()
	for i in _cards.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = Color.WHITE if i == active_index else Color(1, 1, 1, 0.35)
		_dots.add_child(dot)


## Returns the shortest signed distance (in card widths) from [param
## from_position] to card index [param index], wrapping around the deck so
## e.g. the card just before index 0 has a delta of -1 rather than
## [code]count - 1[/code].
func _wrapped_delta(index: int, from_position: float) -> float:
	var count := _cards.size()
	if count <= 0:
		return 0.0
	var delta := fmod(float(index) - from_position, float(count))
	if delta > count / 2.0:
		delta -= count
	elif delta < -count / 2.0:
		delta += count
	return delta


func _wrapi(value: int, count: int) -> int:
	if count <= 0:
		return 0
	return ((value % count) + count) % count
