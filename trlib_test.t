
require'trlib_paint_cairo'
require'cairolib'
setfenv(1, require'trlib')

terra load_font(self: &Font, file_data: &&opaque, file_size: &int64)
	@file_data, @file_size = readfile'media/fonts/OpenSans-Regular.ttf'
end

terra unload_font(self: &Font, file_data: &&opaque, file_size: &int64)
	free(@file_data)
	@file_size = 0
end

terra test()
	var sr = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1000, 1000)
	var cr = sr:context()

	var tr: TextRenderer; tr:init()
	print('tr.glyph_runs.max_size', tr.glyph_runs.max_size)

	var font: Font; font:init(&tr, load_font, unload_font)

	var runs: TextRuns; runs:init()
	escape
		local s = 'Hello World!'
		local t = {}
		for i=1,#s do
			local c = s:byte(i,i)
			emit quote runs.text:add(c) end
		end
	end
	print(runs.text.len)

	var r: TextRun; r:init()
	r.offset = 0
	r.font = &font
	r.font_size = 14
	runs.array:push(r)

	for i = 1, 10 do
		var segs: Segs; segs:init(&tr)
		tr:shape(&runs, &segs)
		segs:wrap(100)
		segs:align(0, 0, 1000, 1000, ALIGN_CENTER, ALIGN_CENTER)
		tr:paint(cr, &segs)
		segs:free()
	end

	pfn('Glyph cache size     : %d', tr.glyphs.size)
	pfn('Glyph cache count    : %d', tr.glyphs.count)
	pfn('GlyphRun cache size  : %d', tr.glyph_runs.size)
	pfn('GlyphRun cache count : %d', tr.glyph_runs.count)

	runs:free()
	tr:free()

	cr:free()
	sr:free()
end
test()
