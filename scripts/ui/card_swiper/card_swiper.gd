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

## Emitted when a card is selected by double-tapping/double-clicking it.
signal card_selected(index: int)

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

## Fraction of a card's width a drag must cross before it counts as a swipe
## to the next/previous card rather than snapping back.
@export_range(0.05, 0.9, 0.05) var swipe_threshold_ratio: float = 0.25

## Fraction of the swiper's own size that each card is rendered at (e.g.
## [code]0.25[/code] renders cards at a quarter of the swiper's width/height,
## centered within their slot). Cards are packed edge-to-edge at this
## reduced size, so the focused card sits in the middle with parts of its
## neighbors peeking in on either side.
@export_range(0.05, 1.0, 0.05) var card_scale: float = 0.25:
	set(value):
		card_scale = value
		if is_node_ready():
			_update_positions()

## Duration, in seconds, of the snap animation played after a drag ends or
## after [method next]/[method previous]/[method go_to] is called.
@export var snap_duration: float = 0.25

## Maximum distance, in pixels, a press/release pair may move and still
## count as a tap (rather than a drag) for double-tap selection purposes.
@export var tap_max_distance: float = 16.0

## Maximum time, in seconds, between two taps on the same card for them to
## count as a double-tap that selects that card.
@export var double_tap_interval: float = 0.35

## Duration, in seconds, of the fade animation played on every card when a
## card is selected (the selected card fades to fully opaque, the rest fade
## out).
@export var select_fade_duration: float = 0.15

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

## Whether a press is currently being tracked, waiting for its matching
## release. Guards against handling the same physical tap twice: by default
## Godot's "input_devices/pointing/emulate_mouse_from_touch" project setting
## makes a single touch also emit a synthetic mouse button event, so a
## tap/click can otherwise deliver two "pressed"/"released" pairs to
## [method _on_gui_input].
var _pointer_down: bool = false
var _press_position: Vector2 = Vector2.ZERO

## Index (into [member _cards]) of the card selected via double-tap, or
## [code]-1[/code] if none has been selected (yet, or the deck was reset).
var _selected_index: int = -1
var _last_tap_index: int = -1
var _last_tap_time: float = -1.0


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
	_clear_selection_state()


## Index (into the current deck) of the card that is currently centered.
func current_index() -> int:
	if _cards.is_empty():
		return -1
	return _wrapi(roundi(_position), _cards.size())


## Index (into the current deck) of the card selected via double-tap, or
## [code]-1[/code] if no card has been selected (yet, or since the deck was
## last reset).
func selected_index() -> int:
	return _selected_index


## Clears any current selection, restoring every card to full opacity
## without animating (e.g. so a demo screen can reset the swiper each time
## it is reopened).
func clear_selection() -> void:
	_clear_selection_state()
	for card in _cards:
		card.modulate.a = 1.0


## Selects the card at [param index] as if it had been double-tapped:
## records it as [member selected_index], emits [signal card_selected], and
## fades out every other card. Out-of-range indices are ignored.
func select_card(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	_select_card(index)


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
			if _pointer_down:
				return
			_pointer_down = true
			_start_drag(event.position)
		else:
			if not _pointer_down:
				return
			_pointer_down = false
			_end_drag(event.position)
	elif _dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		_update_drag(event.relative.x)


func _start_drag(position: Vector2) -> void:
	if _tween:
		_tween.kill()
	_dragging = true
	_drag_start_x = position.x
	_press_position = position
	_position_at_drag_start = _position


func _update_drag(relative_x: float) -> void:
	var step := _card_step()
	if step <= 0.0:
		return
	_position -= relative_x / step
	if not wrap:
		_position = clampf(_position, 0.0, float(_cards.size() - 1))
	_update_positions()


func _end_drag(position: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	var moved := _position - _position_at_drag_start
	var target := roundi(_position_at_drag_start)
	if absf(moved) >= swipe_threshold_ratio:
		target = roundi(_position_at_drag_start) + (1 if moved > 0.0 else -1)
	_go_to_position(float(target), true)
	if (position - _press_position).length() <= tap_max_distance:
		_handle_tap(position)


## Tracks presses that stayed within [member tap_max_distance] of their
## release, and selects the tapped card (via [method _select_card]) once two
## such taps land on the same card within [member double_tap_interval].
func _handle_tap(position: Vector2) -> void:
	var index := _card_index_at_position(position)
	if index == -1:
		_last_tap_index = -1
		_last_tap_time = -1.0
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_tap_index == index and _last_tap_time >= 0.0 and (now - _last_tap_time) <= double_tap_interval:
		_last_tap_index = -1
		_last_tap_time = -1.0
		_select_card(index)
	else:
		_last_tap_index = index
		_last_tap_time = now


## Returns the index of the topmost visible card whose rect contains [param
## position] (in this control's local coordinates), or [code]-1[/code] if
## none does.
func _card_index_at_position(position: Vector2) -> int:
	for i in _cards.size():
		var card := _cards[i]
		if card.visible and Rect2(card.position, card.size).has_point(position):
			return i
	return -1


## Selects the card at [param index]: records it as [member selected_index],
## emits [signal card_selected], and animates every other card fading out
## while the selected card fades back to fully opaque (in case it, or
## others, were left faded from a previous selection).
func _select_card(index: int) -> void:
	_selected_index = index
	for i in _cards.size():
		var card := _cards[i]
		var target_alpha := 1.0 if i == index else 0.0
		create_tween().tween_property(card, "modulate:a", target_alpha, select_fade_duration)
	card_selected.emit(index)


func _clear_selection_state() -> void:
	_selected_index = -1
	_last_tap_index = -1
	_last_tap_time = -1.0


func _update_positions() -> void:
	var card_size := size * clampf(card_scale, 0.05, 1.0)
	var offset := (size - card_size) * 0.5
	var step := card_size.x
	for i in _cards.size():
		var card := _cards[i]
		var delta := _wrapped_delta(i, _position) if wrap else float(i) - _position
		var left := delta * step + offset.x
		card.position = Vector2(left, offset.y)
		card.size = card_size
		card.visible = left + card_size.x > 0.0 and left < size.x


## Current width, in pixels, of a single card slot (i.e. [member card_scale]
## of the swiper's own width). Used to convert drag distances into
## fractional card-index movement.
func _card_step() -> float:
	return size.x * clampf(card_scale, 0.05, 1.0)


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
