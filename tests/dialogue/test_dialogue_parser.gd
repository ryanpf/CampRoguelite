## Headless smoke test for [DialogueParser]'s branch support: parses a
## conversation with a branch node (nested "options" list) and segments
## converging back onto a shared segment via "next", and verifies the
## resulting segments are shaped as expected.
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
    - text: "Take the mountain pass"
      target: mountain
    - text: "Take the river road"
      target: river
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
			if options.size() != 2:
				failures.append("Expected branch segment to have 2 options, got %d." % options.size())
			elif options[0].get("text") != "Take the mountain pass" or options[0].get("target") != "mountain":
				failures.append("Expected first option to target 'mountain', got %s." % [options[0]])
			elif options[1].get("target") != "river":
				failures.append("Expected second option to target 'river', got %s." % [options[1]])

		if segments[2].get("id") != "mountain" or segments[2].get("next") != "reunited":
			failures.append("Expected segment 2 to be 'mountain' with next 'reunited', got %s." % [segments[2]])

		if segments[3].get("id") != "reunited":
			failures.append("Expected segment 3 to be 'reunited', got %s." % [segments[3]])

	if failures.is_empty():
		print("PASS: DialogueParser parses branch options and 'next' jump targets.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)
