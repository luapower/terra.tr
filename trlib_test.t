
require'trlib_paint_cairo'
setfenv(1, require'trlib')

terra load_font(self: &Font, file_data: &&opaque, file_size: &int64)
	@file_data, @file_size = readfile'media/fonts/OpenSans-Regular.ttf'
end

terra unload_font(self: &Font, file_data: &&opaque, file_size: &int64)
	free(@file_data)
	@file_size = 0
end

terra test()
	var tr: TextRenderer; tr:init()

	var font: Font; font:init(&tr, load_font, unload_font)

	var runs: TextRuns; runs:init()
	runs.text:add(65)
	runs.text:add(66)
	runs.text:add(67)

	var r: TextRun; r:init()
	r.offset = 0
	r.font = &font
	r.font_size = 14
	runs.array:push(r)

	var segs: Segs; segs:init(&tr)
	tr:shape(&runs, &segs)
	segs:wrap(100)
	segs:align(0, 0, 100, 100, ALIGN_CENTER, ALIGN_CENTER)
	print(segs)

	segs:free()
	runs:free()
	tr:free()
end
test()
