class_name LineChart
extends Control
## A simple line chart of one series (oldest value first): light grid,
## filled area under the line, the latest value and the range labelled.
## Drawn with Control._draw, no textures.

var values := PackedFloat32Array()
var color := Color(0.22, 0.56, 0.9)
var format: Callable = func(v: float) -> String: return str(roundi(v))
var unit_label: String = ""
var zero_based: bool = true


func set_series(new_values: PackedFloat32Array, new_color: Color, new_format: Callable, from_zero: bool, label: String) -> void:
	values = new_values
	color = new_color
	format = new_format
	zero_based = from_zero
	unit_label = label
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := get_theme_default_font_size() - 6
	var r := Rect2(Vector2(70, 14), size - Vector2(86, 50))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.93, 0.95, 0.97), true)
	if values.size() < 2:
		draw_string(font, Vector2(20, size.y * 0.5), TranslationServer.translate("CHART_NOT_ENOUGH"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.35, 0.4, 0.45))
		return
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if zero_based:
		lo = minf(lo, 0.0)
	if is_equal_approx(hi, lo):
		hi = lo + 1.0
	var pad := (hi - lo) * 0.08
	hi += pad
	if not zero_based:
		lo -= pad
	var grid := Color(0.78, 0.82, 0.86)
	var text := Color(0.3, 0.35, 0.4)
	for k in 4:
		var t := float(k) / 3.0
		var y := r.position.y + r.size.y * (1.0 - t)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), grid, 1.0)
		draw_string(font, Vector2(4, y + fs * 0.35), format.call(lerpf(lo, hi, t)), HORIZONTAL_ALIGNMENT_LEFT, 62, fs, text)
	# Zero line when the series crosses it (e.g. a monthly budget).
	if lo < 0.0 and hi > 0.0:
		var zy := r.position.y + r.size.y * (1.0 - (0.0 - lo) / (hi - lo))
		draw_line(Vector2(r.position.x, zy), Vector2(r.end.x, zy), Color(0.55, 0.3, 0.3), 1.5)
	var pts := PackedVector2Array()
	var n := values.size()
	for i in n:
		var x := r.position.x + r.size.x * float(i) / float(n - 1)
		var y := r.position.y + r.size.y * (1.0 - (values[i] - lo) / (hi - lo))
		pts.append(Vector2(x, y))
	var base_y := r.end.y if lo >= 0.0 else r.position.y + r.size.y * (1.0 - (0.0 - lo) / (hi - lo))
	var area := pts.duplicate()
	area.append(Vector2(pts[n - 1].x, base_y))
	area.append(Vector2(pts[0].x, base_y))
	draw_colored_polygon(area, Color(color, 0.18))
	draw_polyline(pts, color, 3.0, true)
	draw_circle(pts[n - 1], 5.0, color)
	draw_string(font, Vector2(r.position.x, size.y - 10), unit_label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.6, fs, text)
	draw_string(font, Vector2(r.end.x - 200, size.y - 10), TranslationServer.translate("CHART_NOW") % format.call(values[n - 1]),
		HORIZONTAL_ALIGNMENT_RIGHT, 200, fs, color.darkened(0.25))
