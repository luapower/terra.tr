
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
	var tr = TextRenderer; tr:init()

	var font: Font; font:init()
	fill(&font)
	font.tr = &tr
	font.load = load_font
	font.unload = unload_font

	var runs: TextRuns; runs:init()
	runs.len = 5
	runs.codepoints = new(codepoint, 3)
	runs.codepoints[0] = 65
	runs.codepoints[1] = 66
	runs.codepoints[2] = 67
	var r = TextRun(nil)
	r.offset = 0
	r.font = &font
	r.font_size = 14
	runs.runs:push(r)

	var segs = Segs(nil)

	tr:shape(&runs, &segs)

	segs:free()

	free(runs.codepoints)

	--[[
	var run: GlyphRun; fill(&run)
	var a = arrayof(uint32, 65, 66, 67)
	run.text = a
	run.text_len = 3
	run.font = &font
	run.font_size = 14
	run.features = nil
	run.num_features = 0
	run.script = HB_SCRIPT_INVALID
	run.lang = nil
	run.rtl = false

	var runp = tr:shape_word(&run)
	assert(runp ~= nil)
	]]

	tr:free()
end
test()
