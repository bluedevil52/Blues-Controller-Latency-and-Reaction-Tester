extends RefCounted

static func data_folder() -> String:
	# LOCALAPPDATA expands to the current Windows user's Local folder, without
	# embedding a username or depending on where the executable was downloaded.
	var local := OS.get_environment("LOCALAPPDATA")
	if local.is_empty():
		local = OS.get_data_dir()
	return local.path_join("LatencyTester")

static func migrate_results(base: String, legacy: String) -> String:
	# Copy once, never move/delete the old data. The marker prevents an old result
	# from reappearing after you later trash its migrated copy in the new folder.
	var marker := base.path_join("legacy_migration_complete")
	if FileAccess.file_exists(marker):
		return ""
	if DirAccess.make_dir_recursive_absolute(base.path_join("results")) != OK:
		return "Could not create the new results folder. Original results are unchanged."
	for subfolder in ["", "trash"]:
		var source := legacy.path_join(subfolder)
		if not DirAccess.dir_exists_absolute(source):
			continue
		var directory := DirAccess.open(source)
		if directory == null:
			return "Could not read old results. Migration will retry next launch."
		var destination := base.path_join("results").path_join(subfolder)
		if DirAccess.make_dir_recursive_absolute(destination) != OK:
			return "Could not copy old results. Migration will retry next launch."
		for filename in directory.get_files():
			if filename.get_extension().to_lower() != "json":
				continue
			var target := destination.path_join(filename)
			# Never replace a result already present at the destination.
			if FileAccess.file_exists(target):
				continue
			if DirAccess.copy_absolute(source.path_join(filename), target) != OK:
				return "Could not copy old results. Originals are safe; migration will retry next launch."
	var completed := FileAccess.open(marker, FileAccess.WRITE)
	if completed == null:
		return "Results copied, but migration could not be marked complete."
	completed.store_string("Legacy results copied; original files retained.\n")
	return ""
## STORAGE AND MATH — independent of the user interface.
## RefCounted objects are freed automatically when no references remain.
## These functions are static: callers use Store.statistics(...) without creating
## a Store object. res:// means project files; user:// means writable app data.
## One JSON file per completed run; existing files are never overwritten.

static func statistics(values: Array) -> Dictionary:
	# Sorting a copy preserves the original trial order for the details view.
	if values.is_empty():
		return {}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in ordered:
		total += float(value)
	var mean := total / ordered.size()
	# Variance measures the squared distance from the mean. Its square root is SD.
	# We use population SD (divide by n) to describe this particular run's spread.
	var variance := 0.0
	for value in ordered:
		variance += pow(float(value) - mean, 2)
	var middle := ordered.size() / 2
	var median := float(ordered[int(middle)])
	if ordered.size() % 2 == 0:
		# An even-sized list has two middle values, so average those for the median.
		median = (float(ordered[int(middle) - 1]) + median) / 2.0
	return {"mean_ms": mean, "median_ms": median, "best_ms": ordered[0], "worst_ms": ordered[-1], "stddev_ms": sqrt(variance / ordered.size())}

static func save_run(record: Dictionary, folder: String = "") -> String:
	if folder.is_empty():
		folder = data_folder().path_join("results")
	# The returned String is an error message, or "" for success. No exception needed.
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK:
		return "Could not create the results folder (error %s). Select Retry save." % error
	var path := folder.path_join("run_%s_%s.json" % [str(Time.get_unix_time_from_system()).replace(".", "_"), Crypto.new().generate_random_bytes(8).hex_encode()])
	# A time plus random suffix allows identical test names without overwriting runs.
	if FileAccess.file_exists(path):
		return "Result filename already exists; nothing was overwritten."
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save this result (error %s). Select Retry save." % FileAccess.get_open_error()
	file.store_string(JSON.stringify(record, "\t"))
	# JSON is human-readable text. Flush and inspect errors before claiming success.
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Could not save this result (error %s). Keep the app open and select Retry save." % write_error
	return ""

static func load_runs(folder: String = "") -> Dictionary:
	if folder.is_empty():
		folder = data_folder().path_join("results")
	# Scan only this directory, not its trash subdirectory. A bad file should never
	# prevent good results from loading; count and skip it without altering the file.
	var records: Array = []
	var skipped := 0
	if not DirAccess.dir_exists_absolute(folder):
		return {"records": records, "skipped": skipped}
	for filename in DirAccess.get_files_at(folder):
		if not filename.ends_with(".json"):
			continue
		var file := FileAccess.open(folder.path_join(filename), FileAccess.READ)
		if file == null:
			skipped += 1
			continue
		var parser := JSON.new()
		# A JSON parser reports invalid text without executing anything from the file.
		var json_text := file.get_as_text()
		file.close()
		if parser.parse(json_text) != OK:
			skipped += 1
			continue
		var record = parser.data
		# Essential fields must be valid before the UI can safely display this record.
		if not record is Dictionary or not record.get("samples_ms") is Array or not record.get("name") is String:
			skipped += 1
			continue
		var valid: bool = not record.samples_ms.is_empty()
		for sample in record.samples_ms:
			if not (sample is float or sample is int) or not is_finite(float(sample)) or float(sample) < 0:
				valid = false
		if not valid:
			skipped += 1
			continue
		record["stats"] = statistics(record.samples_ms)
		# Recompute summaries instead of trusting cached numbers from a hand-edited file.
		# A finite input can still overflow when squared or summed. Preserve such
		# files on disk, but do not display invalid statistics in the leaderboard.
		for value in record.stats.values():
			if not is_finite(float(value)):
				valid = false
		if not valid:
			skipped += 1
			continue
		_normalize_metadata(record)
		# Always derive the filename from directory enumeration, never from JSON data.
		record["_filename"] = filename
		records.append(record)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.stats.mean_ms < b.stats.mean_ms)
	return {"records": records, "skipped": skipped}

static func _normalize_metadata(record: Dictionary) -> void:
	# Older or hand-edited JSON may omit metadata, or store the wrong type.
	# Repair only our in-memory copy; never rewrite the user's saved file.
	if not record.get("device") is Dictionary:
		record["device"] = {}
	for field in ["false_starts", "timeouts"]:
		var value: Variant = record.get(field, 0)
		var valid_number: bool = value is int or value is float
		if valid_number:
			valid_number = is_finite(float(value)) and float(value) >= 0 and float(value) < 2147483647
		record[field] = int(value) if valid_number else 0
	for field in ["vsync", "fullscreen"]:
		if not record.get(field) is bool:
			record[field] = false
	if not record.get("created_at") is String:
		record["created_at"] = ""

static func _valid_filename(filename: String) -> bool:
	# Accept a simple JSON basename only, never a path supplied inside saved data.
	return not filename.is_empty() and filename == filename.get_file() and not filename.contains("\\") and not filename.contains(":") and filename.ends_with(".json")

static func trash_run(filename: String, folder: String = "") -> String:
	if folder.is_empty():
		folder = data_folder().path_join("results")
	# Soft deletion: move into our trash folder. There is no permanent-delete call.
	return _relocate_run(filename, folder, false)

static func restore_run(filename: String, folder: String = "") -> String:
	if folder.is_empty():
		folder = data_folder().path_join("results")
	# The reverse operation uses the same path checks as trashing.
	return _relocate_run(filename, folder, true)

static func _relocate_run(filename: String, folder: String, restore: bool) -> String:
	# Work with resolved absolute paths and check their parent folders before moving.
	if not _valid_filename(filename):
		return "Invalid result filename; nothing was changed."
	var base := ProjectSettings.globalize_path(folder).simplify_path()
	var trash := base.path_join("trash")
	var source := (trash if restore else base).path_join(filename).simplify_path()
	var destination := (base if restore else trash).path_join(filename).simplify_path()
	# Only one immediate child JSON file can move within this result directory.
	if source.get_base_dir() != (trash if restore else base) or destination.get_base_dir() != (base if restore else trash):
		return "This result is outside the results folder. Nothing was changed."
	if not FileAccess.file_exists(source):
		return "Result file was not found. Nothing was changed."
	if FileAccess.file_exists(destination):
		return "A file with that name already exists at the destination. Nothing was overwritten."
	var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if error == OK:
		error = DirAccess.rename_absolute(source, destination)
	if error != OK:
		return "Could not move this result (error %s). Please try again." % error
	return ""
