
--Glyph caching & rasterization based on freetype's rasterizer.
--Written by Cosmin Apreutesei. Public Domain.

setfenv(1, require'trlib_types')
require'trlib_font'

terra Font:load_glyph(font_size: num, glyph_index: int)
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

terra Glyph:rasterize()

	var ft_glyph = self.font:load_glyph(self.font_size, self.glyph_index)
	if ft_glyph == nil then
		self.ft_bitmap.buffer = nil --mark invalid
		return self
	end

	self.font:ref()

	if ft_glyph.format == FT_GLYPH_FORMAT_OUTLINE then
		FT_Outline_Translate(&ft_glyph.outline, self.offset_x * 64, -self.offset_y * 64)
	end
	if ft_glyph.format ~= FT_GLYPH_FORMAT_BITMAP then
		FT_Render_Glyph(ft_glyph, self.font.ft_render_flags)
	end
	assert(ft_glyph.format == FT_GLYPH_FORMAT_BITMAP)

	--BGRA bitmaps must already have aligned pitch because we can't change that
	assert(ft_glyph.bitmap.pixel_mode ~= FT_PIXEL_MODE_BGRA
		or ((ft_glyph.bitmap.pitch and 3) == 0))

	--bitmaps must be top-down because we can't change that
	assert(ft_glyph.bitmap.pitch >= 0) --top-down

	FT_Bitmap_New(&self.ft_bitmap)

	if (ft_glyph.bitmap.pitch and 3) ~= 0
		or (ft_glyph.bitmap.pixel_mode ~= FT_PIXEL_MODE_GRAY
			and ft_glyph.bitmap.pixel_mode ~= FT_PIXEL_MODE_BGRA)
	then
		FT_Bitmap_Convert(self.font.tr.ft_lib, &ft_glyph.bitmap, &self.ft_bitmap, 4)
		assert(self.ft_bitmap.pixel_mode == FT_PIXEL_MODE_GRAY)
		assert((self.ft_bitmap.pitch and 3) == 0)
	else
		FT_Bitmap_Copy(self.font.tr.ft_lib, &ft_glyph.bitmap, &self.ft_bitmap)
	end

	self.ft_bitmap_left = round(ft_glyph.bitmap_left * self.font.scale)
	self.ft_bitmap_top  = round(ft_glyph.bitmap_top  * self.font.scale)

	self.font.tr:wrap_glyph(self)

	return self
end

--glyph LRU cache

terra Glyph:__memsize()
	return sizeof(Glyph) + self.ft_bitmap.rows * self.ft_bitmap.pitch
end

terra Glyph:free()
	self.font.tr:unwrap_glyph(self)
	FT_Bitmap_Done(self.font.tr.ft_lib, &self.ft_bitmap)
	self.font:unref()
end

local empty_glyph = constant(`Glyph{font=nil})

terra TextRenderer:rasterize_glyph(
	font: &Font, font_size: num,
	glyph_index: int, x: num, y: num
)
	if glyph_index == 0 then --freetype code for "missing glyph"
		return &empty_glyph, x, y
	end
	font_size = snap(font_size, self.font_size_resolution)
	var pixel_x = floor(x)
	var pixel_y = floor(y)
	var offset_x = snap(x - pixel_x, self.subpixel_x_resolution)
	var offset_y = snap(y - pixel_y, self.subpixel_y_resolution)
	var glyph = Glyph {
		font = font,
		font_size = font_size,
		glyph_index = glyph_index,
		offset_x = offset_x,
		offset_y = offset_y
	}
	var pair = self.glyphs:get(glyph)
	if pair == nil then
		glyph:rasterize()
		pair = self.glyphs:put(glyph, true)
		assert(pair ~= nil)
	end
	var glyph_ref = &pair.key
	var x = pixel_x + glyph_ref.ft_bitmap_left
	var y = pixel_y - glyph_ref.ft_bitmap_top
	return glyph_ref, x, y
end
