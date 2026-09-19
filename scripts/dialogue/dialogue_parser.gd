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
## true" key and a nested "options" list presents a choice instead of a line
## of dialogue; each option is a mapping with its own "text" (shown on a
## card) and "target" (the id to jump to when that card is selected), for
## example:
##
## [codeblock]
## - id: crossroads
##   speaker: balaam
##   text: "Which path shall we take?"
## - branch: true
##   options:
##     - text: "Take the mountain pass"
##       target: mountain
##     - text: "Take the river road"
##       target: river
## - id: mountain
##   speaker: donkey
##   text: "The mountain air is thin here."
##   next: reunited
## - id: river
##   speaker: donkey
##   text: "The river runs swift and cold."
##   next: reunited
## - id: reunited
##   speaker: balaam
##   text: "Onward, regardless of the path taken."
## [/codeblock]
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


static func _unquote(value: String) -> String:
	if value.length() >= 2:
		var first := value[0]
		var last := value[value.length() - 1]
		if (first == "\"" and last == "\"") or (first == "'" and last == "'"):
			return value.substr(1, value.length() - 2)
	return value
