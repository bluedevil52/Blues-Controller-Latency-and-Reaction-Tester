extends SceneTree
const Store = preload("res://benchmark_store.gd")
var capture_dir := ""

func _initialize() -> void:
	call_deferred("capture")

func shot(filename: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join(filename))
	var app := root.get_child(root.get_child_count() - 1)
	if app.menu.visible:
		check_bounds(app.menu, app.get_viewport_rect().size, filename)

func check_bounds(node: Node, viewport: Vector2, context: String) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button or node is Tree):
		var rect: Rect2 = node.get_global_rect()
		if rect.end.y > viewport.y - 12 or rect.end.x > viewport.x - 12:
			push_error("UI bounds overflow in %s: %s at %s" % [context, node.name, rect])
	for child in node.get_children():
		check_bounds(child, viewport, context)

func capture() -> void:
	capture_dir = "res://tests/review-" + str(Time.get_unix_time_from_system()).replace(".", "_")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var app = load("res://main.tscn").instantiate()
	app.results_folder = "user://test_artifacts/visual-" + Crypto.new().generate_random_bytes(6).hex_encode()
	root.add_child(app)
	await shot("empty.png")
	for i in range(8):
		var values: Array = []
		for trial in range(200 if i == 0 else 10):
			values.append(200.0 + i * 12 + (trial % 7) * 4.3)
		Store.save_run({"name": "Xbox wired · session %d" % (i + 1) if i != 0 else "A very long controller name to verify truncation without pushing the trash icon out of view " + "X".repeat(15), "samples_ms": values, "created_at": "2026-09-12T21:00:00Z", "device": {"name": "Xbox Controller"}, "vsync": false, "fullscreen": true, "refresh_hz": 144}, app.results_folder)
	app._refresh_board()
	await shot("populated.png")
	app.retry_button.show()
	await shot("save-error-layout.png")
	app.retry_button.hide()
	app._change_trial_page(19)
	await shot("last-trials.png")
	root.size = Vector2i(880, 624)
	await shot("compact.png")
	root.size = Vector2i(1100, 780)
	app.run_name = "Xbox wired / session 1"
	app.target = 10
	app.menu.hide()
	app.overlay.show()
	app._feedback("Don't cheat!", "Too early. Wait for green — this trial will retry.", Time.get_ticks_usec())
	app.set_process(false)
	await shot("early.png")
	app._paint(Color("087f50"), "PRESS", "Press any button on your selected device.")
	await shot("green.png")
	print("CAPTURES: ", ProjectSettings.globalize_path(capture_dir))
	quit()
