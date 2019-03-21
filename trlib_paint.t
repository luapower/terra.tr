
--Painting rasterized glyph runs into a cairo surface.

setfenv(1, require'trlib_types')
require'trlib_clip'
require'trlib_rasterize'

--NOTE: clip_left and clip_right are relative to glyph run's origin.
terra TextRenderer:paint_glyph_run(
	cr: &GraphicsContext, run: &GlyphRun, i: int, j: int,
	ax: num, ay: num, clip: bool, clip_left: num, clip_right: num
)
	for i = i, j do

		var glyph_index = run.info[i].codepoint
		var px = iif(i > 0, run.pos[i-1].x_advance / 64.0, 0.0)
		var ox = run.pos[i].x_offset / 64.0
		var oy = run.pos[i].y_offset / 64.0

		var glyph, bmpx, bmpy = self:rasterize_glyph(
			run.font, run.font_size, glyph_index,
			ax + px + ox,
			ay - oy
		)

		if glyph.ft_bitmap.buffer ~= nil then
			if clip then
				--make clip_left and clip_right relative to bitmap's left edge.
				clip_left  = clip_left + ax - bmpx
				clip_right = clip_right + ax - bmpx
			end
			print('paint_glyph', i, bmpx, bmpy, clip, clip_left, clip_right)
			self:paint_glyph(cr, glyph, bmpx, bmpy, clip, clip_left, clip_right)
		end
	end
end

terra TextRenderer:paint(cr: &GraphicsContext, segs: &Segs)

	if not segs.clip_valid then
		segs:reset_clip()
	end

	var lines = &segs.lines
	for line_i = lines.first_visible, lines.last_visible + 1 do
		print('paint line', line_i, lines.array.len)
		var line = lines.array:at(line_i)
		if line.visible then

			var ax = lines.x + line.x
			var ay = lines.y + lines.baseline + line.y

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
							paint_glyph_run(cr, rs, run, i, j, x, y, true, clip_left, clip_right)
						end
					else
					]]

					self:setcontext(cr, seg.text_run)
					print('paint seg', @seg)
					self:paint_glyph_run(cr, run, 0, run.len, x, y, false, 0, 0)
					--end

				end
				seg = seg.next_vis
			end
		end
	end

end
