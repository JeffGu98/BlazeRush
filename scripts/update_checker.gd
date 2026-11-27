extends Node
class_name UpdateChecker

const RELEASES_API := "https://api.github.com/repos/JeffGu98/BlazeRush/releases/latest"
const RELEASES_PAGE := "https://github.com/JeffGu98/BlazeRush/releases/latest"
const SEEN_PATH := "user://update_seen.cfg"

var _release_url := RELEASES_PAGE
var _update_bar: Control
var _target_parent: Control
var _hint_base_top := 0.0
var _hint_base_bottom := 0.0


func start(parent_panel: Control) -> void:
	_target_parent = parent_panel
	var http := HTTPRequest.new()
	http.timeout = 8.0
	http.use_threads = true
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(_on_response.bind(http))
	var headers := PackedStringArray([
		"User-Agent: BlazeRush",
		"Accept: application/vnd.github+json",
	])
	var err := http.request(RELEASES_API, headers)
	if err != OK:
		http.queue_free()


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var tag := str(data.get("tag_name", "")).strip_edges()
	var local_ver := str(ProjectSettings.get_setting("application/config/version", "0"))
	if tag.is_empty() or not is_newer(tag, local_ver):
		return
	if _was_dismissed(tag):
		return
	var url := str(data.get("html_url", "")).strip_edges()
	if not url.is_empty():
		_release_url = url
	_show_banner(tag)


static func is_newer(remote: String, local: String) -> bool:
	var a := _semver(remote)
	var b := _semver(local)
	for i in range(3):
		if a[i] > b[i]:
			return true
		if a[i] < b[i]:
			return false
	return false


static func _semver(raw: String) -> PackedInt32Array:
	var text := raw.strip_edges()
	if text.begins_with("v") or text.begins_with("V"):
		text = text.substr(1)
	var parts := text.split(".")
	var out := PackedInt32Array()
	for i in range(3):
		out.append(parts[i].to_int() if i < parts.size() else 0)
	return out


func _was_dismissed(tag: String) -> bool:
	var config := ConfigFile.new()
	if config.load(SEEN_PATH) != OK:
		return false
	return str(config.get_value("update", "dismissed", "")) == tag


func _dismiss(tag: String) -> void:
	var config := ConfigFile.new()
	config.set_value("update", "dismissed", tag)
	config.save(SEEN_PATH)


func _show_banner(tag: String) -> void:
	if _target_parent == null or not is_instance_valid(_target_parent):
		return
	if _update_bar != null and is_instance_valid(_update_bar):
		_update_bar.queue_free()
	var hint := _target_parent.get_node_or_null("Hint") as Control
	if hint != null:
		if is_zero_approx(_hint_base_bottom) and is_zero_approx(_hint_base_top):
			_hint_base_top = hint.offset_top
			_hint_base_bottom = hint.offset_bottom
		hint.offset_top = _hint_base_top - 80.0
		hint.offset_bottom = _hint_base_bottom - 80.0

	var bar := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.07, 0.09, 0.96)
	style.set_corner_radius_all(14)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 0.45, 0.18, 0.65)
	bar.add_theme_stylebox_override("panel", style)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 28
	bar.offset_right = -28
	bar.offset_top = -84
	bar.offset_bottom = -20
	_target_parent.add_child(bar)
	_update_bar = bar

	var open_btn := Button.new()
	open_btn.text = "  有新版本 %s　·　点此查看" % tag
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_btn.offset_right = -56
	open_btn.add_theme_font_size_override("font_size", 18)
	open_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38, 1))
	open_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_btn(open_btn, Color(0, 0, 0, 0))
	open_btn.pressed.connect(func(): OS.shell_open(_release_url))
	bar.add_child(open_btn)

	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	close.offset_left = -52
	close.offset_right = -8
	close.offset_top = -22
	close.offset_bottom = 22
	close.add_theme_font_size_override("font_size", 22)
	close.add_theme_color_override("font_color", Color(0.75, 0.65, 0.62, 1))
	_style_btn(close, Color(0, 0, 0, 0))
	close.pressed.connect(_hide_banner.bind(bar, tag))
	bar.add_child(close)


func _hide_banner(bar: Control, tag: String) -> void:
	_dismiss(tag)
	if bar != null and is_instance_valid(bar):
		bar.queue_free()
	if _update_bar == bar:
		_update_bar = null
	if _target_parent != null and is_instance_valid(_target_parent):
		var hint := _target_parent.get_node_or_null("Hint") as Control
		if hint != null and not is_zero_approx(_hint_base_bottom):
			hint.offset_top = _hint_base_top
			hint.offset_bottom = _hint_base_bottom


func _style_btn(btn: Button, bg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.45, 0.18, 0.16)
	hover.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.45, 0.18, 0.28)
	pressed.set_corner_radius_all(12)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
