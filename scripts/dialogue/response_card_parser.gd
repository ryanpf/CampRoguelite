## Parses the player's response card inventory, written in the same
## human-readable YAML subset as [DialogueParser].
##
## Response cards are what the player plays at a conversation's branch nodes
## (see [DialogueParser]): each card shows its "text" to the player, while
## its "tags" (a comma-separated list of free-form words like "brash",
## "timid" or "smart") decide which branch the conversation follows. A
## card's text should allude to its tags, for example:
##
## [codeblock]
## - text: "Nope. Absolutely not."
##   tags: timid
## - text: "Bold AND clever: shortcut over the ridge!"
##   tags: brash, smart
## [/codeblock]
##
## A card's tags are listed in priority order: when played, its first tag
## that any branch option responds to wins (see [method
## DialogueParser.find_option_for_tags]).
class_name ResponseCardParser
extends RefCounted


## Loads the response card inventory at [param path] and returns an [Array]
## of [Dictionary] entries shaped like {"text": String, "tags":
## PackedStringArray}.
static func load_cards(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ResponseCardParser: could not open response card file '%s'" % path)
		return []
	var content := file.get_as_text()
	return parse(content)


## Parses raw YAML-subset [param text] into an [Array] of response cards
## shaped like {"text": String, "tags": PackedStringArray}. Entries without
## any tags are skipped with an error, since they could never trigger a
## branch of their own.
static func parse(text: String) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for entry in DialogueParser.parse(text):
		var tags := parse_tags(entry)
		if tags.is_empty():
			push_error("ResponseCardParser: skipping card with no tags: %s" % [entry])
			continue
		cards.append({
			"text": str(entry.get("text", "")),
			"tags": tags,
		})
	return cards


## Returns [param entry]'s "tags" key (a response card or branch option) as
## a list of lowercase tags, in the order written. Accepts a plain
## comma-separated list ("brash, smart") or a bracketed one ("[brash,
## smart]"); empty entries are dropped.
static func parse_tags(entry: Dictionary) -> PackedStringArray:
	var raw := str(entry.get("tags", "")).strip_edges()
	if raw.begins_with("[") and raw.ends_with("]"):
		raw = raw.substr(1, raw.length() - 2)
	var tags := PackedStringArray()
	for tag in raw.split(","):
		var cleaned := tag.strip_edges().to_lower()
		if not cleaned.is_empty() and not tags.has(cleaned):
			tags.append(cleaned)
	return tags
