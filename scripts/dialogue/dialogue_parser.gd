## Parses conversation data files written in a small, human-readable YAML
## subset so writers can define dialogue without touching the Godot editor.
##
## Supported format is a list of mappings, each with a "speaker" and "text"
## key, for example:
##
## [codeblock]
## - speaker: balaam
##   text: "What is thy will with me?"
## - speaker: donkey
##   text: "Have I not served thee well?"
## [/codeblock]
##
## "speaker" is the id of a character defined in a character file (see
## [CharacterParser]), not a display name.
##
## Conversations can branch: any segment may have an "id" key naming it as a
## jump target, and an optional "next" key jumping to a named segment instead
## of falling through to the following one (useful to have diverging
## branches converge back onto a shared segment). A segment with a "branch:
## true" key and a nested "options" list asks the player to respond instead
## of showing a line of dialogue.
##
## Responses aren't written into the conversation: the player instead plays
## one of the response cards from their inventory (see [ResponseCardParser]),
## each carrying one or more "tags" such as "brash", "timid" or "smart".
## Each option is a mapping with "tags" (the card tag(s) it responds to,
## comma-separated) and a "target" (the id to jump to when a card with one
## of those tags is played), for example:
##
## [codeblock]
## - id: crossroads
##   speaker: balaam
##   text: "Shall we brave the mountain pass, or scurry back to camp?"
## - branch: true
##   options:
##     - tags: timid
##       target: turn_back
##     - tags: brash
##       target: mountain
##     - tags: smart, easygoing
##       target: river
## - id: mountain
##   speaker: donkey
##   text: "The mountain air is thin here."
##   next: reunited
## - id: river
##   speaker: donkey
##   text: "The river runs swift and cold."
##   next: reunited
## - id: turn_back
##   speaker: donkey
##   text: "Back to camp it is, then."
##   next: end
## - id: reunited
##   speaker: balaam
##   text: "Onward, regardless of the path taken."
## [/codeblock]
##
## The conversation's visible dialogue should allude to which kind of
## response leads where (e.g. a timid card turns back, a brash one takes the
## mountain). See [method find_option_for_tags] for how a played card picks
## an option; a card matching no option at all (including a card with no
## tags) follows the same fallback option as the timeout below.
##
## A branch response has a visible time limit (see [DialogueBox]'s
## "branch_timeout_seconds", overridable per-branch with a "timeout" key on
## the "branch: true" segment) after which one option is chosen
## automatically. That option is the one flagged "timeout: true" (not to be
## confused with the branch segment's own "timeout" duration); if no
## option is flagged, the first option is used as the automatic fallback. A
## timeout option may omit "tags" entirely, so no card ever picks it
## directly and it's reached only by letting the timer run out (i.e. by
## being indecisive) or by playing a card that matches nothing (or has no
## tags).
class_name DialogueParser
extends RefCounted

## Key nested lists (currently only "options") are collected under, keyed by
## indentation. Only one nesting level is supported.
const _NESTED_LIST_KEYS := ["options"]


## Loads a conversation file from [param path] and returns an [Array] of
## [Dictionary] entries shaped like {"speaker": String, "text": String},
## where "speaker" is a character id (see [CharacterParser]). Branch entries
## instead carry a "branch" key and an "options" array; see the class
## description for the full format.
static func load_conversation(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogueParser: could not open conversation file '%s'" % path)
		return []
	var content := file.get_as_text()
	return parse(content)


## Parses raw YAML-subset [param text] into an [Array] of dialogue/branch
## segments.
static func parse(text: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var current: Dictionary = {}
	var top_level_indent: int = -1

	# State for the nested list (e.g. a branch's "options") currently being
	# collected under a key of [member current], if any. Once non-empty,
	# every line belongs to this nested list (either starting a new item, on
	# a dash line, or adding a field to the item in progress) until the next
	# top-level entry starts.
	var nested_list_key: String = ""
	var nested_list: Array[Dictionary] = []
	var nested_current: Dictionary = {}

	for raw_line in text.split("\n"):
		var line := raw_line
		# Strip full-line and trailing comments (lines starting with '#').
		var comment_index := line.find("#")
		if comment_index != -1:
			line = line.substr(0, comment_index)
		if line.strip_edges().is_empty():
			continue

		var indent := line.length() - line.strip_edges(true, false).length()
		var is_dash_line := line.strip_edges().begins_with("-")
		var is_new_top_level_entry := is_dash_line \
			and (top_level_indent == -1 or indent == top_level_indent)

		if is_new_top_level_entry:
			_close_nested_list(current, nested_list_key, nested_list, nested_current)
			nested_list_key = ""
			nested_list = []
			nested_current = {}
			if not current.is_empty():
				segments.append(current)
			current = {}
			top_level_indent = indent
			line = line.substr(line.find("-") + 1)
		elif not nested_list_key.is_empty() and is_dash_line:
			# A new item in the nested list currently being collected.
			if not nested_current.is_empty():
				nested_list.append(nested_current)
			nested_current = {}
			line = line.substr(line.find("-") + 1)

		var colon_index := line.find(":")
		if colon_index == -1:
			continue
		var key := line.substr(0, colon_index).strip_edges()
		var value := line.substr(colon_index + 1).strip_edges()
		value = _unquote(value)
		if key.is_empty():
			continue

		if nested_list_key.is_empty() and value.is_empty() and key in _NESTED_LIST_KEYS:
			# Starts a nested list under this key (e.g. "options:" with the
			# list items on following, more-indented lines).
			nested_list_key = key
			nested_list = []
			nested_current = {}
			current[key] = nested_list
			continue

		if nested_list_key.is_empty():
			current[key] = value
		else:
			nested_current[key] = value

	_close_nested_list(current, nested_list_key, nested_list, nested_current)
	if not current.is_empty():
		segments.append(current)

	return segments


## Appends any in-progress [param nested_current] entry to [param
## nested_list] (which [param current] already holds a reference to under
## [param nested_list_key]), if a nested list was being collected.
static func _close_nested_list(
	current: Dictionary,
	nested_list_key: String,
	nested_list: Array[Dictionary],
	nested_current: Dictionary
) -> void:
	if nested_list_key.is_empty():
		return
	if not nested_current.is_empty():
		nested_list.append(nested_current)


## Returns whether [param segment] is a branch node (presents a card select
## of options rather than a line of dialogue).
static func is_branch(segment: Dictionary) -> bool:
	return str(segment.get("branch", "")).to_lower() == "true"


## Returns whether [param option] (one entry of a branch segment's "options"
## list) is flagged "timeout: true" - the option automatically selected if
## the branch's visible time limit expires before the player picks one (see
## the class description).
static func is_timeout_option(option: Dictionary) -> bool:
	return str(option.get("timeout", "")).to_lower() == "true"


## Returns the index (into [param options], a branch segment's "options"
## list) of the option triggered by a response card with [param card_tags]
## (see [method ResponseCardParser.parse_tags]), or [code]-1[/code] if none
## matches (always the case for a card with no tags). The card's tags are
## tried in order, so its first tag that any
## option responds to wins; among options sharing that tag, the first listed
## wins.
static func find_option_for_tags(options: Array, card_tags: PackedStringArray) -> int:
	for tag in card_tags:
		for i in options.size():
			if ResponseCardParser.parse_tags(options[i]).has(tag):
				return i
	return -1


## Returns the index (into [param options], a branch segment's "options"
## list) of the fallback option followed when a branch times out or a
## played card matches no option: the one flagged "timeout: true", else the
## first option, or [code]-1[/code] if [param options] is empty.
static func find_fallback_option(options: Array) -> int:
	for i in options.size():
		if is_timeout_option(options[i]):
			return i
	return 0 if not options.is_empty() else -1


static func _unquote(value: String) -> String:
	if value.length() >= 2:
		var first := value[0]
		var last := value[value.length() - 1]
		if (first == "\"" and last == "\"") or (first == "'" and last == "'"):
			return value.substr(1, value.length() - 2)
	return value
