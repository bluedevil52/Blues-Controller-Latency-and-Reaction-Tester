extends SceneTree
## Render the editable SVG into a PNG and a Windows icon with seven sizes.
func _initialize() -> void:
	var svg := FileAccess.get_file_as_string("res://icons/blue-dpad.svg")
	var sizes := [16, 24, 32, 48, 64, 128, 256]
	var images: Array[PackedByteArray] = []
	for size in sizes:
		var picture := Image.new()
		if picture.load_svg_from_string(svg, float(size) / 256.0) != OK:
			push_error("Could not render the icon SVG")
			quit(1)
			return
		images.append(picture.save_png_to_buffer())
		if size == 256:
			picture.save_png("res://icons/blue-dpad.png")
	# ICO: six-byte header, then a 16-byte entry pointing to each size's PNG.
	var ico := FileAccess.open("res://icons/blue-dpad.ico", FileAccess.WRITE)
	ico.store_16(0)
	ico.store_16(1) # Type 1 is an icon, rather than a cursor.
	ico.store_16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var dimension: int = 0 if sizes[i] == 256 else sizes[i]
		ico.store_8(dimension) # Zero represents 256 in this one-byte field.
		ico.store_8(dimension)
		ico.store_8(0)
		ico.store_8(0)
		ico.store_16(1)
		ico.store_16(32)
		ico.store_32(images[i].size())
		ico.store_32(offset)
		offset += images[i].size()
	for data in images:
		ico.store_buffer(data)
	ico.close()
	print("Created app PNG and Windows ICO (seven sizes).")
	quit()
