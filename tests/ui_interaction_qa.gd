extends SceneTree
# Run in the real renderer: these events go through Godot's GUI and input routing.
# All results are synthetic and isolated from the user's benchmark folder.
const Store = preload("res://benchmark_store.gd")
var app: Control
var output_dir := ""
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func move_to(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)

func click(control: Control) -> void:
	move_to(control)
	await click_position(control.get_global_rect().get_center())

func click_position(position: Vector2) -> void:
	# Tree buttons also consult the current pointer position, not only the event.
	root.warp_mouse(position)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)
		await process_frame

func shot(name: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(name + ".png"))

func inspect_layout(node: Node) -> bool:
	var fits := true
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button or node is Tree):
		var rect: Rect2 = node.get_global_rect()
		var limit: Vector2 = app.get_viewport_rect().size
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > limit.x - 12 or rect.end.y > limit.y - 12:
			print("OVERFLOW: ", node.name, " ", rect)
			fits = false
	for child in node.get_children():
		fits = inspect_layout(child) and fits
	return fits

func run() -> void:
	output_dir = "res://tests/ui-pass-" + str(Time.get_unix_time_from_system()).replace(".", "_")
	DirAccess.make_dir_recursive_absolute(output_dir)
	app = load("res://main.tscn").instantiate()
	app.results_folder = "user://test_artifacts/ui-" + Crypto.new().generate_random_bytes(6).hex_encode()
	root.add_child(app)
	root.notify_mouse_entered()
	await shot("01-normal")
	for control in [app.fullscreen_check, app.vsync_check]:
		var base: StyleBox = control.get_theme_stylebox("normal")
		for state in ["hover", "pressed", "hover_pressed", "disabled"]:
			var other: StyleBox = control.get_theme_stylebox(state)
			check(base.get_content_margin(SIDE_LEFT) == other.get_content_margin(SIDE_LEFT) and base.get_content_margin(SIDE_TOP) == other.get_content_margin(SIDE_TOP), "%s has stable %s padding" % [control.text, state])
	move_to(app.fullscreen_check)
	await shot("02-checked-hover")
	check(app.fullscreen_check.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED, "Real checked-hover state exercised")
	await click(app.fullscreen_check)
	await shot("03-unchecked-hover")
	check(not app.fullscreen_check.button_pressed and app.fullscreen_check.get_draw_mode() == BaseButton.DRAW_HOVER, "Checkbox toggles without leaving hover")
	move_to(app.vsync_check)
	await shot("04-vsync-hover")
	await click(app.vsync_check)
	check(app.vsync_check.button_pressed, "VSync toggles through GUI events")
	app.vsync_check.button_pressed = false
	app.start_button.grab_focus()
	await shot("05-keyboard-focus")
	check(root.gui_get_focus_owner() == app.start_button, "Primary button can receive keyboard focus")
	await click(app.start_button)
	check(app.phase == app.Phase.IDLE and root.gui_get_focus_owner() == app.name_edit, "Empty name prevents start and focuses name field")
	app.device_picker.select(0)
	app.device_picker.item_selected.emit(0)
	app.name_edit.text = "UI integration run"
	app.count_edit.value = 1
	await click(app.start_button)
	check(app.phase == app.Phase.RELEASE and app.overlay.color == app.WAIT_RED, "Clicking Start opens directly on red")
	await shot("06-starts-red")
	var stop_at := Time.get_ticks_msec() + 8000
	var stayed_red := true
	while app.phase in [app.Phase.RELEASE, app.Phase.WAIT] and Time.get_ticks_msec() < stop_at:
		stayed_red = stayed_red and app.overlay.color == app.WAIT_RED
		await process_frame
	check(stayed_red, "Release and random wait stay red on every observed frame")
	check(app.phase == app.Phase.GO, "Real render callback arms green cue")
	if app.phase == app.Phase.GO:
		await create_timer(0.12).timeout
		var press := InputEventKey.new()
		press.keycode = KEY_SPACE
		press.physical_keycode = KEY_SPACE
		press.pressed = true
		root.push_input(press, true)
		press = press.duplicate()
		press.pressed = false
		root.push_input(press, true)
		check(app.samples.size() == 1 and app.samples[0] >= 100, "Reaction scores through viewport input routing")
		check(app.overlay.color == app.WAIT_RED, "Feedback returns to red, not blue")
		await shot("07-reaction-feedback")
		await create_timer(1.2).timeout
		check(app.records.size() == 1 and app.phase == app.Phase.IDLE, "One-trial run saves automatically through the complete loop")
	else:
		app._cancel("QA transition failed")
	for i in range(7):
		var values: Array = []
		for j in range(200 if i == 0 else 10):
			values.append(250.0 + j + i)
		Store.save_run({"name": "Long controller name " + "example ".repeat(12) if i == 0 else "Comparison %d" % i, "samples_ms": values}, app.results_folder)
	app._refresh_board()
	await shot("08-populated")
	check(inspect_layout(app.menu), "Populated layout fits the default window")
	await click(app.next_button)
	check(app.board_page == 1, "Next page works through mouse events")
	await shot("08a-second-page")
	var row: TreeItem = app.board.get_root().get_first_child()
	var filename: String = app.records[int(row.get_metadata(0))]._filename
	var trash_rect: Rect2 = app.board.get_item_area_rect(row, 3, 0)
	await click_position(app.board.global_position + trash_rect.get_center())
	await process_frame
	check(app.records.size() == 7 and app.last_trashed == filename and FileAccess.file_exists(app.results_folder.path_join("trash").path_join(filename)), "Clicking the trash icon removes exactly one fixture row")
	await shot("08b-trashed")
	await click(app.undo_button)
	check(app.records.size() == 8 and app.records[app.selected_record]._filename == filename, "Undo restores and selects the clicked result")
	await shot("08c-restored")
	await click(app.previous_button)
	check(app.board_page == 0, "Previous page works through mouse events")
	app.retry_button.show()
	root.size = Vector2i(880, 624)
	await shot("09-compact-retry")
	check(inspect_layout(app.menu), "Minimum window fits populated results and save retry")
	root.size = Vector2i(1100, 780)
	app.retry_button.hide()
	app.fullscreen_check.button_pressed = true
	await click(app.start_button)
	await shot("10-fullscreen-red")
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and app.overlay.color == app.WAIT_RED, "Fullscreen benchmark opens on red")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	check(app.phase == app.Phase.IDLE and not app.overlay.visible, "Escape exits fullscreen trial and restores menu")
	print("UI RESULT: %d checks, %d failures. CAPTURES: %s" % [checks, failures, ProjectSettings.globalize_path(output_dir)])
	quit(1 if failures else 0)
