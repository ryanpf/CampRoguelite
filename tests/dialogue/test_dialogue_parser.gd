## Headless smoke test for [DialogueParser]'s branch support: parses a
## conversation with a branch node (nested "options" list keyed by response
## card tags) and segments converging back onto a shared segment via "next",
## verifies the resulting segments are shaped as expected, and that response
## card tags resolve to the matching option (or the fallback). Also checks
## [ResponseCardParser] parses a response card inventory.
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
    - tags: brash
      target: mountain
    - tags: [Timid, easygoing]
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
			elif options[0].get("tags") != "brash" or options[0].get("target") != "mountain":
				failures.append("Expected first option to be tagged 'brash' targeting 'mountain', got %s." % [options[0]])
			elif options[1].get("target") != "river":
				failures.append("Expected second option to target 'river', got %s." % [options[1]])
			elif not DialogueParser.is_special_option(options[2]):
				failures.append("Expected third option to be special, got %s." % [options[2]])
			else:
				var cases := [
					[["brash"], 0],
					[["timid"], 1],
					[["easygoing"], 1],
					# First card tag with any matching option wins.
					[["smart", "easygoing", "brash"], 1],
					# No matching option (the untagged special option is
					# never matched by a card).
					[["smart"], -1],
				]
				for case in cases:
					var index := DialogueParser.find_option_for_tags(options, PackedStringArray(case[0]))
					if index != case[1]:
						failures.append(
							"Expected tags %s to resolve to option %d, got %d." % [case[0], case[1], index]
						)
				if DialogueParser.find_fallback_option(options) != 2:
					failures.append("Expected the special option to be the fallback.")
				if DialogueParser.find_fallback_option(options.slice(0, 2)) != 0:
					failures.append("Expected the first option to be the fallback when none is special.")

		if segments[2].get("id") != "mountain" or segments[2].get("next") != "reunited":
			failures.append("Expected segment 2 to be 'mountain' with next 'reunited', got %s." % [segments[2]])

		if segments[3].get("id") != "reunited":
			failures.append("Expected segment 3 to be 'reunited', got %s." % [segments[3]])

	var cards := ResponseCardParser.parse("""
- text: "Nope."
  tags: timid
- text: "Missing tags"
- text: "YES! Clever AND bold!"
  tags: Brash,  smart ,
""")
	if cards.size() != 2:
		failures.append("Expected 2 valid response cards, got %d." % cards.size())
	elif cards[0]["text"] != "Nope." or Array(cards[0]["tags"]) != ["timid"] \
			or Array(cards[1]["tags"]) != ["brash", "smart"]:
		failures.append("Unexpected parsed response cards: %s." % [cards])

	if failures.is_empty():
		print("PASS: DialogueParser parses branch options, 'next' jump targets, and response card tags.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
