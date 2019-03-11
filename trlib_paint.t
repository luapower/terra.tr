
--Painting rasterized glyph runs into a cairo surface.

setfenv(1, require'trlib_types')
require'trlib_clip'
require'trlib_rasterize'

--NOTE: clip_left and clip_right are relative to glyph run's origin.
terra TextRenderer:paint_glyph_run(
	cr: &GraphicsContext, run: &GlyphRun, i: int, j: int,
	ax: num, ay: num, clip_left: num, clip_right: num
)
	for i = i, j do

		var glyph_index = run.info[i].codepoint
		var px = iif(i > 0, run.pos[i-1].x_advance / 64, 0)
		var ox = run.pos[i].x_offset / 64
		var oy = run.pos[i].y_offset / 64

		var glyph, bmpx, bmpy = self:rasterize_glyph(
			run.font, run.font_size, glyph_index,
			ax + px + ox,
			ay - oy
		)

		--make clip_left and clip_right relative to bitmap's left edge.
		clip_left = iif(clip_left ~= -1, clip_left + ax - bmpx, 0)
		clip_right = iif(clip_right ~= -1, clip_right + ax - bmpx, 0)

		self:paint_glyph(cr, glyph, bmpx, bmpy, clip_left, clip_right)
	end
end

terra TextRenderer:paint(cr: &GraphicsContext, segs: &Segs)

	if not segs.clip_valid then
		segs:reset_clip()
	end

	var lines = &segs.lines
	for line_i = lines.first_visible, lines.last_visible + 1 do
		var line = lines.array:at(line_i)
		if line.visible then

			var ax = lines.x + line.x
			var ay = lines.y + lines.baseline + line.y

			print(line_i, line, line.x, line.first_vis, segs.array.elements, segs.array.len)
			var seg = line.first_vis
			while seg ~= nil do
				if seg.visible then

					var run = seg.glyph_run
					var x, y = ax + seg.x, ay

					--[[
					--TODO: subsegments
					if #seg > 0 then --has sub-segments, paint them separately
						for i = 1, #seg, 5 do
							var i, j, text_run, clip_left, clip_right = unpack(seg, i, i + 4)
							rs:setcontext(cr, text_run)
							paint_glyph_run(cr, rs, run, i, j, x, y, clip_left, clip_right)
						end
					else
					]]
					self:setcontext(cr, seg.text_run)
					self:paint_glyph_run(cr, run, 0, run.len-1, x, y, -1, -1)
					--end

				end
				seg = seg.next_vis
			end
		end
	end

end
