
require'tr2_paint_cairo'
setfenv(1, require'tr2')

terra load_font(self: &Font)
	self.file_data, self.file_size = readfile'media/fonts/OpenSans-Regular.ttf'
	return self.file_data ~= nil
end

terra unload_font(self: &Font)
	free(self.file_data)
	self.file_data = nil
	self.file_size = 0
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
