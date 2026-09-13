extends SceneTree
# Headless regression tests: each check names a behavior, not a UI implementation.
# Run with --script res://tests/test_runner.gd. Exit code 1 means a failed check.
# All fixture files stay in test_artifacts; no real benchmark history is modified.
const Store = preload("res://benchmark_store.gd")
var failures := 0
var passed := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
	else:
		passed += 1
		print("PASS: ", description)

func _initialize() -> void:
	call_deferred("run")

func key(pressed: bool, code: int = KEY_SPACE) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func joy(pressed: bool, button: int, device: int = 77) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	return event

func axis(value: float, axis_id: int = JOY_AXIS_TRIGGER_LEFT) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 77
	event.axis = axis_id
	event.axis_value = value
	return event

func mouse(pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event

func green(app: Control) -> void:
	app.phase = app.Phase.PENDING_GREEN
	app._before_draw()
	app.green_us = Time.get_ticks_usec() - 250000

func run() -> void:
	var stats: Dictionary = Store.statistics([100.0, 200.0, 300.0, 400.0])
	check(stats.mean_ms == 250.0 and stats.median_ms == 250.0, "Even mean and median")
	check(Store.statistics([300.0, 100.0, 200.0]).median_ms == 200.0, "Odd median sorts samples")
	check(Store.statistics([]).is_empty(), "Empty sample handling")
	check(is_equal_approx(Store.statistics([100.0]).stddev_ms, 0.0), "Single trial standard deviation")
	var folder := "user://test_artifacts/" + Crypto.new().generate_random_bytes(8).hex_encode()
	var record := {"name": "Regression test", "samples_ms": [200.0, 300.0]}
	check(Store.save_run(record, folder).is_empty(), "Save completed run")
	check(Store.save_run(record, folder).is_empty(), "Same-name run saved independently")
	var malformed := FileAccess.open(folder.path_join("malformed.json"), FileAccess.WRITE)
	malformed.store_string("{broken")
	malformed.close()
	var loaded: Dictionary = Store.load_runs(folder)
	check(loaded.records.size() == 2 and loaded.skipped == 1, "Reload preserves duplicate names and skips malformed data")
	check(loaded.records[0].stats.mean_ms == 250.0, "Statistics reconstructed from saved samples")
	var filename: String = loaded.records[0]._filename
	check(not Store.trash_run("../outside.json", folder).is_empty(), "Trash rejects path traversal")
	check(not Store.trash_run("C:\\outside.json", folder).is_empty(), "Trash rejects absolute Windows paths")
	check(Store.trash_run(filename, folder).is_empty(), "Trash moves only the selected test result")
	check(Store.load_runs(folder).records.size() == 1 and FileAccess.file_exists(folder.path_join("trash").path_join(filename)), "Trashed result leaves leaderboard but file is preserved")
	check(Store.restore_run(filename, folder).is_empty() and Store.load_runs(folder).records.size() == 2, "Undo restores original result")
	# A conflicting destination must never overwrite data.
	DirAccess.make_dir_recursive_absolute(folder.path_join("trash"))
	var conflict := FileAccess.open(folder.path_join("trash").path_join(filename), FileAccess.WRITE)
	conflict.store_string("preserved collision")
	conflict.close()
	check(not Store.trash_run(filename, folder).is_empty() and FileAccess.file_exists(folder.path_join(filename)), "Trash collision preserves both files")
	var app = load("res://main.tscn").instantiate()
	app.results_folder = folder.path_join("app_results")
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.device_picker.select(0)
	app.name_edit.text = "State machine test"
	app.fullscreen_check.button_pressed = false
	# Simulate buttons already held BEFORE starting, then release them one at a time.
	app._input(key(true, KEY_A))
	app._input(key(true, KEY_B))
	app._start_run()
	check(app.phase == app.Phase.RELEASE, "Run starts without binding")
	check(app.overlay.color == app.WAIT_RED, "Initial release screen is already red")
	app.release_since = 1
	app._input(key(false, KEY_A))
	app._process(0.001)
	check(app.release_since == 0 and app.held_inputs.size() == 1, "Release gate waits for every held button")
	app._input(key(false, KEY_B))
	app._input(key(true, KEY_C))
	check(app.false_starts == 1 and app.cue.text == "Don't cheat!", "New press during initial red is also an early press")
	app._input(key(false, KEY_C))
	app.phase = app.Phase.WAIT
	app._input(mouse(true))
	check(app.phase == app.Phase.WAIT, "Mouse ignored in keyboard mode")
	app._input(key(true, KEY_A))
	check(app.false_starts == 2 and app.samples.is_empty() and app.cue.text == "Don't cheat!", "Early press shows Don't cheat and excludes the trial")
	app._input(key(false, KEY_A))
	green(app)
	app._input(key(true, KEY_B))
	check(app.samples.size() == 1 and abs(app.samples[0] - 250.0) < 20.0, "Any different key can score with input-callback timing")
	app._input(key(true, KEY_B))
	check(app.samples.size() == 1, "Repeated press cannot double score")
	app._input(key(false, KEY_B))
	app.phase = app.Phase.WAIT
	var echo := key(true)
	echo.echo = true
	app._input(echo)
	check(app.phase == app.Phase.WAIT, "Keyboard auto-repeat ignored")
	app.phase = app.Phase.GO
	app.green_us = Time.get_ticks_usec() - 11000000
	app._process(0.001)
	check(app.timeouts == 1 and app.samples.size() == 1, "Timeout excluded from scored trials")
	app.phase = app.Phase.GO
	app.green_us = Time.get_ticks_usec() - 11000000
	app._input(key(true, KEY_D))
	check(app.timeouts == 2 and app.samples.size() == 1, "Late input is rejected even before the next frame timeout check")
	app._input(key(false, KEY_D))
	var logical_key := key(true, KEY_E)
	logical_key.physical_keycode = 0
	check(app._event_button(logical_key).id == "key:%d" % KEY_E, "Logical key fallback supports inputs without physical keycodes")
	app.device_picker.add_item("Synthetic controller")
	app.device_picker.set_item_metadata(app.device_picker.item_count - 1, 77)
	app.device_picker.select(app.device_picker.item_count - 1)
	app.held_inputs.clear()
	app.phase = app.Phase.WAIT
	app._input(joy(true, 0, 78))
	app._input(key(true))
	check(app.phase == app.Phase.WAIT and app.held_inputs.is_empty(), "Other controllers and keyboard cannot score selected controller run")
	app._input(axis(0.9, JOY_AXIS_LEFT_X))
	app._input(axis(0.1))
	check(app.phase == app.Phase.WAIT, "Stick motion and trigger noise do not cause false starts")
	for button in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_DPAD_UP, JOY_BUTTON_START]:
		green(app)
		var before: int = app.samples.size()
		app._input(joy(true, button))
		check(app.samples.size() == before + 1, "Unbound controller button %d scores" % button)
		app._input(joy(false, button))
	green(app)
	var before_trigger: int = app.samples.size()
	app._input(axis(0.7))
	check(app.samples.size() == before_trigger + 1, "Trigger crossing threshold scores")
	app.phase = app.Phase.WAIT
	app._input(axis(0.4))
	app._input(axis(0.6))
	check(app.phase == app.Phase.WAIT and app.held_inputs.size() == 1, "Trigger hysteresis prevents repeated presses")
	app._input(axis(0.1))
	check(app.held_inputs.is_empty(), "Trigger releases below lower threshold")
	app._input(axis(0.7))
	check(app.cue.text == "Don't cheat!", "Early trigger press shows Don't cheat")
	app._input(axis(0.0))
	app.device_picker.select(1)
	green(app)
	var before_mouse: int = app.samples.size()
	app._input(mouse(true, MOUSE_BUTTON_WHEEL_UP))
	check(app.phase == app.Phase.GO, "Wheel motion is ignored")
	app._input(mouse(true, MOUSE_BUTTON_RIGHT))
	check(app.samples.size() == before_mouse + 1, "Any physical mouse button scores in mouse mode")
	app._input(mouse(false, MOUSE_BUTTON_RIGHT))
	app.phase = app.Phase.WAIT
	app._focus_lost()
	check(app.phase == app.Phase.IDLE and not app.overlay.visible, "Focus loss cancels run")
	app.device_picker.select(app.device_picker.item_count - 1)
	app.phase = app.Phase.WAIT
	app._device_changed(78, false)
	check(app.phase == app.Phase.WAIT, "Unrelated controller disconnection does not cancel run")
	app._device_changed(77, false)
	check(app.phase == app.Phase.IDLE, "Selected controller disconnection cancels run")
	app.device_picker.select(0)
	app.samples = [210.0, 230.0]
	app.run_name = "Completed benchmark"
	app._complete_run()
	check(app.pending_record.is_empty() and app.records.size() == 1, "Completed run saves and populates leaderboard")
	var reopened = load("res://main.tscn").instantiate()
	reopened.results_folder = app.results_folder
	root.add_child(reopened)
	check(reopened.records.size() == 1 and reopened.records[0].stats.mean_ms == 220.0, "Reopened app reloads completed benchmark")
	var item: TreeItem = app.board.get_root().get_first_child()
	app._trash_clicked(item, 3, 0, MOUSE_BUTTON_LEFT)
	check(app.records.is_empty() and not app.undo_button.disabled, "Trash icon removes chosen row and enables Undo")
	app._undo_trash()
	check(app.records.size() == 1 and app.undo_button.disabled, "UI Undo restores trashed row")
	for i in range(7):
		Store.save_run({"name": "Page test %d" % i, "samples_ms": [300.0 + i]}, app.results_folder)
	app._refresh_board()
	check(app.board.get_root().get_child_count() == 5 and not app.next_button.disabled, "Leaderboard paginates after five rows")
	app._change_page(1)
	check(app.board.get_root().get_child_count() == 3 and app.next_button.disabled, "Last leaderboard page shows remaining results")
	check(not app.board.scroll_vertical_enabled and not app.board.scroll_horizontal_enabled, "Leaderboard scrolling disabled")
	var many: Array = []
	for i in range(200):
		many.append(100.0 + i)
	Store.save_run({"name": "200 trials", "samples_ms": many}, app.results_folder)
	app.board_page = 0
	app._refresh_board()
	app._change_trial_page(19)
	check(app.trial_page == 19 and app.trial_next.disabled and app.trial_page_label.text.contains("191–200"), "All 200 trial times accessible through pages")
	app.samples = [900.0, 1000.0]
	app.run_name = "Newest slow run"
	app._complete_run()
	check(app.board_page == 1 and app.records[app.selected_record].name == "Newest slow run", "Newest saved run is selected even on a later leaderboard page")
	check(app._format_refresh_rate(239.7599945) == "239.8 Hz" and app._format_refresh_rate(-1) == "Refresh rate unavailable", "Refresh display rounds real values and handles unavailable data")
	var edited_folder := folder.path_join("edited_metadata")
	Store.save_run({"name": "Edited metadata", "samples_ms": [200.0], "device": "wrong type", "false_starts": [], "timeouts": {}, "vsync": "false", "created_at": null}, edited_folder)
	var edited: Dictionary = Store.load_runs(edited_folder)
	check(edited.records.size() == 1 and edited.records[0].device is Dictionary and edited.records[0].false_starts == 0 and edited.records[0].vsync == false, "Malformed optional metadata is normalized without losing valid scores")
	app.results_folder = edited_folder
	app._refresh_board()
	check(app.detail.text.contains("Undated"), "Edited metadata renders safely in the details panel")
	app.results_folder = folder.path_join("malformed.json")
	app.pending_record = record
	app._save_pending()
	check(not app.pending_record.is_empty() and app.retry_button.visible, "Save failure retains run for retry")
	print("RESULT: %d passed; %d failures. Test files retained at %s" % [passed, failures, ProjectSettings.globalize_path(folder)])
	quit(1 if failures else 0)
