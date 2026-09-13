extends Control

## BEGINNER MAP
## This script is attached to the full-window Control in main.tscn.
## Godot calls _ready once, _process every frame, and _input for input events.
## UI nodes are created in code, so _build_ui is our equivalent of a visual scene.
## Saving/math live in benchmark_store.gd; this file handles the screen and run.
## Functions beginning with '_' are internal helpers by convention, not magic,
## except Godot callbacks such as _ready, _process and _input.

const Store = preload("res://benchmark_store.gd")
# An enum gives names to the possible states instead of using unexplained numbers.
# Normal flow: IDLE -> RELEASE -> WAIT -> PENDING_GREEN -> GO -> FEEDBACK.
# FEEDBACK goes back to RELEASE, or to COMPLETE when enough trials are recorded.
# RELEASE and WAIT both draw red. Only GO accepts a scored response.
enum Phase { IDLE, RELEASE, WAIT, PENDING_GREEN, GO, FEEDBACK, COMPLETE }
const WAIT_RED := Color("b6253b")
const GO_GREEN := Color("087f50")
const MUTED := Color("99acc2")
const ACCENT := Color("60e2b5")
const PAGE_SIZE := 5
const TRIAL_PAGE_SIZE := 10
# Durations are microseconds: 1 second = 1,000,000 microseconds.
const RELEASE_SETTLE_US := 700000
const WAIT_MIN_US := 1800000
const WAIT_MAX_US := 5000000
const RESPONSE_TIMEOUT_US := 10000000
const FEEDBACK_US := 1100000
const TRIGGER_PRESS := 0.5
const TRIGGER_RELEASE := 0.2
var phase := Phase.IDLE
# This dictionary acts as a set: each key is a held button, e.g. "button:0".
# A single true/false flag would fail when two buttons are held at once.
var held_inputs: Dictionary = {}
# *_us values are monotonic timestamps/durations, not the calendar time.
var deadline: int = 0
var green_us: int = 0
var release_since: int = 0
var samples: Array = []
# Parallel arrays: sample_buttons[i] tells us which input produced samples[i].
var sample_buttons: Array = []
var false_starts := 0
var timeouts := 0
var target := 10
var run_name := ""
var run_device: Dictionary = {}
# A completed run stays here until saving succeeds. Starting again is blocked
# while it is pending, so a disk error cannot silently discard the user's score.
var pending_record: Dictionary = {}
var frame_times: Array = []
var records: Array = []
# user:// is Godot's writable app-data directory. Tests replace this path with
# their own temporary fixture directory so they never touch real results.
var results_folder := "user://results"
# Page indexes start at zero internally; captions display human-friendly counts.
var board_page := 0
var trial_page := 0
var selected_record := -1
var last_trashed := ""
var trash_icon: ImageTexture
# Keep references to controls that we need to update after constructing the UI.
var menu: MarginContainer
var name_edit: LineEdit
var count_edit: SpinBox
var device_picker: OptionButton
var device_info: Label
var input_led: TextureRect
var input_check_label: Label
var led_on: ImageTexture
var led_off: ImageTexture
var input_check_active := false
var input_flash_until := 0
const INPUT_FLASH_US := 180000
var notice: Label
var board: Tree
var detail: Label
var trial_values: Label
var board_page_label: Label
var trial_page_label: Label
var previous_button: Button
var next_button: Button
var trial_previous: Button
var trial_next: Button
var undo_button: Button
var fullscreen_check: CheckBox
var vsync_check: CheckBox
var retry_button: Button
var start_button: Button
var overlay: ColorRect
var cue: Label
var cue_detail: Label
var cue_progress: Label

func _ready() -> void:
	# Don't merge input events until the next frame. This reduces avoidable delay,
	# but it cannot remove delays in the controller, OS, renderer or monitor.
	Input.use_accumulated_input = false
	Engine.max_fps = 0
	get_window().min_size = Vector2i(880, 624)
	_build_ui()
	_refresh_devices()
	_refresh_board()
	# Signals are notifications: connect() says which function should receive one.
	Input.joy_connection_changed.connect(_device_changed)
	RenderingServer.frame_pre_draw.connect(_before_draw)
	get_window().focus_exited.connect(_focus_lost)

func _label(text: String, size: int = 16, color: Color = Color.WHITE) -> Label:
	# A factory helper keeps shared text styling in one place.
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, action: Callable, height: int = 42) -> Button:
	# A Callable is a function passed as a value. Run it when this button is pressed.
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = height
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	_style_button(button, height < 40)
	return button

func _style_button(button: Button, compact: bool = false, primary: bool = false) -> void:
	# Every state uses identical padding. Otherwise Godot's fallback hover_pressed
	# style can shift checkbox text when the pointer moves over a checked control.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(8)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 3 if compact else 8
		box.content_margin_bottom = 3 if compact else 8
		box.bg_color = Color("207557") if primary else Color("1d2b40")
		if state in ["hover", "hover_pressed"]:
			box.bg_color = Color("298c69") if primary else Color("304966")
		elif state == "disabled":
			box.bg_color = Color("172234")
		button.add_theme_stylebox_override(state, box)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = ACCENT
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(8)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_disabled_color", Color("75869a"))
	button.add_theme_constant_override("h_separation", 8)
	if button is CheckBox:
		# Matching icon dimensions keep the caption in the same place when toggled.
		for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			var color := "#75869a" if icon_name.ends_with("disabled") else "#afc0d3"
			var tick := '<path d="M4 8l3 3 5-6"/>' if icon_name.begins_with("checked") else ""
			var icon := Image.new()
			icon.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><g fill="none" stroke="%s" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="1.5" y="1.5" width="13" height="13" rx="2"/>%s</g></svg>' % [color, tick])
			button.add_theme_icon_override(icon_name, ImageTexture.create_from_image(icon))

func _single_line(label: Label) -> void:
	# Keep long names/messages from changing the layout. Their tooltips retain text.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _build_ui() -> void:
	# Containers arrange their children automatically; no hard-coded text positions.
	# Sections below build the theme, setup column, results column, and trial screen.
	var app_theme := Theme.new()
	app_theme.default_font_size = 16
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d2b40")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	app_theme.set_stylebox("normal", "Button", style)
	var hover := style.duplicate()
	hover.bg_color = Color("304966")
	app_theme.set_stylebox("hover", "Button", hover)
	app_theme.set_stylebox("pressed", "Button", hover)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color("193e37")
	selected_style.set_corner_radius_all(4)
	app_theme.set_stylebox("selected", "Tree", selected_style)
	app_theme.set_stylebox("selected_focus", "Tree", selected_style)
	theme = app_theme
	# Tiny vector icons are drawn locally, so no downloaded images are required.
	var icon_image := Image.new()
	icon_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"><g fill="none" stroke="#f59aa8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/></g></svg>')
	trash_icon = ImageTexture.create_from_image(icon_image)
	menu = MarginContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		menu.add_theme_constant_override("margin_" + side, 24)
	add_child(menu)
	var page := VBoxContainer.new()
	# VBox stacks vertically; HBox places children beside each other.
	page.add_theme_constant_override("separation", 8)
	menu.add_child(page)
	# The reference card shares the header row rather than covering existing controls.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	page.add_child(header)
	var introduction := VBoxContainer.new()
	introduction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	introduction.add_theme_constant_override("separation", 8)
	header.add_child(introduction)
	introduction.add_child(_label("Reaction Lab", 14, ACCENT))
	introduction.add_child(_label("Controller reaction benchmark", 32))
	introduction.add_child(_label("Choose a device. Wait for green. Press any button.", 16, MUTED))
	header.add_child(_age_reference_card())
	page.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 28)
	page.add_child(columns)
	var setup := VBoxContainer.new()
	# LEFT COLUMN: name, trial count, input selection, and display settings.
	setup.custom_minimum_size.x = 340
	setup.add_theme_constant_override("separation", 8)
	columns.add_child(setup)
	setup.add_child(_label("New benchmark", 14, ACCENT))
	setup.add_child(_label("Benchmark name", 14, MUTED))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Example: Xbox wired"
	name_edit.max_length = 100
	setup.add_child(name_edit)
	var trial_row := HBoxContainer.new()
	setup.add_child(trial_row)
	var trial_label := _label("Trials to complete", 14, MUTED)
	trial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trial_row.add_child(trial_label)
	count_edit = SpinBox.new()
	count_edit.min_value = 1
	count_edit.max_value = 200
	count_edit.value = 10
	count_edit.custom_minimum_size.x = 112
	trial_row.add_child(count_edit)
	setup.add_child(_label("Input device", 14, MUTED))
	device_picker = OptionButton.new()
	device_picker.fit_to_longest_item = false
	device_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	device_picker.custom_minimum_size.y = 38
	device_picker.item_selected.connect(func(_index: int) -> void:
		# This inline function is a small signal handler, sometimes called a lambda.
		held_inputs.clear()
		_update_device_info())
	setup.add_child(device_picker)
	device_info = _label("", 13, MUTED)
	device_info.custom_minimum_size.y = 48
	setup.add_child(device_info)
	# A small LED and text confirm input without starting or recording a benchmark.
	var input_check := HBoxContainer.new()
	input_check.add_theme_constant_override("separation", 8)
	setup.add_child(input_check)
	input_led = TextureRect.new()
	input_led.custom_minimum_size = Vector2(20, 20)
	input_led.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	input_led.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	input_led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_check.add_child(input_led)
	led_off = _make_led(false)
	led_on = _make_led(true)
	input_led.texture = led_off
	input_check_label = _label("Press a button to check this device", 13, MUTED)
	input_check_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_single_line(input_check_label)
	input_check.add_child(input_check_label)
	input_check.tooltip_text = "Lights up for the selected device's buttons, keys or triggers. No result is recorded."
	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "Fullscreen during benchmark"
	fullscreen_check.button_pressed = true
	_style_button(fullscreen_check)
	setup.add_child(fullscreen_check)
	vsync_check = CheckBox.new()
	vsync_check.text = "VSync"
	vsync_check.tooltip_text = "May add display delay. Keep this setting the same across comparisons."
	_style_button(vsync_check)
	setup.add_child(vsync_check)
	start_button = _button("Start benchmark  →", _start_run, 48)
	_style_button(start_button, false, true)
	setup.add_child(start_button)
	retry_button = _button("Retry save", _save_pending)
	retry_button.hide()
	setup.add_child(retry_button)
	var results := VBoxContainer.new()
	# RIGHT COLUMN: fixed-size pages prevent long histories from adding scrollbars.
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_theme_constant_override("separation", 8)
	columns.add_child(results)
	results.add_child(_label("Local leaderboard", 14, ACCENT))
	results.add_child(_label("Lowest average first · each benchmark saved separately", 14, MUTED))
	board = Tree.new()
	board.custom_minimum_size.y = 213
	board.columns = 4
	board.hide_root = true
	# Tree requires a root item; hide it so the user sees only benchmark rows.
	board.select_mode = Tree.SELECT_ROW
	board.scroll_horizontal_enabled = false
	board.scroll_vertical_enabled = false
	board.column_titles_visible = true
	board.set_column_title(0, "Benchmark")
	board.set_column_title(1, "Average (ms)")
	board.set_column_title(2, "Trials")
	for column in [1, 2, 3]:
		board.set_column_expand(column, false)
	board.set_column_custom_minimum_width(1, 110)
	board.set_column_custom_minimum_width(2, 52)
	board.set_column_custom_minimum_width(3, 36)
	board.add_theme_constant_override("v_separation", 4)
	board.item_selected.connect(_show_record)
	board.button_clicked.connect(_trash_clicked)
	results.add_child(board)
	var paging := HBoxContainer.new()
	results.add_child(paging)
	previous_button = _button("←", func() -> void: _change_page(-1), 30)
	previous_button.tooltip_text = "Previous five results"
	paging.add_child(previous_button)
	board_page_label = _label("", 13, MUTED)
	board_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paging.add_child(board_page_label)
	next_button = _button("→", func() -> void: _change_page(1), 30)
	next_button.tooltip_text = "Next five results"
	paging.add_child(next_button)
	detail = _label("", 14, MUTED)
	detail.custom_minimum_size.y = 64
	results.add_child(detail)
	trial_values = _label("", 13, ACCENT)
	trial_values.custom_minimum_size.y = 20
	_single_line(trial_values)
	results.add_child(trial_values)
	var trial_paging := HBoxContainer.new()
	results.add_child(trial_paging)
	trial_previous = _button("←", func() -> void: _change_trial_page(-1), 28)
	trial_previous.tooltip_text = "Previous ten trial times"
	trial_paging.add_child(trial_previous)
	trial_page_label = _label("", 12, MUTED)
	trial_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trial_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trial_paging.add_child(trial_page_label)
	trial_next = _button("→", func() -> void: _change_trial_page(1), 28)
	trial_next.tooltip_text = "Next ten trial times"
	trial_paging.add_child(trial_next)
	var files := HBoxContainer.new()
	results.add_child(files)
	var open_button := _button("Open results folder ↗", func() -> void:
		DirAccess.make_dir_recursive_absolute(results_folder)
		OS.shell_open(ProjectSettings.globalize_path(results_folder)), 32)
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files.add_child(open_button)
	undo_button = _button("Undo trash", _undo_trash, 32)
	undo_button.disabled = true
	files.add_child(undo_button)
	notice = _label("Enter a benchmark name, choose a device, then select Start benchmark.", 14, ACCENT)
	_single_line(notice)
	page.add_child(notice)
	page.add_child(HSeparator.new())
	page.add_child(_label("Wait for green before pressing. Early presses repeat the trial. Press Esc to cancel.", 14, MUTED))
	page.add_child(_label("Measures reaction time, including display and input delay. Use the same display and settings for comparisons.", 13, MUTED))
	overlay = ColorRect.new()
	# TRIAL SCREEN: this full-window rectangle covers the setup while a run is active.
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 45)
	margin.add_theme_constant_override("margin_right", 45)
	overlay.add_child(margin)
	var cues := VBoxContainer.new()
	cues.alignment = BoxContainer.ALIGNMENT_CENTER
	cues.add_theme_constant_override("separation", 20)
	margin.add_child(cues)
	cue_progress = _label("", 18)
	_single_line(cue_progress)
	cue = _label("", 64)
	cue_detail = _label("", 20)
	for label in [cue_progress, cue, cue_detail]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cues.add_child(label)
	overlay.hide()

func _set_notice(text: String) -> void:
	# Keep the full message available on hover if its visible line is shortened.
	notice.text = text
	notice.tooltip_text = text

func _refresh_devices() -> void:
	# Dropdown metadata stores stable device IDs, not the dropdown row number.
	# -1 means keyboard and -2 means mouse; nonnegative IDs belong to controllers.
	var previous := _selected_device() if device_picker.item_count > 0 else -99
	device_picker.clear()
	device_picker.add_item("Keyboard (including USB buttons)")
	device_picker.set_item_metadata(0, -1)
	device_picker.add_item("Mouse (including USB buttons)")
	device_picker.set_item_metadata(1, -2)
	for device in Input.get_connected_joypads():
		device_picker.add_item(Input.get_joy_name(device) + "  (#%d)" % device)
		device_picker.set_item_metadata(device_picker.item_count - 1, device)
	device_picker.select(2 if device_picker.item_count > 2 else 0)
	for i in device_picker.item_count:
		if device_picker.get_item_metadata(i) == previous:
			device_picker.select(i)
	_update_device_info()

func _selected_device() -> int:
	# Reading metadata avoids mistaking dropdown row 2 for controller device 2.
	return int(device_picker.get_selected_metadata())

func _device_metadata() -> Dictionary:
	# A Dictionary is a set of named values, like {"name": "Xbox", "vendor_id": 123}.
	var device := _selected_device()
	if device < 0:
		return {"name": "Keyboard" if device == -1 else "Mouse", "backend": "OS keyboard / mouse events"}
	var info := Input.get_joy_info(device).duplicate()
	info["name"] = Input.get_joy_name(device)
	info["guid"] = Input.get_joy_guid(device)
	info["mapped"] = Input.is_joy_known(device)
	return info

func _update_device_info() -> void:
	# Show device identification and reset the input-check flash on selection changes.
	var info := _device_metadata()
	if _selected_device() < 0:
		device_info.text = "Use any key except Esc." if _selected_device() == -1 else "Use any mouse button. Scrolling does not count."
	else:
		device_info.text = "Vendor / product ID: %04X / %04X · %s\nUse any button, D-pad direction or trigger." % [int(info.get("vendor_id", 0)), int(info.get("product_id", 0)), "XInput" if info.has("xinput_index") else "SDL input"]
	device_info.tooltip_text = JSON.stringify(info, "  ")
	device_picker.tooltip_text = str(info.name)
	input_flash_until = 0
	_refresh_input_indicator(Time.get_ticks_usec())

func _device_changed(device: int, connected: bool) -> void:
	# Cancel only when the device being tested disappears; unrelated hotplug is safe.
	if device == _selected_device() and not connected:
		if phase != Phase.IDLE and phase != Phase.COMPLETE:
			_cancel("The selected device disconnected. Benchmark cancelled.")
		held_inputs.clear()
		_refresh_devices()
	elif phase == Phase.IDLE or phase == Phase.COMPLETE:
		_refresh_devices()

func _event_button(event: InputEvent) -> Dictionary:
	# Convert different event classes into one common {id, pressed} shape.
	# An empty dictionary means "ignore this event" (wrong device, stick drift, etc.).
	var device := _selected_device()
	if device >= 0 and event.device == device:
		if event is InputEventJoypadButton:
			return {"id": "button:%d" % event.button_index, "pressed": event.pressed}
		if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			var id := "trigger:%d" % event.axis
			# Hysteresis rejects analog noise while allowing both triggers as buttons.
			# Press above 50%; once pressed, require dropping below 20% to release.
			var pressed: bool = event.axis_value > (TRIGGER_RELEASE if held_inputs.has(id) else TRIGGER_PRESS)
			return {"id": id, "pressed": pressed}
	if device == -1 and event is InputEventKey and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return {"id": "key:%d" % code, "pressed": event.pressed}
	if device == -2 and event is InputEventMouseButton and event.button_index > 0 and event.button_index not in [4, 5, 6, 7]:
		return {"id": "mouse:%d" % event.button_index, "pressed": event.pressed}
	return {}

func _input(event: InputEvent) -> void:
	# Take the timestamp FIRST, before UI updates or other work can delay it.
	var received_us := Time.get_ticks_usec()
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if event.pressed and phase != Phase.IDLE and phase != Phase.COMPLETE:
			_cancel("Benchmark cancelled. Saved results are unchanged.")
		return
	var button := _event_button(event)
	if button.is_empty():
		return
	var was_held := held_inputs.has(button.id)
	# Track releases too, including on the menu, so holding a button cannot re-arm.
	if button.pressed:
		held_inputs[button.id] = true
	else:
		held_inputs.erase(button.id)
	if phase in [Phase.IDLE, Phase.COMPLETE]:
		if button.pressed and not was_held:
			input_flash_until = received_us + INPUT_FLASH_US
		_refresh_input_indicator(received_us)
		return
	get_viewport().set_input_as_handled()
	# Stop this event from also activating hidden menu controls during a trial.
	if not button.pressed or was_held:
		return
	if phase in [Phase.RELEASE, Phase.WAIT, Phase.PENDING_GREEN]:
		false_starts += 1
		_feedback("Don't cheat!", "Too early. Wait for green. This trial will repeat.", received_us)
	elif phase == Phase.GO:
		# Input can arrive before _process notices the deadline. Check it here too.
		if received_us - green_us >= RESPONSE_TIMEOUT_US:
			timeouts += 1
			_feedback("No response", "No input within 10 seconds. This trial will repeat.", received_us)
			return
		var elapsed := (received_us - green_us) / 1000.0
		# Divide microseconds by 1,000 to store milliseconds as a decimal number.
		samples.append(elapsed)
		sample_buttons.append(button.id)
		_feedback("%.1f ms" % elapsed, "Trial recorded. " + _release_instruction(), received_us)

func _snapshot_held() -> void:
	# Catch controller/mouse buttons held before Start, even if their press event
	# happened before device selection. They must be released before arming.
	var device := _selected_device()
	if device >= 0:
		held_inputs.clear()
		for button in range(JOY_BUTTON_MAX):
			if Input.is_joy_button_pressed(device, button):
				held_inputs["button:%d" % button] = true
		for axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			if Input.get_joy_axis(device, axis) > TRIGGER_RELEASE:
				held_inputs["trigger:%d" % axis] = true
	elif device == -2:
		held_inputs.clear()
		for button in [1, 2, 3, 8, 9]:
			if Input.is_mouse_button_pressed(button):
				held_inputs["mouse:%d" % button] = true

func _start_run() -> void:
	# Validate before changing screens. Preserve an unsaved completed run on failure.
	if not pending_record.is_empty():
		_set_notice("Select Retry save before starting another benchmark.")
		return
	if name_edit.text.strip_edges().is_empty():
		_set_notice("Enter a benchmark name first.")
		name_edit.grab_focus()
		return
	if get_viewport().gui_get_focus_owner():
		get_viewport().gui_get_focus_owner().release_focus()
	run_name = name_edit.text.strip_edges()
	target = int(count_edit.value)
	run_device = _device_metadata()
	# clear() here empties in-memory arrays only. It never deletes files on disk.
	samples.clear()
	sample_buttons.clear()
	frame_times.clear()
	false_starts = 0
	timeouts = 0
	_snapshot_held()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED)
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	menu.hide()
	# Paint red BEFORE showing the overlay, avoiding a frame of the default color.
	_begin_release()
	overlay.show()

func _paint(color: Color, heading: String, subtitle: String) -> void:
	# Update the cue together so its background, heading, and instructions agree.
	overlay.color = color
	cue.text = heading
	cue_detail.text = subtitle
	cue_progress.text = "Trial %d of %d   /   %s   /   Esc to cancel" % [mini(samples.size() + 1, target), target, run_name.left(45)]

func _begin_release() -> void:
	# Start each attempt on red and wait for all buttons to settle in the released state.
	phase = Phase.RELEASE
	release_since = 0
	_paint(WAIT_RED, "Wait", _release_instruction() + " Wait for the screen to turn green.")

func _process(delta: float) -> void:
	# delta is time since the last frame in seconds. Use the monotonic clock for
	# deadlines; adding frame deltas would unnecessarily tie the stopwatch to FPS.
	var now := Time.get_ticks_usec()
	if menu.visible:
		_refresh_input_indicator(now)
	if phase == Phase.RELEASE:
		if not held_inputs.is_empty():
			release_since = 0
		elif release_since == 0:
			release_since = now
		elif now - release_since >= RELEASE_SETTLE_US:
			phase = Phase.WAIT
			deadline = now + randi_range(WAIT_MIN_US, WAIT_MAX_US)
			# Random delay discourages predicting green from a regular countdown.
			_paint(WAIT_RED, "Wait", "Wait for the screen to turn green.")
	elif phase == Phase.WAIT:
		if now >= deadline:
			phase = Phase.PENDING_GREEN
			_paint(GO_GREEN, "Press", _press_instruction())
	elif phase == Phase.GO:
		frame_times.append(delta * 1000.0)
		if now - green_us >= RESPONSE_TIMEOUT_US:
			timeouts += 1
			_feedback("No response", "No input within 10 seconds. This trial will repeat.", now)
	elif phase == Phase.FEEDBACK and now >= deadline:
		if samples.size() >= target:
			_complete_run()
		else:
			_begin_release()

func _before_draw() -> void:
	# Software timestamp immediately before drawing the green frame, not photon onset.
	# A pending state ensures we don't start the clock merely when scheduling green.
	if phase == Phase.PENDING_GREEN:
		green_us = Time.get_ticks_usec()
		phase = Phase.GO

func _feedback(heading: String, subtitle: String, now: int) -> void:
	# Show feedback briefly without blocking the game loop with a sleep.
	phase = Phase.FEEDBACK
	deadline = now + FEEDBACK_US
	_paint(WAIT_RED, heading, subtitle)

func _restore_menu() -> void:
	# Leave the test's fullscreen mode and restore menu VSync to limit idle GPU work.
	overlay.hide()
	menu.show()
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

func _cancel(message: String) -> void:
	# Cancel affects this unfinished run only. Previously saved JSON stays untouched.
	phase = Phase.IDLE
	input_flash_until = 0
	held_inputs.clear()
	_restore_menu()
	_set_notice(message)

func _focus_lost() -> void:
	# An interrupted run is not comparable. Also clear stale held keys after alt-tab.
	if phase in [Phase.RELEASE, Phase.WAIT, Phase.PENDING_GREEN, Phase.GO, Phase.FEEDBACK]:
		_cancel("You switched away from the app. Benchmark cancelled to keep results comparable.")
	else:
		held_inputs.clear()

func _complete_run() -> void:
	# duplicate() takes a snapshot; clearing samples for a future run must not
	# change the completed record we are about to save.
	phase = Phase.COMPLETE
	pending_record = {
		"schema_version": 2, "name": run_name, "created_at": Time.get_datetime_string_from_system(true) + "Z",
		"samples_ms": samples.duplicate(), "stats": Store.statistics(samples),
		"false_starts": false_starts, "timeouts": timeouts, "device": run_device,
		"input_mode": "any_button", "sample_buttons": sample_buttons.duplicate(), "vsync": vsync_check.button_pressed,
		"fullscreen": fullscreen_check.button_pressed, "refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"engine": Engine.get_version_info().string, "os": OS.get_name(),
		"timing": "Monotonic microseconds: green frame_pre_draw to input callback; not physical display onset",
		"frame_stats": Store.statistics(frame_times), "input_accumulation": false
	}
	_restore_menu()
	_save_pending()

func _save_pending() -> void:
	# Empty error text means success. Keep pending_record on any failure for Retry.
	if pending_record.is_empty():
		return
	if not pending_record.has("run_id"):
		pending_record["run_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
	var saved_id: String = pending_record.run_id
	# The unique ID lets the leaderboard find this run even among duplicate names.
	var error: String = Store.save_run(pending_record, results_folder)
	if not error.is_empty():
		_set_notice(error)
		retry_button.show()
		return
	_set_notice("Result saved · Average: %.1f ms · Trials: %d · Early presses: %d · %s" % [pending_record.stats.mean_ms, pending_record.samples_ms.size(), pending_record.false_starts, pending_record.name])
	pending_record = {}
	retry_button.hide()
	phase = Phase.IDLE
	_refresh_board(saved_id)

func _refresh_board(preferred_run_id: String = "", preferred_filename: String = "") -> void:
	# Reload from disk, then choose the page containing the saved/restored result.
	# Filenames also identify older results that have no run_id field.
	var loaded: Dictionary = Store.load_runs(results_folder)
	records = loaded.records
	board_page = clampi(board_page, 0, maxi(0, ceili(records.size() / float(PAGE_SIZE)) - 1))
	var preferred_index := -1
	if not preferred_run_id.is_empty() or not preferred_filename.is_empty():
		for i in records.size():
			var id_matches: bool = not preferred_run_id.is_empty() and records[i].get("run_id", "") == preferred_run_id
			var filename_matches: bool = records[i]._filename == preferred_filename
			if id_matches or filename_matches:
				preferred_index = i
				board_page = int(i / float(PAGE_SIZE))
				break
	_render_board(preferred_index)
	if loaded.skipped > 0:
		_set_notice(notice.text + " · Unreadable result files skipped: %d. Files are unchanged." % loaded.skipped)

func _render_board(preferred_index: int = -1) -> void:
	# Rebuild only five visible rows. board.clear() removes UI rows, not result files.
	board.clear()
	selected_record = -1
	var root := board.create_item()
	var first := board_page * PAGE_SIZE
	var preferred_item: TreeItem
	for i in range(first, mini(first + PAGE_SIZE, records.size())):
		var item := board.create_item(root)
		var record: Dictionary = records[i]
		item.set_text(0, "%d. %s" % [i + 1, record.name])
		item.set_text(1, "%.1f" % record.stats.mean_ms)
		item.set_text(2, str(record.samples_ms.size()))
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_metadata(0, i)
		# Store the record index on the row so clicking it retrieves the right data.
		item.add_button(3, trash_icon, 0, false, "Move this result to trash. Use Undo trash to restore it.")
		if i == preferred_index:
			preferred_item = item
	board_page_label.text = "No saved results" if records.is_empty() else "Results %d–%d of %d" % [first + 1, mini(first + PAGE_SIZE, records.size()), records.size()]
	previous_button.disabled = board_page == 0
	next_button.disabled = first + PAGE_SIZE >= records.size()
	if root.get_first_child():
		(preferred_item if preferred_item else root.get_first_child()).select(0)
		_show_record()
	else:
		detail.text = "No results yet.\nComplete a benchmark to see your reaction times here."
		_render_trials()

func _change_page(direction: int) -> void:
	# clampi keeps the page index between the first and last available pages.
	board_page = clampi(board_page + direction, 0, maxi(0, ceili(records.size() / float(PAGE_SIZE)) - 1))
	_render_board()

func _show_record() -> void:
	# Selection changes update the summary and reset individual trials to page one.
	var item := board.get_selected()
	if item == null:
		return
	selected_record = int(item.get_metadata(0))
	trial_page = 0
	var record: Dictionary = records[selected_record]
	var stats: Dictionary = record.stats
	var date := str(record.get("created_at", "")).replace("T", " ").left(16)
	date = "Undated" if date.is_empty() else date + " UTC"
	# Build three short lines rather than one hard-to-read formatting expression.
	# %.1f prints one decimal place; %d prints an integer; %s inserts text.
	var summary := "Average %.1f ms · Median %.1f ms · Fastest %.1f ms" % [stats.mean_ms, stats.median_ms, stats.best_ms]
	var spread := "Variation %.1f ms (SD) · Early presses %d · Timeouts %d" % [stats.stddev_ms, int(record.get("false_starts", 0)), int(record.get("timeouts", 0))]
	var sync := "on" if record.get("vsync", false) else "off"
	var mode := "Fullscreen" if record.get("fullscreen", false) else "Windowed"
	var display := "VSync %s · %s · %s · %s" % [sync, mode, _format_refresh_rate(record.get("refresh_hz")), date]
	detail.text = "\n".join([summary, spread, display])
	detail.tooltip_text = "%s\n%s\n%s\nAverage: Arithmetic mean of completed trials.\nMedian: Middle reaction time.\nFastest: Shortest reaction time.\nVariation (SD): Standard deviation; lower means more consistent times." % [str(record.name), str(record.get("device", {}).get("name", "Unknown device")), "Fullscreen" if record.get("fullscreen", false) else "Windowed"]
	_render_trials()

func _format_refresh_rate(value: Variant) -> String:
	# Variant means the value may have different types, especially after parsing JSON.
	if (value is float or value is int) and is_finite(float(value)) and float(value) > 0:
		return "%.1f Hz" % float(value)
	return "Refresh rate unavailable"

func _render_trials() -> void:
	# Show a slice of the sample array; the original array always retains every trial.
	if selected_record < 0:
		trial_values.text = "Individual trial times will appear here."
		trial_page_label.text = "Trials · milliseconds"
		trial_previous.disabled = true
		trial_next.disabled = true
		return
	var values: Array = records[selected_record].samples_ms
	var first := trial_page * TRIAL_PAGE_SIZE
	var texts := PackedStringArray()
	for i in range(first, mini(first + TRIAL_PAGE_SIZE, values.size())):
		texts.append("%.1f" % values[i])
	trial_values.text = "  ·  ".join(texts)
	trial_values.tooltip_text = trial_values.text
	trial_page_label.text = "Trials %d–%d of %d · ms" % [first + 1, mini(first + TRIAL_PAGE_SIZE, values.size()), values.size()]
	trial_previous.disabled = trial_page == 0
	trial_next.disabled = first + TRIAL_PAGE_SIZE >= values.size()

func _change_trial_page(direction: int) -> void:
	# Ceiling division counts a partially filled final page too.
	if selected_record < 0:
		return
	trial_page = clampi(trial_page + direction, 0, ceili(records[selected_record].samples_ms.size() / float(TRIAL_PAGE_SIZE)) - 1)
	_render_trials()

func _trash_clicked(item: TreeItem, column: int, _id: int, mouse_button: int) -> void:
	# Only the trash-column action moves a file. Ordinary row selection never does.
	if column != 3 or mouse_button != MOUSE_BUTTON_LEFT:
		return
	var record: Dictionary = records[int(item.get_metadata(0))]
	var filename: String = record._filename
	var error: String = Store.trash_run(filename, results_folder)
	if not error.is_empty():
		_set_notice(error)
		return
	last_trashed = filename
	undo_button.disabled = false
	_set_notice("Result moved to trash. Use Undo trash to restore it.")
	_refresh_board()

func _undo_trash() -> void:
	# Restore the last trashed file and select it. The store refuses name collisions.
	if last_trashed.is_empty():
		return
	var error: String = Store.restore_run(last_trashed, results_folder)
	if not error.is_empty():
		_set_notice(error)
		return
	var restored_filename := last_trashed
	last_trashed = ""
	undo_button.disabled = true
	_set_notice("Result restored.")
	_refresh_board("", restored_filename)


func _release_instruction() -> String:
	# Match instructions to the selected device; this does not alter input handling.
	return "Release all keys." if _selected_device() == -1 else "Release all buttons."

func _press_instruction() -> String:
	if _selected_device() == -1:
		return "Press any key except Esc."
	if _selected_device() == -2:
		return "Click any mouse button."
	return "Press any button on your controller."

func _make_led(active: bool) -> ImageTexture:
	# Draw a local vector circle. Both textures share dimensions, so nothing shifts.
	var fill := "#60e2b5" if active else "#263647"
	var rim := "#a3f5d8" if active else "#708196"
	var glow := '<circle cx="10" cy="10" r="10" fill="#60e2b5" opacity="0.18"/>' if active else ""
	var picture := Image.new()
	picture.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20">%s<circle cx="10" cy="10" r="6.5" fill="%s" stroke="%s" stroke-width="1.5"/><circle cx="8" cy="8" r="2" fill="#ffffff" opacity="0.25"/></svg>' % [glow, fill, rim])
	return ImageTexture.create_from_image(picture)

func _refresh_input_indicator(now: int) -> void:
	# Keep a quick tap visible for 180 ms; a held input stays lit until released.
	# Reuse benchmark filtering, so another controller or stick drift cannot light it.
	var active := not held_inputs.is_empty() or now < input_flash_until
	if active == input_check_active:
		return
	input_check_active = active
	input_led.texture = led_on if active else led_off
	input_check_label.text = "Input detected" if active else "Press a button to check this device"
	input_check_label.add_theme_color_override("font_color", ACCENT if active else MUTED)


func _age_reference_card() -> PanelContainer:
	# Published GROUP MEANS for the computer-based SIMPLE visual task (DLS),
	# not the four-choice task, not per-age predictions, and not controller latency.
	# Source: Deary, Liewald & Nissan (2011), Table 1. n=50 per group. https://doi.org/10.3758/s13428-010-0024-1
	# Keep the study's actual age bands: there are no data here for ages 26–44.
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 405
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color("101c2a")
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", box)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	card.add_child(content)
	content.add_child(_label("Average visual reaction time by age", 14, ACCENT))
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 12)
	content.add_child(groups)
	var references := [
		{"age": "18–25 years", "mean_ms": 243.1},
		{"age": "45–60 years", "mean_ms": 283.9},
		{"age": "61–80 years", "mean_ms": 296.1}
	]
	for reference in references:
		var group := VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_theme_constant_override("separation", 0)
		groups.add_child(group)
		group.add_child(_label(reference.age, 12, MUTED))
		group.add_child(_label("%.1f ms" % reference.mean_ms, 21))
	return card
