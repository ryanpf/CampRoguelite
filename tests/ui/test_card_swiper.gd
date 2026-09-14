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

	if failures.is_empty():
		print("PASS: card swiper starts on the first card and wraps in both directions.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
