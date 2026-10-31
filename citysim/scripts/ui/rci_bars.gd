class_name RciBars
extends Control
## Four demand bars (R / C / O / I). Positive demand fills upwards from the
## middle line in the zone colour, negative demand downwards in grey.

const GROUPS: PackedStringArray = ["residential", "commercial", "office", "industrial"]

var colors: Array[Color] = []
var letters: PackedStringArray = []
var values: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(150, 74)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(demand: Dictionary) -> void:
	values = demand
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var bar_w := 22.0
	var gap := (size.x - bar_w * GROUPS.size()) / (GROUPS.size() + 1)
	var label_h := 20.0
	var mid := (size.y - label_h) * 0.5
	var half := mid - 4.0
	draw_line(Vector2(gap * 0.5, mid), Vector2(size.x - gap * 0.5, mid), Color(1, 1, 1, 0.35), 2.0)
	for i in GROUPS.size():
		var x := gap + i * (bar_w + gap)
		var v := clampf(float(values.get(GROUPS[i], 0.0)), -1.0, 1.0)
		draw_rect(Rect2(x, mid - half, bar_w, half * 2.0), Color(0, 0, 0, 0.25))
		if v >= 0.0:
			draw_rect(Rect2(x, mid - half * v, bar_w, half * v), colors[i])
		else:
			draw_rect(Rect2(x, mid, bar_w, -half * v), Color(0.55, 0.57, 0.6))
		draw_string_outline(font, Vector2(x, size.y - 3), letters[i], HORIZONTAL_ALIGNMENT_CENTER, bar_w, 18, 5, Color(0.07, 0.09, 0.13, 0.9))
		draw_string(font, Vector2(x, size.y - 3), letters[i], HORIZONTAL_ALIGNMENT_CENTER, bar_w, 18, Color.WHITE)
