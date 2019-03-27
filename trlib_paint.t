
--Painting rasterized glyph runs into a cairo surface.

if not ... then require'trlib_test'; return end

setfenv(1, require'trlib_types')
require'trlib_clip'
require'trlib_rasterize'

--NOTE: clip_left and clip_right are relative to glyph run's origin.
terra TextRenderer:paint_glyph_run(
	cr: &GraphicsContext, gr: &GlyphRun, i: int, j: int,
	ax: num, ay: num, clip: bool, clip_left: num, clip_right: num
): {}

	if not clip and j > 2 and gr.font_size < 50 then
		var sr, sx, sy = self:rasterize_glyph_run(gr, ax, ay)
		self:paint_surface(cr, sr, sx, sy, false, 0, 0)
		inc(self.paint_glyph_num)
		return
	end

	for sr, sx, sy in self:glyph_run_surfaces(gr, i, j, ax, ay) do
		if clip then
			--make clip_left and clip_right relative to bitmap's left edge.
			clip_left  = clip_left + ax - sx
			clip_right = clip_right + ax - sy
		end
		self:paint_surface(cr, sr, sx, sy, clip, clip_left, clip_right)
		inc(self.paint_glyph_num)
	end
end

terra TextRenderer:paint(cr: &GraphicsContext, layout: &Layout)

	var segs = &layout.segs
	var lines = &layout.lines

	if not layout.clip_valid then
		layout:reset_clip()
	end

	for line_i = layout.first_visible_line, layout.last_visible_line + 1 do
		var line = lines:at(line_i)
		if line.visible then

			var ax = layout.x + line.x
			var ay = layout.y + layout.baseline + line.y

			var seg = line.first_vis
			while seg ~= nil do
				if seg.visible then

					var gr = layout:glyph_run(seg)
					var x, y = ax + seg.x, ay

					--[[
					--TODO: subsegments
					if #seg > 0 then --has sub-segments, paint them separately
						for i = 1, #seg, 5 do
							var i, j, text_run, clip_left, clip_right = unpack(seg, i, i + 4)
							rs:setcontext(cr, text_run)
							paint_glyph_run(cr, rs, run, i, j, x, y, true, clip_left, clip_right)
						end
					else
					]]

					self:setcontext(cr, seg.span)
					self:paint_glyph_run(cr, gr, 0, gr.glyphs.len, x, y, false, 0, 0)
					--end

				end
				seg = seg.next_vis
			end
		end
	end

end
