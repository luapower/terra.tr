
--Painting rasterized glyph runs into a cairo surface.

setfenv(1, require'tr2_env')

includepath'$L/csrc/cairo/src'
include'cairo.h'
linklibrary'cairo'

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
			var sr0 = [&cairo_surface_t](glyph.surface)
			var sr1 = cairo_image_surface_create(
				format,
				ceil(w1),
				ceil(h1))
			var cr = cairo_create(sr1)
			cairo_translate(cr, glyph.offset_x, glyph.offset_y)
			cairo_scale(cr, w1 / w, h1 / h)
			cairo_set_source_surface(cr, sr0, 0, 0)
			cairo_paint(cr)
			cairo_set_source_rgb(cr, 0, 0, 0) --release source
			cairo_destroy(cr)
			cairo_surface_destroy(sr0)
			glyph.surface = sr1
		end
	end

end

terra TextRenderer:unwrap_glyph(glyph: &Glyph)
	if glyph.surface ~= nil then
		cairo_surface_destroy([&cairo_surface_t](glyph.surface))
		glyph.surface = nil
	end
end

--NOTE: clip_left and clip_right are relative to bitmap's left edge.
terra TextRenderer:paint_glyph(
	cr: &GraphicsContext, glyph: &Glyph,
	x: num, y: num, clip_left: num, clip_right: num
)
	var surface = [&cairo_surface_t](glyph.surface)
	var clip = clip_left ~= 0 or clip_right ~= 0
	if clip then
		cairo_save(cr)
		cairo_new_path(cr)
		var x1 = x + clip_left
		var x2 = x + glyph.ft_bitmap.width + clip_right
		cairo_rectangle(cr, x1, y, x2 - x1, glyph.ft_bitmap.rows)
		cairo_clip(cr)
	end
	if glyph.ft_bitmap.pixel_mode == FORMAT_G8 then
		cairo_mask_surface(cr, surface, x, y)
	else
		cairo_set_source_surface(cr, surface, x, y)
		cairo_paint(cr)
		cairo_set_source_rgb(cr, 0, 0, 0) --clear source
	end
	if clip then
		cairo_restore(cr)
	end
end

terra TextRenderer:setcontext(cr: &GraphicsContext, text_run: &TextRun)
	var r, g, b, a = text_run.color
	a = a * text_run.opacity
	cairo_set_source_rgba(cr, r, g, b, a)
	cairo_set_operator(cr, text_run.operator)
end
