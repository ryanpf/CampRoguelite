## Headless smoke test for [CardSwiper].
##
## Instantiates the card swiper, adds a handful of cards, and verifies:
## - it starts on the first card,
## - [method CardSwiper.next]/[method CardSwiper.previous] move one card at
##   a time (without animation, so the assertions can run synchronously),
## - wrapping is honored: calling [method CardSwiper.previous] from the
##   first card lands on the last one, and [method CardSwiper.next] from the
##   last card wraps back to the first.
##
## Run with:
##
##   godot --headless --import
##   godot --headless --script res://tests/ui/test_card_swiper.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree


func _initialize() -> void:
	var failures: Array[String] = []

	var swiper := (load("res://scenes/ui/card_swiper/card_swiper.tscn") as PackedScene).instantiate()
	get_root().add_child(swiper)
	# Wait a frame so the swiper's own _ready() (and its @onready node
	# references) run before we start adding cards to it.
	await process_frame

	var cards: Array[Control] = []
	for i in 4:
		var card := Control.new()
		card.name = "Card%d" % i
		cards.append(card)
	swiper.set_cards(cards)

	if swiper.current_index() != 0:
		failures.append("Expected to start on card 0, got %d" % swiper.current_index())

	swiper.next(false)
	if swiper.current_index() != 1:
		failures.append("Expected next() to move to card 1, got %d" % swiper.current_index())

	swiper.previous(false)
	if swiper.current_index() != 0:
		failures.append("Expected previous() to move back to card 0, got %d" % swiper.current_index())

	# Wrapping backwards from the first card should land on the last card.
	swiper.previous(false)
	if swiper.current_index() != cards.size() - 1:
		failures.append(
			"Expected previous() from card 0 to wrap to card %d, got %d" \
				% [cards.size() - 1, swiper.current_index()]
		)

	# Wrapping forwards from the last card should land back on the first.
	swiper.next(false)
	if swiper.current_index() != 0:
		failures.append("Expected next() from the last card to wrap to card 0, got %d" % swiper.current_index())

	# go_to() should jump directly to the requested card.
	swiper.go_to(2, false)
	if swiper.current_index() != 2:
		failures.append("Expected go_to(2) to land on card 2, got %d" % swiper.current_index())

	# Cards should be scaled down to card_scale of the swiper's own size and
	# centered on the focused card, so that neighboring cards peek in on
	# either side rather than being fully off-screen.
	swiper.go_to(0, false)
	swiper.size = Vector2(400, 200)
	swiper.card_scale = 0.25
	swiper.card_spacing = 0.0
	await process_frame
	var focused_card: Control = cards[0]
	var expected_card_size: Vector2 = swiper.size * 0.25
	if not focused_card.size.is_equal_approx(expected_card_size):
		failures.append(
			"Expected focused card size %s, got %s" % [expected_card_size, focused_card.size]
		)
	var expected_offset: Vector2 = (swiper.size - expected_card_size) * 0.5
	if not focused_card.position.is_equal_approx(expected_offset):
		failures.append(
			"Expected focused card to be centered at %s, got %s" % [expected_offset, focused_card.position]
		)
	var next_card: Control = cards[1]
	if not next_card.visible:
		failures.append("Expected the next card to peek in and be visible next to the focused card")

	# card_spacing should push neighboring card slots further apart (in
	# addition to card_scale sizing) without moving the focused card itself,
	# matching the visible gap between cards in Android's Recents panel
	# rather than packing them edge-to-edge.
	swiper.card_spacing = 40.0
	await process_frame
	if not focused_card.position.is_equal_approx(expected_offset):
		failures.append(
			"Expected card_spacing not to move the focused card, got %s" % [focused_card.position]
		)
	var expected_next_left: float = expected_card_size.x + 40.0 + expected_offset.x
	if not is_equal_approx(next_card.position.x, expected_next_left):
		failures.append(
			"Expected card_spacing to push the next card to x=%f, got %f" % [expected_next_left, next_card.position.x]
		)
	swiper.card_spacing = 0.0
	await process_frame

	# Double-tapping the focused card (positioned at focused_card.position,
	# centered within its slot) should select it, fade out every other
	# card, and report its index via both the signal and selected_index().
	swiper.select_fade_duration = 0.0
	var selected_signal_values: Array[int] = []
	swiper.card_selected.connect(func(index: int) -> void: selected_signal_values.append(index))
	var tap_position: Vector2 = focused_card.position + focused_card.size * 0.5
	_simulate_double_tap(swiper, tap_position)
	await process_frame
	await process_frame

	if swiper.selected_index() != 0:
		failures.append("Expected double-tapping card 0 to select it, got selected_index() = %d" % swiper.selected_index())
	if selected_signal_values != [0]:
		failures.append("Expected card_selected to emit once with index 0, got %s" % [selected_signal_values])
	if not is_equal_approx(focused_card.modulate.a, 1.0):
		failures.append("Expected the selected card to stay fully opaque, got alpha %f" % focused_card.modulate.a)
	if not is_equal_approx(next_card.modulate.a, 0.0):
		failures.append("Expected other cards to fade out after a selection, got alpha %f" % next_card.modulate.a)

	# A single tap (no second tap within the double-tap interval) should not
	# select anything.
	swiper.clear_selection()
	selected_signal_values.clear()
	_simulate_tap(swiper, tap_position)
	await process_frame
	if swiper.selected_index() != -1:
		failures.append("Expected a single tap not to select a card, got selected_index() = %d" % swiper.selected_index())

	# A single drag that crosses several cards' worth of distance should be
	# able to cycle through more than one card at once, rather than only
	# ever moving to the immediate neighbor.
	var far_target: int = swiper._resolve_swipe_target(2.5, 0.0, 0.0)
	if far_target != 3:
		failures.append("Expected a 2.5-card-wide drag to target card 3, got %d" % far_target)

	# A fast flick that only physically crosses a fraction of a single
	# card's width should still register as a swipe (matching the swipe's
	# momentum) even though the raw distance dragged is well under the
	# configured swipe_threshold_ratio.
	var flick_target: int = swiper._resolve_swipe_target(0.1, 0.0, 20.0)
	if flick_target == 0:
		failures.append(
			"Expected a fast flick to advance past card 0 even with a short drag distance, got %d" % flick_target
		)

	# A slow drag that stays well under the threshold, with negligible
	# velocity, should snap back to the starting card instead of advancing.
	var snap_back_target: int = swiper._resolve_swipe_target(0.1, 0.0, 0.0)
	if snap_back_target != 0:
		failures.append("Expected a short, slow drag to snap back to card 0, got %d" % snap_back_target)

	if failures.is_empty():
		print("PASS: card swiper starts on the first card and wraps in both directions.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


## Simulates a single physical tap/click at [param position] by delivering
## both an [InputEventScreenTouch] and a synthetic [InputEventMouseButton]
## press (followed by their releases), mirroring what Godot's default
## "input_devices/pointing/emulate_mouse_from_touch" project setting does
## for a real tap on a touch-capable device. [param swiper] must not treat
## the duplicate pair as two separate taps.
func _simulate_tap(swiper: Control, position: Vector2) -> void:
	var touch_press := InputEventScreenTouch.new()
	touch_press.pressed = true
	touch_press.position = position
	swiper._on_gui_input(touch_press)

	var mouse_press := InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	mouse_press.position = position
	swiper._on_gui_input(mouse_press)

	var touch_release := InputEventScreenTouch.new()
	touch_release.pressed = false
	touch_release.position = position
	swiper._on_gui_input(touch_release)

	var mouse_release := InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.pressed = false
	mouse_release.position = position
	swiper._on_gui_input(mouse_release)


## Simulates two quick taps at [param position], as a double-tap gesture.
func _simulate_double_tap(swiper: Control, position: Vector2) -> void:
	_simulate_tap(swiper, position)
	_simulate_tap(swiper, position)
