
--Glyph caching & rasterization based on freetype's rasterizer.
--Written by Cosmin Apreutesei. Public Domain.

if not ... then require'trlib_test'; return end

setfenv(1, require'trlib_types')
require'trlib_font'

terra Font:load_glyph(font_size: num, glyph_index: uint)
	self:setsize(font_size)
	if FT_Load_Glyph(self.ft_face, glyph_index, self.ft_load_flags) ~= 0 then
		return nil
	end
	var ft_glyph = self.ft_face.glyph
	var w = ft_glyph.metrics.width
	var h = ft_glyph.metrics.height
	if w == 0 or h == 0 then
		return nil
	end
	return ft_glyph
end

terra Glyph:free(r: &Renderer)
	if self.surface == nil then return end
	var font = r.fonts:at(self.font_id)
	font.r:unwrap_glyph(self)
	font:unref()
end

terra Glyph:rasterize(r: &Renderer)

	var font = r.fonts:at(self.font_id)

	var glyph = font:load_glyph(self.font_size, self.glyph_index)
	if glyph == nil then
		self.surface = nil
		return
	end

	font:ref()

	if glyph.format == FT_GLYPH_FORMAT_OUTLINE then
		FT_Outline_Translate(&glyph.outline, self.subpixel_offset_x_8_6, 0)
	end
	if glyph.format ~= FT_GLYPH_FORMAT_BITMAP then
		FT_Render_Glyph(glyph, font.ft_render_flags)
	end
	assert(glyph.format == FT_GLYPH_FORMAT_BITMAP)

	var bitmap = &glyph.bitmap

	--BGRA bitmaps must already have aligned pitch because we can't change that
	assert(bitmap.pixel_mode ~= FT_PIXEL_MODE_BGRA or ((bitmap.pitch and 3) == 0))

	--bitmaps must be top-down because we can't change that
	assert(bitmap.pitch >= 0) --top-down

	if (bitmap.pitch and 3) ~= 0
		or (bitmap.pixel_mode ~= FT_PIXEL_MODE_GRAY
			and bitmap.pixel_mode ~= FT_PIXEL_MODE_BGRA)
	then
		var tmp_bitmap: FT_Bitmap
		FT_Bitmap_Init(&tmp_bitmap)
		FT_Bitmap_Convert(font.r.ft_lib, bitmap, &tmp_bitmap, 4)
		assert(tmp_bitmap.pixel_mode == FT_PIXEL_MODE_GRAY)
		assert((tmp_bitmap.pitch and 3) == 0)

		font.r:wrap_glyph(self, &tmp_bitmap)

		FT_Bitmap_Done(font.r.ft_lib, &tmp_bitmap)
	else
		font.r:wrap_glyph(self, bitmap)
	end

	self.surface_x = glyph.bitmap_left * font.scale + 0.5
	self.surface_y = glyph.bitmap_top  * font.scale + 0.5
end

local empty_glyph = constant(Glyph.empty)

terra Renderer:rasterize_glyph(
	font_id: font_id_t, font_size: num,
	glyph_index: uint, x: num, y: num
)

	if glyph_index == 0 then --freetype code for "missing glyph"
		return -1, &empty_glyph, x, y
	end
	font_size = snap(font_size, self.font_size_resolution)
	var sx = floor(x)
	var sy = floor(y)
	var subpixel_offset_x = snap(x - sx, self.subpixel_x_resolution)
	var glyph: Glyph;
	glyph.font_id = font_id;
	glyph.glyph_index = glyph_index;
	glyph.font_size = font_size;
	glyph.subpixel_offset_x = subpixel_offset_x;
	var glyph_id, pair = self.glyphs:get(glyph)
	if pair == nil then
		glyph:rasterize(self)
		glyph_id, pair = self.glyphs:put(glyph, {})
	end
	var glyph_ref = &pair.key
	var x = sx + glyph_ref.surface_x
	var y = sy - glyph_ref.surface_y
	return glyph_id, glyph_ref, x, y
end

local struct glyph_run_surfaces {
	r: &Renderer;
	gr: &GlyphRun;
	i: uint16; j: uint16;
	ax: num; ay: num;
}
glyph_run_surfaces.metamethods.__for = function(self, body)
	return quote
		var gr = self.gr
		for i: uint16 = self.i, self.j do
			var g = gr.glyphs:at(i)
			var glyph_id, glyph, sx, sy = self.r:rasterize_glyph(
				gr.font_id, gr.font_size, g.glyph_index,
				self.ax + g.x + g.image_x,
				self.ay + g.image_y
			)
			if glyph.surface ~= nil then
				[ body(`glyph.surface, sx, sy) ]
			end
		end
	end
end
terra Renderer:glyph_run_surfaces(gr: &GlyphRun, i: uint16, j: uint16, ax: num, ay: num)
	return glyph_run_surfaces {r = self, gr = gr, i = i, j = j, ax = ax, ay = ay}
end

terra Renderer:glyph_run_bbox(gr: &GlyphRun, ax: num, ay: num)
	var ox = self:word_subpixel_offset_x(ax)
	var bbox = box2d.bbox()
	for sr, sx, sy in self:glyph_run_surfaces(gr, 0, gr.glyphs.len, ox, 0) do
		bbox:add(sx, sy, sr:width(), sr:height())
	end
	return bbox()
end

terra Renderer:word_subpixel_offset_x(ax: num)
	return snap(ax - floor(ax), self.word_subpixel_x_resolution)
end

terra Renderer:word_subpixel_surface_index(ax: num)
	return self:word_subpixel_offset_x(ax) / self.word_subpixel_x_resolution
end

terra Renderer:rasterize_glyph_run(gr: &GlyphRun, ax: num, ay: num)
	var ox = self:word_subpixel_offset_x(ax)
	var si = self:word_subpixel_surface_index(ax)
	var sr = gr.surfaces(si, nil)
	var sx = floor(ax)
	var sy = floor(ay)
	if sr == nil then
		var bx, by, bw, bh = self:glyph_run_bbox(gr, ox, 0)
		sr = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, bw, bh)
		var srcr = sr:context()
		srcr:translate(-bx, -by)
		var ox = self:word_subpixel_offset_x(ax)
		for gsr, gsx, gsy in self:glyph_run_surfaces(gr, 0, gr.glyphs.len, ox, 0) do
			self:paint_surface(srcr, gsr, gsx, gsy, false, 0, 0)
		end
		srcr:free()
		gr.surfaces:set(si, sr)
		inc(gr.surfaces_memsize, 1024 + sr:height() * sr:stride())
		gr.surface_x = bx
		gr.surface_y = by
	end
	return sr, sx + gr.surface_x, sy + gr.surface_y
end
