
--Cairo graphics adapter for trlib.
--Paints (and scales) rasterized glyph runs into a cairo surface.

setfenv(1, require'trlib_env')
require'cairolib'
color = cairo_argb32_color_t
GraphicsSurface = cairo_surface_t
default_color_constant_text      = `color {0x000000ff}
default_color_constant_selection = `color {0x77770077}
setfenv(1, require'trlib_types')

GraphicsContext = cairo_t

terra box_fit(w: num, h: num, bw: num, bh: num)
	if w / h > bw / bh then
		return bw, bw * h / w
	else
		return bh * w / h, bh
	end
end

terra TextRenderer:wrap_glyph(glyph: &Glyph)

	var w = glyph.ft_bitmap.width
	var h = glyph.ft_bitmap.rows

	var format = iif(glyph.ft_bitmap.pixel_mode == FORMAT_G8,
		CAIRO_FORMAT_A8, CAIRO_FORMAT_ARGB32)

	glyph.surface = cairo_image_surface_create_for_data(
		glyph.ft_bitmap.buffer, format, w, h, glyph.ft_bitmap.pitch)

	--scale raster glyphs which freetype cannot scale by itglyph.
	if glyph.font.scale ~= 1 then
		var bw = glyph.font.size
		if w ~= bw and h ~= bw then
			var w1, h1 = box_fit(w, h, bw, bw)
			var sr0 = glyph.surface; defer sr0:free()
			var sr1 = cairo_image_surface_create(
				format,
				ceil(w1),
				ceil(h1))
			var cr = cairo_create(sr1); defer cr:free()
			cr:translate(glyph.offset_x, glyph.offset_y)
			cr:scale(w1 / w, h1 / h)
			cr:source(sr0, 0, 0)
			cr:paint()
			cr:rgb(0, 0, 0) --release source
			glyph.surface = sr1
		end
	end

end

terra TextRenderer:unwrap_glyph(glyph: &Glyph)
	free(glyph.surface)
end

--NOTE: clip_left and clip_right are relative to bitmap's left edge.
terra TextRenderer:paint_glyph(
	cr: &GraphicsContext, glyph: &Glyph,
	x: num, y: num, clip_left: num, clip_right: num
)
	var surface = [&cairo_surface_t](glyph.surface)
	var clip = clip_left ~= 0 or clip_right ~= 0
	if clip then
		cr:save()
		cr:new_path()
		var x1 = x + clip_left
		var x2 = x + glyph.ft_bitmap.width + clip_right
		cr:rectangle(x1, y, x2 - x1, glyph.ft_bitmap.rows)
		cr:clip()
	end
	if glyph.ft_bitmap.pixel_mode == FORMAT_G8 then
		cr:mask(surface, x, y)
	else
		cr:source(surface, x, y)
		cr:paint()
		cr:rgb(0, 0, 0) --clear source
	end
	if clip then
		cr:restore()
	end
end

terra TextRenderer:setcontext(cr: &GraphicsContext, text_run: &TextRun)
	var c: cairo_color_t = text_run.color --implicit cast
	c.alpha = c.alpha * text_run.opacity
	cr:rgba(c)
	cr:operator(text_run.operator)
end
