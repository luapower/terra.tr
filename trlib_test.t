
require'trlib_paint_cairo'
require'cairolib'
require'utf8lib'
setfenv(1, require'trlib')

terra load_font(self: &Font, file_data: &&opaque, file_size: &int64)
	@file_data, @file_size = readfile'media/fonts/OpenSans-Regular.ttf'
end

terra unload_font(self: &Font, file_data: &&opaque, file_size: &int64)
	free(@file_data)
end

local s = 'Hello World\nNew Line'
--local s = glue.readfile'winapi_history.md'
local s = glue.readfile'lorem_ipsum.txt'

terra test()
	var sr = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1800, 900); defer sr:free()
	var cr = sr:context(); defer cr:free()
	var r: Renderer; r:init(); defer r:free()

	var font_id = r:font(load_font, unload_font)

	var layout: Layout; layout:init(&r)
	utf8.decode.toarr([s], [#s], &layout.text, maxint, utf8.REPLACE, utf8.INVALID)

	var sp: Span; sp:init()
	sp.offset = 0
	sp.font_id = font_id
	sp.font_size = 12
	sp.color = 0xffffffff
	layout.spans:push(sp)

	probe'start'

	layout:shape()
	layout:wrap(sr:width())
	layout:align(0, 0, sr:width(), sr:height(), ALIGN_LEFT, ALIGN_TOP)
	layout:clip(0, 0, sr:width(), sr:height())
	assert(layout.clip_valid)
	probe'shape/wrap/align/clip'

	r.paint_glyph_num = 0
	--var glyphs_per_frame = 8500
	var glyphs_per_frame = 1800
	var wanted_fps = 60
	var t0 = clock()
	var times = 60
	for i=0,times do
		cr:rgb(0, 0, 0)
		cr:paint()
		layout:paint(cr)
	end
	var dt = clock() - t0
	pfn('%.2fs\tpaint %d times, %d glyphs, %.2f%% of a frame @60fps',
		dt, times, r.paint_glyph_num, 100 * glyphs_per_frame * wanted_fps * dt / r.paint_glyph_num)

	layout:free()

	sr:save_png'trlib_test.png'

	pfn('Glyph cache size     : %d', r.glyphs.size)
	pfn('Glyph cache count    : %d', r.glyphs.count)
	pfn('GlyphRun cache size  : %d', r.glyph_runs.size)
	pfn('GlyphRun cache count : %d', r.glyph_runs.count)
end
test()
