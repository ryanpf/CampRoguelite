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
class_name DialogueParser
extends RefCounted


## Loads a conversation file from [param path] and returns an [Array] of
## [Dictionary] entries shaped like {"speaker": String, "text": String},
## where "speaker" is a character id (see [CharacterParser]).
static func load_conversation(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogueParser: could not open conversation file '%s'" % path)
		return []
	var content := file.get_as_text()
	return parse(content)


## Parses raw YAML-subset [param text] into an [Array] of dialogue segments.
static func parse(text: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var current: Dictionary = {}

	for raw_line in text.split("\n"):
		var line := raw_line
		# Strip full-line and trailing comments (lines starting with '#').
		var comment_index := line.find("#")
		if comment_index != -1:
			line = line.substr(0, comment_index)
		if line.strip_edges().is_empty():
			continue

		var is_new_entry := line.strip_edges().begins_with("-")
		if is_new_entry:
			if not current.is_empty():
				segments.append(current)
			current = {}
			# Remove the leading "-" so the rest parses like "key: value".
			var dash_index := line.find("-")
			line = line.substr(dash_index + 1)

		var colon_index := line.find(":")
		if colon_index == -1:
			continue
		var key := line.substr(0, colon_index).strip_edges()
		var value := line.substr(colon_index + 1).strip_edges()
		value = _unquote(value)
		if key.is_empty():
			continue
		current[key] = value

	if not current.is_empty():
		segments.append(current)

	return segments


static func _unquote(value: String) -> String:
	if value.length() >= 2:
		var first := value[0]
		var last := value[value.length() - 1]
		if (first == "\"" and last == "\"") or (first == "'" and last == "'"):
			return value.substr(1, value.length() - 2)
	return value
