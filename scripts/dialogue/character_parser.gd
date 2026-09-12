## Parses character definition files written in the same human-readable YAML
## subset as [DialogueParser], so writers can define characters that can be
## referenced as conversation speakers by id.
##
## Supported format is a list of mappings, each with an "id", "name", and
## "portrait" key, for example:
##
## [codeblock]
## - id: balaam
##   name: Balaam
##   portrait: "res://data/art/Wizard1.png"
## [/codeblock]
class_name CharacterParser
extends RefCounted


## Loads the character file at [param path] and returns a [Dictionary]
## mapping character id to a Dictionary shaped like
## {"name": String, "portrait": Texture2D}.
static func load_characters(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CharacterParser: could not open character file '%s'" % path)
		return {}
	var content := file.get_as_text()
	return parse(content)


## Parses raw YAML-subset [param text] into a [Dictionary] mapping character
## id to a Dictionary shaped like {"name": String, "portrait": Texture2D}.
static func parse(text: String) -> Dictionary:
	var characters: Dictionary = {}
	for entry in DialogueParser.parse(text):
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		var portrait: Texture2D = null
		var portrait_path := str(entry.get("portrait", ""))
		if not portrait_path.is_empty():
			portrait = load(portrait_path) as Texture2D
		characters[id] = {
			"name": str(entry.get("name", id)),
			"portrait": portrait,
		}
	return characters
