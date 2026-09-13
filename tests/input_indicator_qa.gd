extends SceneTree
# Isolated checks for the device LED. No benchmarks are saved by this test.
var failures := 0
var passed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", title)
	else:
		failures += 1
		push_error(title)

func button(down: bool, device: int = 77, index: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = down
	return event

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	app.results_folder = "user://test_artifacts/led-" + Crypto.new().generate_random_bytes(6).hex_encode()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.device_picker.add_item("Synthetic test controller")
	app.device_picker.set_item_metadata(app.device_picker.item_count - 1, 77)
	app.device_picker.select(app.device_picker.item_count - 1)
	check(not app.input_check_active, "Indicator starts off")
	app._input(button(true, 78))
	check(not app.input_check_active, "Other controller does not light the LED")
	app._input(button(true))
	check(app.input_check_active and app.input_check_label.text == "Input detected", "Selected controller lights LED and shows input detected")
	app._refresh_input_indicator(Time.get_ticks_usec() + 1000000)
	check(app.input_check_active, "Held input stays lit after the minimum flash")
	app._input(button(true, 77, 1))
	app._input(button(false))
	app._refresh_input_indicator(Time.get_ticks_usec() + 1000000)
	check(app.input_check_active, "Releasing one of two held buttons keeps LED lit")
	app._input(button(false, 77, 1))
	app._refresh_input_indicator(Time.get_ticks_usec() + 1000000)
	check(not app.input_check_active, "LED turns off when all buttons are released")
	app._input(button(true))
	app._input(button(false))
	check(app.input_check_active, "A quick tap remains visible briefly")
	app.input_flash_until = 0
	app._refresh_input_indicator(Time.get_ticks_usec())
	var motion := InputEventJoypadMotion.new()
	motion.device = 77
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.9
	app._input(motion)
	check(not app.input_check_active, "Stick movement does not light the button indicator")
	motion.axis = JOY_AXIS_TRIGGER_LEFT
	app._input(motion)
	check(app.input_check_active, "Trigger press lights the LED")
	check(app.samples.is_empty() and app.phase == app.Phase.IDLE, "Checking buttons never starts or scores a benchmark")
	app.device_picker.select(0)
	app.device_picker.item_selected.emit(0)
	check(not app.input_check_active, "Changing devices resets the LED")
	check(not app.device_info.text.to_lower().contains("polling"), "Polling-rate text is removed")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.keycode = KEY_SPACE
	key.pressed = true
	app._input(key)
	check(app.input_check_active, "Keyboard mode lights the LED for a key press")
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://tests/input-led-" + str(Time.get_unix_time_from_system()).replace(".", "_") + ".png"
	root.get_texture().get_image().save_png(path)
	print("PREVIEW: ", ProjectSettings.globalize_path(path))
	print("LED RESULT: %d passed, %d failures" % [passed, failures])
	quit(1 if failures else 0)
