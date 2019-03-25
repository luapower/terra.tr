
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

terra Glyph:free(tr: &TextRenderer)
	if self.surface == nil then return end
	var font = tr.fonts:at(self.font_id)
	font.tr:unwrap_glyph(self)
	font:unref()
end

terra Glyph:rasterize(tr: &TextRenderer)

	var font = tr.fonts:at(self.font_id)

	var glyph = font:load_glyph(self.font_size, self.glyph_index)
	if glyph == nil then return end

	font:ref()

	if glyph.format == FT_GLYPH_FORMAT_OUTLINE then
		FT_Outline_Translate(&glyph.outline, self.offset_x_8_6, 0)
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
		FT_Bitmap_Convert(font.tr.ft_lib, bitmap, &tmp_bitmap, 4)
		assert(tmp_bitmap.pixel_mode == FT_PIXEL_MODE_GRAY)
		assert((tmp_bitmap.pitch and 3) == 0)

		font.tr:wrap_glyph(self, &tmp_bitmap)

		FT_Bitmap_Done(font.tr.ft_lib, &tmp_bitmap)
	else
		font.tr:wrap_glyph(self, bitmap)
	end

	self.x = glyph.bitmap_left * font.scale + 0.5
	self.y = glyph.bitmap_top  * font.scale + 0.5
end

local empty_glyph = constant(Glyph.empty)

terra TextRenderer:rasterize_glyph(
	font_id: font_id_t, font_size: num,
	glyph_index: uint, x: num, y: num
)
	if glyph_index == 0 then --freetype code for "missing glyph"
		return &empty_glyph, x, y
	end
	font_size = snap(font_size, self.font_size_resolution)
	var pixel_x = floor(x)
	var pixel_y = floor(y)
	var offset_x = snap(x - pixel_x, self.subpixel_x_resolution)
	var glyph = Glyph {
		font_id = font_id;
		font_size_16_6 = font_size * 64;
		glyph_index = glyph_index;
		offset_x_8_6 = offset_x * 64;
	}
	var pair = self.glyphs:get(glyph)
	if pair == nil then
		glyph:rasterize(self)
		pair = self.glyphs:put(glyph, {})
	end
	var glyph_ref = &pair.key
	var x = pixel_x + glyph_ref.x
	var y = pixel_y - glyph_ref.y
	return glyph_ref, x, y
end
