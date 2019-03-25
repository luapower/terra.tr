
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

local s = 'Hello World\nNew Line'
--local s = glue.readfile'winapi_history.md'
local s = glue.readfile'lorem_ipsum.txt'

terra test()
	var sr = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1800, 900); defer sr:free()
	var cr = sr:context(); defer cr:free()
	var tr: TextRenderer; tr:init(); defer tr:free()

	var font_id = tr:font(load_font, unload_font)

	var runs: TextRuns; runs:init()
	var len = [#s]
	var s: rawstring = s
	for i=0,len do
		assert(s[i] > 0)
		runs.text:add(s[i])
	end

	var r: TextRun; r:init()
	r.offset = 0
	r.font_id = font_id
	r.font_size = 12
	r.color = 0xffffffff
	runs.array:push(r)

	probe'start'

	var segs: Segs; segs:init(&tr)
	tr:shape(&runs, &segs)
	segs:wrap(sr:width())
	segs:align(0, 0, sr:width(), sr:height(), ALIGN_LEFT, ALIGN_TOP)
	probe'shape/wrap/align'

	tr.paint_glyph_num = 0
	var glyphs_per_frame = 8500
	var t0 = clock()
	var times = 60
	for i=0,times do
		tr:paint(cr, &segs)
	end
	var dt = clock() - t0
	pfn('%.2f\tpaint %d times, %d glyphs, %.2f%% of a frame @60fps',
		dt, times, tr.paint_glyph_num, 100 * 8500 * 60 * dt / tr.paint_glyph_num)

	segs:free()

	sr:save_png'trlib_test.png'

	pfn('Glyph cache size     : %d', tr.glyphs.size)
	pfn('Glyph cache count    : %d', tr.glyphs.count)
	pfn('GlyphRun cache size  : %d', tr.glyph_runs.size)
	pfn('GlyphRun cache count : %d', tr.glyph_runs.count)

	runs:free()
end
test()
