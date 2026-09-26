## Parses the player's response card inventory, written in the same
## human-readable YAML subset as [DialogueParser].
##
## Response cards are what the player plays at a conversation's branch nodes
## (see [DialogueParser]): each card shows only its "text" to the player,
## while its "value" (an integer from [constant MIN_VALUE] to [constant
## MAX_VALUE]) stays hidden and decides which branch the conversation
## follows. A card's text should allude to its hidden value, for example:
##
## [codeblock]
## - text: "Nope. Not happening."
##   value: 1
## - text: "Let's do it!"
##   value: 4
## [/codeblock]
class_name ResponseCardParser
extends RefCounted

## Lowest hidden value a response card (or branch option) can have.
const MIN_VALUE := 1

## Highest hidden value a response card (or branch option) can have.
const MAX_VALUE := 5


## Loads the response card inventory at [param path] and returns an [Array]
## of [Dictionary] entries shaped like {"text": String, "value": int}.
static func load_cards(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ResponseCardParser: could not open response card file '%s'" % path)
		return []
	var content := file.get_as_text()
	return parse(content)


## Parses raw YAML-subset [param text] into an [Array] of response cards
## shaped like {"text": String, "value": int}. Entries without a value in
## the valid range are skipped with an error, since they could never
## trigger a branch.
static func parse(text: String) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for entry in DialogueParser.parse(text):
		var value := parse_value(entry)
		if value == -1:
			push_error("ResponseCardParser: skipping card with missing/invalid value: %s" % [entry])
			continue
		cards.append({
			"text": str(entry.get("text", "")),
			"value": value,
		})
	return cards


## Returns [param entry]'s "value" key (a response card or branch option) as
## an integer, or [code]-1[/code] if it's missing or outside [constant
## MIN_VALUE]..[constant MAX_VALUE].
static func parse_value(entry: Dictionary) -> int:
	var raw := str(entry.get("value", "")).strip_edges()
	if not raw.is_valid_int():
		return -1
	var value := raw.to_int()
	if value < MIN_VALUE or value > MAX_VALUE:
		return -1
	return value
