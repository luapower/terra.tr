
--Mark segments as clipped.

setfenv(1, require'trlib_env')
require'trlib_hit_test'

local overlap_seg = macro(function(ax1, ax2, bx1, bx2) --1D segments overlap test
	return `not (ax2 < bx1 or bx2 < ax1)
end)

local box_overlapping = macro(function(x1, y1, w1, h1, x2, y2, w2, h2)
	return `overlap_seg(x1, x1+w1, x2, x2+w2)
	    and overlap_seg(y1, y1+h1, y2, y2+h2)
end)

--NOTE: doesn't take into account side bearings, so it's not 100% accurate!
terra Segs:clip(x: num, y: num, w: num, h: num)
	var lines = self.lines
	x = x - lines.x
	y = y - lines.y - lines.baseline
	var first_visible = lines:line_at_y(y) or 1
	var last_visible = lines:line_at_y(y + h - 1/256) or 0
	for line_i = first_visible, last_visible do
		var line = lines.array:at(line_i)
		var bx = line.x
		var bw = line.advance_x
		var by = line.y - line.ascent
		var bh = line.ascent - line.descent
		line.visible = box_overlapping(x, y, w, h, bx, by, bw, bh)
		if line.visible then
			var seg = line.first_vis
			while seg ~= nil do
				var bx = bx + seg.x
				var bw = seg.advance_x
				seg.visible = box_overlapping(x, y, w, h, bx, by, bw, bh)
				seg = seg.next_vis
			end
			first_visible = first_visible or line_i
			last_visible = line_i
		end
	end
	lines.first_visible = first_visible
	lines.last_visible = last_visible
	lines.clip_valid = true
	return self
end

terra Segs:reset_clip()
	return self:clip(-inf, -inf, inf, inf)
end
