extends Control

const EXAMPLE_CONVERSATION := "res://data/conversations/balaam_and_donkey.yml"

## Background colors used to visually distinguish the demo's sample cards.
const DEMO_CARD_COLORS: Array[Color] = [
	Color(0.85, 0.35, 0.35),
	Color(0.35, 0.65, 0.85),
	Color(0.45, 0.80, 0.45),
	Color(0.90, 0.75, 0.30),
	Color(0.65, 0.45, 0.85),
]

@onready var version_label: Label = $VersionLabel
@onready var start_conversation_button: Button = $StartConversationButton
@onready var dialogue_box: Control = $DialogueBox
@onready var card_swiper_demo_button: Button = $CardSwiperDemoButton
@onready var card_swiper_demo: Control = $CardSwiperDemo
@onready var card_swiper: CardSwiper = $CardSwiperDemo/CardSwiper
@onready var card_swiper_close_button: Button = $CardSwiperDemo/CloseButton
@onready var selected_card_label: Label = $CardSwiperDemo/SelectedCardLabel
@onready var card_scale_slider: HSlider = $CardSwiperDemo/ControlsPanel/CardScaleRow/CardScaleSlider
@onready var card_scale_value_label: Label = $CardSwiperDemo/ControlsPanel/CardScaleRow/CardScaleValueLabel
@onready var swipe_distance_slider: HSlider = $CardSwiperDemo/ControlsPanel/SwipeDistanceRow/SwipeDistanceSlider
@onready var swipe_distance_value_label: Label = $CardSwiperDemo/ControlsPanel/SwipeDistanceRow/SwipeDistanceValueLabel
@onready var card_spacing_slider: HSlider = $CardSwiperDemo/ControlsPanel/CardSpacingRow/CardSpacingSlider
@onready var card_spacing_value_label: Label = $CardSwiperDemo/ControlsPanel/CardSpacingRow/CardSpacingValueLabel

const NO_CARD_SELECTED_TEXT := "Double-tap a card to select it."

func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	version_label.text = "Version %s" % version
	start_conversation_button.pressed.connect(_on_start_conversation_button_pressed)
	dialogue_box.conversation_finished.connect(_on_conversation_finished)
	card_swiper_demo_button.pressed.connect(_on_card_swiper_demo_button_pressed)
	card_swiper_close_button.pressed.connect(_on_card_swiper_close_button_pressed)
	card_swiper.card_selected.connect(_on_card_swiper_card_selected)
	card_scale_slider.value = card_swiper.card_scale
	swipe_distance_slider.value = card_swiper.swipe_distance_ratio
	card_spacing_slider.value = card_swiper.card_spacing
	card_scale_value_label.text = "%.2f" % card_swiper.card_scale
	swipe_distance_value_label.text = "%.2f" % card_swiper.swipe_distance_ratio
	card_spacing_value_label.text = "%.0f" % card_swiper.card_spacing
	card_scale_slider.value_changed.connect(_on_card_scale_slider_value_changed)
	swipe_distance_slider.value_changed.connect(_on_swipe_distance_slider_value_changed)
	card_spacing_slider.value_changed.connect(_on_card_spacing_slider_value_changed)
	_populate_demo_cards()


func _on_start_conversation_button_pressed() -> void:
	start_conversation_button.visible = false
	dialogue_box.start_conversation(EXAMPLE_CONVERSATION)


func _on_conversation_finished() -> void:
	start_conversation_button.visible = true


func _on_card_swiper_demo_button_pressed() -> void:
	start_conversation_button.visible = false
	card_swiper_demo_button.visible = false
	card_swiper_demo.visible = true
	card_swiper.clear_selection()
	selected_card_label.text = NO_CARD_SELECTED_TEXT


func _on_card_swiper_close_button_pressed() -> void:
	card_swiper_demo.visible = false
	start_conversation_button.visible = true
	card_swiper_demo_button.visible = true


func _on_card_swiper_card_selected(index: int) -> void:
	selected_card_label.text = "Selected card index: %d" % index


func _on_card_scale_slider_value_changed(value: float) -> void:
	card_swiper.card_scale = value
	card_scale_value_label.text = "%.2f" % value


func _on_swipe_distance_slider_value_changed(value: float) -> void:
	card_swiper.swipe_distance_ratio = value
	swipe_distance_value_label.text = "%.2f" % value


func _on_card_spacing_slider_value_changed(value: float) -> void:
	card_swiper.card_spacing = value
	card_spacing_value_label.text = "%.0f" % value


## Builds a handful of simple colored/labeled cards so the swiper demo has
## something to display without depending on other gameplay data.
func _populate_demo_cards() -> void:
	var cards: Array[Control] = []
	for i in DEMO_CARD_COLORS.size():
		var card := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = DEMO_CARD_COLORS[i]
		style.set_corner_radius_all(12)
		card.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.text = "Card %d" % (i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(label)

		cards.append(card)
	card_swiper.set_cards(cards)

