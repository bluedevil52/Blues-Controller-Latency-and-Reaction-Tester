extends SceneTree

## Storage QA
##
## These checks use one fresh user:// folder per run.  The fixtures are kept on
## disk so a failed check can be inspected later; this script never removes
## files and never touches the real application data folder.
const Store = preload("res://benchmark_store.gd")

var passed := 0
var failures := 0

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", description)
	else:
		failures += 1
		push_error(description)

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Fixture file can be created: %s" % path.get_file())
	if file != null:
		file.store_string(text)
		file.close()

func make_record(name: String, value: float) -> String:
	return JSON.stringify({"name": name, "samples_ms": [value, value + 10.0]})

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# A random folder prevents this QA from colliding with another test run.
	var token := Crypto.new().generate_random_bytes(8).hex_encode()
	var fixture := "user://test_artifacts/storage-" + token
	var legacy := fixture.path_join("legacy-results")
	var destination := fixture.path_join("new-data")
	# migrate_results receives the old results directory itself (the old app
	# stored JSON files directly there), so its optional trash folder is one
	# level below legacy.
	var legacy_results := legacy
	var legacy_trash := legacy.path_join("trash")
	DirAccess.make_dir_recursive_absolute(legacy_trash)
	var original_result := "run_original.json"
	var secondary_result := "run_secondary.json"
	var original_trash := "run_old_trash.json"
	write_text(legacy_results.path_join(original_result), make_record("Legacy result", 210.0))
	write_text(legacy_results.path_join(secondary_result), make_record("Second legacy result", 220.0))
	write_text(legacy_trash.path_join(original_trash), make_record("Legacy trashed result", 310.0))
	write_text(legacy_results.path_join("ignore.txt"), "not a result")

	# Migration copies both active and trashed JSON files and leaves originals.
	check(Store.migrate_results(destination, legacy).is_empty(), "Legacy results migrate successfully")
	var copied_result := destination.path_join("results").path_join(original_result)
	var copied_trash := destination.path_join("results").path_join("trash").path_join(original_trash)
	check(FileAccess.file_exists(copied_result) and FileAccess.file_exists(copied_trash), "Active and trashed results are copied")
	check(FileAccess.file_exists(legacy_results.path_join(original_result)) and FileAccess.file_exists(legacy_trash.path_join(original_trash)), "Legacy originals are preserved")
	check(not FileAccess.file_exists(destination.path_join("results").path_join("ignore.txt")), "Non-JSON legacy files are skipped")

	# Use a fresh destination with a preexisting file so the collision branch is
	# exercised during the first migration, before the marker can short-circuit.
	var collision_destination := fixture.path_join("collision-data")
	var collision_folder := collision_destination.path_join("results")
	var collision_text := "destination survives collision"
	DirAccess.make_dir_recursive_absolute(collision_folder)
	write_text(collision_folder.path_join(original_result), collision_text)
	check(Store.migrate_results(collision_destination, legacy).is_empty(), "Fresh migration tolerates an existing result")
	var collision_file := FileAccess.open(collision_folder.path_join(original_result), FileAccess.READ)
	var collision_read := collision_file.get_as_text() if collision_file != null else ""
	if collision_file != null:
		collision_file.close()
	check(collision_read == collision_text, "Migration never overwrites an existing result")
	check(FileAccess.file_exists(collision_folder.path_join(secondary_result)) and FileAccess.file_exists(collision_destination.path_join("results").path_join("trash").path_join(original_trash)), "Collision migration copies other legacy files")

	# The original destination is already marked complete, so repeating it must
	# be a no-op as well.
	check(Store.migrate_results(destination, legacy).is_empty(), "Completed migration is idempotent")
	check(FileAccess.file_exists(destination.path_join("legacy_migration_complete")), "Migration marker is written")

	# Give the real scene isolated paths so settings QA cannot alter preferences.
	var settings_path := fixture.path_join("settings.cfg")
	var results_path := fixture.path_join("app-results")
	var app: Control = load("res://main.tscn").instantiate()
	app.results_folder = results_path
	app.settings_path = settings_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.count_edit.value = 37
	app.fullscreen_check.button_pressed = false
	app.vsync_check.button_pressed = true
	app._save_settings()
	check(FileAccess.file_exists(settings_path), "Settings save creates the supplied settings file")
	var reopened: Control = load("res://main.tscn").instantiate()
	reopened.results_folder = results_path
	reopened.settings_path = settings_path
	root.add_child(reopened)
	await process_frame
	reopened.set_process(false)
	check(int(reopened.count_edit.value) == 37, "Saved trial count reloads")
	check(not reopened.fullscreen_check.button_pressed, "Saved windowed setting reloads")
	check(reopened.vsync_check.button_pressed, "Saved VSync setting reloads")
	check(not settings_path.begins_with("user://") or settings_path.contains("storage-"), "Settings QA uses an isolated fixture path")

	print("RESULT: %d passed; %d failures. Fixtures retained at %s" % [passed, failures, ProjectSettings.globalize_path(fixture)])
	quit(1 if failures else 0)
