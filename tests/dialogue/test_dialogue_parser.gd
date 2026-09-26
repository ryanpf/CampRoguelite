## Headless smoke test for [DialogueParser]'s branch support: parses a
## conversation with a branch node (nested "options" list keyed by hidden
## response card value) and segments converging back onto a shared segment
## via "next", verifies the resulting segments are shaped as expected, and
## that response card values resolve to the matching (or nearest) option.
## Also checks [ResponseCardParser] parses a response card inventory.
##
## Run with:
##
##   godot --headless --script res://tests/dialogue/test_dialogue_parser.gd
##
## Exits with code 0 on success, 1 on failure (printing the failed checks).
extends SceneTree


func _initialize() -> void:
	var failures: Array[String] = []

	var text := """
- id: start
  speaker: balaam
  text: "Which path shall we take?"
- branch: true
  options:
    - value: 5
      target: mountain
    - value: 2
      target: river
    - special: true
      target: indecisive
- id: mountain
  speaker: donkey
  text: "The mountain air is thin here."
  next: reunited
- id: reunited
  speaker: balaam
  text: "Onward, regardless of the path taken."
"""
	var segments := DialogueParser.parse(text)

	if segments.size() != 4:
		failures.append("Expected 4 segments, got %d." % segments.size())
	else:
		if segments[0].get("id") != "start" or DialogueParser.is_branch(segments[0]):
			failures.append("Expected segment 0 to be the non-branch 'start' segment.")

		if not DialogueParser.is_branch(segments[1]):
			failures.append("Expected segment 1 to be a branch segment.")
		else:
			var options: Array = segments[1].get("options", [])
			if options.size() != 3:
				failures.append("Expected branch segment to have 3 options, got %d." % options.size())
			elif options[0].get("value") != "5" or options[0].get("target") != "mountain":
				failures.append("Expected first option to be value 5 targeting 'mountain', got %s." % [options[0]])
			elif options[1].get("target") != "river":
				failures.append("Expected second option to target 'river', got %s." % [options[1]])
			elif not DialogueParser.is_special_option(options[2]):
				failures.append("Expected third option to be special, got %s." % [options[2]])
			else:
				# Exact matches, then nearest-value fallbacks (1 and 3 are
				# nearest 2, 4 is nearest 5). The value-less special option
				# is never matched by a card.
				var expected := {1: 1, 2: 1, 3: 1, 4: 0, 5: 0}
				for value in expected:
					var index := DialogueParser.find_option_for_value(options, value)
					if index != expected[value]:
						failures.append(
							"Expected value %d to resolve to option %d, got %d." % [value, expected[value], index]
						)
				var tie_options: Array = [{"value": "1"}, {"value": "5"}]
				if DialogueParser.find_option_for_value(tie_options, 3) != 0:
					failures.append("Expected a tie between nearest values to resolve to the lower one.")
				if DialogueParser.find_option_for_value([{"special": "true"}], 3) != -1:
					failures.append("Expected no match when no option has a value.")

		if segments[2].get("id") != "mountain" or segments[2].get("next") != "reunited":
			failures.append("Expected segment 2 to be 'mountain' with next 'reunited', got %s." % [segments[2]])

		if segments[3].get("id") != "reunited":
			failures.append("Expected segment 3 to be 'reunited', got %s." % [segments[3]])

	var cards := ResponseCardParser.parse("""
- text: "Nope."
  value: 1
- text: "Missing value"
- text: "Out of range"
  value: 6
- text: "YES!"
  value: 5
""")
	if cards.size() != 2:
		failures.append("Expected 2 valid response cards, got %d." % cards.size())
	elif cards[0] != {"text": "Nope.", "value": 1} or cards[1] != {"text": "YES!", "value": 5}:
		failures.append("Unexpected parsed response cards: %s." % [cards])

	if failures.is_empty():
		print("PASS: DialogueParser parses branch options, 'next' jump targets, and response card values.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
