extends SceneTree
# Include the engine's own license notices alongside every distributed executable.
func _initialize() -> void:
	var file := FileAccess.open("res://THIRD_PARTY_NOTICES.txt", FileAccess.WRITE)
	file.store_string("Godot Engine\n============\n" + Engine.get_license_text() + "\n\n")
	for component in Engine.get_copyright_info():
		file.store_string(str(component) + "\n\n")
	var licenses := Engine.get_license_info()
	for name in licenses:
		file.store_string(str(name) + "\n" + str(licenses[name]) + "\n\n")
	file.close()
	quit()
