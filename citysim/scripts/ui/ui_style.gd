class_name UiStyle
extends RefCounted
## Shared look for the city-builder HUD: chunky rounded font with outline,
## resource "pills" with coloured icon badges, round 3D-looking buttons and
## light cards for menus. Icons are Lucide (ISC), font is Nunito (OFL);
## licences live next to the files in res://assets/ui/.

const ICON_DIR := "res://assets/ui/icons/"
const FONT_PATH := "res://assets/ui/fonts/Nunito-Variable.ttf"

const TEXT := Color(1.0, 1.0, 1.0)
const TEXT_OUTLINE := Color(0.07, 0.09, 0.13, 0.9)
const PILL_BG := Color(0.04, 0.06, 0.1, 0.6)
const CARD_BG := Color(0.93, 0.95, 0.97, 0.98)
const CARD_HEADER := Color(0.2, 0.52, 0.85)
const CARD_TEXT := Color(0.13, 0.19, 0.25)

const BLUE := Color(0.22, 0.56, 0.9)
const GREEN := Color(0.3, 0.72, 0.33)
const GOLD := Color(0.98, 0.72, 0.15)
const ORANGE := Color(0.96, 0.55, 0.12)
const RED := Color(0.9, 0.3, 0.27)
const PURPLE := Color(0.58, 0.4, 0.82)
const TEAL := Color(0.15, 0.68, 0.7)
const SLATE := Color(0.36, 0.42, 0.5)
const YELLOW := Color(0.96, 0.8, 0.2)

static var _fonts: Dictionary = {}


static func font(weight: int) -> FontVariation:
	if not _fonts.has(weight):
		var fv := FontVariation.new()
		fv.base_font = load(FONT_PATH)
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		_fonts[weight] = fv
	return _fonts[weight]


static func icon(icon_name: String) -> Texture2D:
	return load(ICON_DIR + icon_name + ".svg")


static func build_theme(font_size: int) -> Theme:
	var theme := Theme.new()
	theme.default_font = font(800)
	theme.default_font_size = font_size
	for type: String in ["Label", "Button", "CheckButton"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_outline_color", type, TEXT_OUTLINE)
		theme.set_constant("outline_size", type, 6)
	theme.set_stylebox("panel", "PanelContainer", pill_box())
	return theme


## Light menu card; labels inside get dark text without outline.
static func card_theme(font_size: int) -> Theme:
	var theme := Theme.new()
	theme.default_font = font(700)
	theme.default_font_size = font_size
	for type: String in ["Label", "CheckButton"]:
		theme.set_color("font_color", type, CARD_TEXT)
		theme.set_color("font_hover_color", type, CARD_TEXT)
		theme.set_color("font_pressed_color", type, CARD_TEXT)
		theme.set_color("font_hover_pressed_color", type, CARD_TEXT)
		theme.set_constant("outline_size", type, 0)
	var segment := flat_box(Color(0.82, 0.86, 0.9), 14)
	var segment_on := flat_box(BLUE, 14)
	theme.set_stylebox("normal", "Button", segment)
	theme.set_stylebox("hover", "Button", segment)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("pressed", "Button", segment_on)
	theme.set_stylebox("hover_pressed", "Button", segment_on)
	theme.set_color("font_color", "Button", CARD_TEXT)
	theme.set_color("font_hover_color", "Button", CARD_TEXT)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_constant("outline_size", "Button", 0)
	return theme


static func flat_box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(10)
	box.anti_aliasing = true
	return box


static func pill_box() -> StyleBoxFlat:
	var box := flat_box(PILL_BG, 40)
	box.content_margin_left = 4
	box.content_margin_right = 22
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


static func card_box() -> StyleBoxFlat:
	var box := flat_box(CARD_BG, 26)
	box.set_content_margin_all(0)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 4)
	return box


## Round "candy" button face: base colour with a darker lip at the bottom.
static func circle_box(color: Color, size: float, lip: int, pressed: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.lightened(0.08) if not pressed else color.darkened(0.08)
	box.set_corner_radius_all(int(size * 0.5))
	box.border_color = color.darkened(0.35)
	box.border_width_bottom = lip if not pressed else maxi(lip / 2, 1)
	box.border_width_top = 0 if not pressed else lip / 2
	box.set_border_width(SIDE_LEFT, 2)
	box.set_border_width(SIDE_RIGHT, 2)
	box.anti_aliasing = true
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 4 if not pressed else 1
	box.shadow_offset = Vector2(0, 3)
	return box


static func round_button(icon_name: String, color: Color, size: float, toggle: bool = false,
		on_color: Color = Color.TRANSPARENT) -> Button:
	var b := Button.new()
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.icon = icon(icon_name)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var lip := maxi(int(size * 0.07), 3)
	var pad := int(size * 0.24)
	var normal := circle_box(color, size, lip, false)
	# Toggle buttons can light up in a different colour when switched on.
	var down := circle_box(on_color if on_color.a > 0.0 else color, size, lip, true)
	for box: StyleBoxFlat in [normal, down]:
		box.content_margin_left = pad
		box.content_margin_right = pad
		box.content_margin_top = pad
		box.content_margin_bottom = pad
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("hover_pressed", down)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", circle_box(SLATE, size, lip, false))
	b.pressed.connect(func() -> void: EventBus.sfx_requested.emit("ui_click"))
	return b


## Rounded rectangular toggle with the same candy look as round buttons.
static func chip_button(text: String, color: Color, on_color: Color, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	var lip := 4
	var normal := circle_box(color, 32.0, lip, false)
	var down := circle_box(on_color, 32.0, lip, true)
	for box: StyleBoxFlat in [normal, down]:
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("hover_pressed", down)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: EventBus.sfx_requested.emit("ui_click"))
	return b


## Coloured circular icon badge used at the left end of a resource pill.
static func badge(icon_name: String, color: Color, size: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := circle_box(color, size, 3, false)
	var pad := int(size * 0.2)
	box.set_content_margin_all(pad)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(size, size)
	var tex := TextureRect.new()
	tex.texture = icon(icon_name)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tex)
	return panel


## Greys out a tool that a milestone has not unlocked yet (it stays
## pressable so it can say what unlocks it).
static func set_locked(c: Control, locked: bool) -> void:
	c.modulate = Color(0.55, 0.56, 0.6, 0.8) if locked else Color.WHITE


## Formats an integer with Turkish thousands separators: 1234567 -> "1.234.567".
static func format_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if value < 0 else "") + out


static func label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Light menu card with a coloured header, a title and a round close button.
## Returns [card, content VBoxContainer]. The card starts hidden.
static func card(title_key: String, width: float, font_size: int, min_touch: float) -> Array:
	var c := PanelContainer.new()
	c.visible = false
	c.custom_minimum_size.x = width
	c.add_theme_stylebox_override("panel", card_box())
	c.theme = card_theme(font_size - 2)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	c.add_child(col)

	var header := PanelContainer.new()
	var header_box := flat_box(CARD_HEADER, 26)
	header_box.corner_radius_bottom_left = 0
	header_box.corner_radius_bottom_right = 0
	header_box.content_margin_left = 24
	header_box.content_margin_right = 12
	header.add_theme_stylebox_override("panel", header_box)
	var header_row := HBoxContainer.new()
	header.add_child(header_row)
	var title := label(title_key, font_size + 2)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	var close := round_button("x", RED, min_touch * 0.8)
	close.pressed.connect(func() -> void: c.visible = false)
	header_row.add_child(close)
	col.add_child(header)

	var body := MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body.add_theme_constant_override(side, 22)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	body.add_child(content)
	col.add_child(body)
	return [c, content]
