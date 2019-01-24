
--Line-wrapping a list of segments on a width.

setfenv(1, require'tr2_env')
local reorder_segs = require'tr2_wrap_reorder'

--wrap-width and advance-width of all the nowrap segments starting with the
--segment at seg_i and the seg_i after those segments.
terra Segs:nowrap_segments(seg_i: int)
	var seg = self.array:at(seg_i)
	if not seg.text_run.nowrap then
		var wx = seg.glyph_run.wrap_advance_x
		var ax = seg.glyph_run.advance_x
		wx = iif(seg.linebreak ~= BREAK_NONE or seg_i == self.array.len-1, ax, wx)
		return wx, ax, seg_i + 1
	end
	var ax = 0
	var n = self.array.len
	for i = seg_i, n do
		var seg = self.array(i)
		var ax1 = ax + seg.glyph_run.advance_x
		if i == n-1 or seg.linebreak ~= BREAK_NONE then --hard break, w == ax
			return ax1, ax1, i + 1
		elseif i < n-1 and not self.array(i+1).text_run.nowrap then
			var wx = ax + seg.glyph_run.wrap_advance_x
			return wx, ax1, i + 1
		end
		ax = ax1
	end
end

--minimum width that the text can wrap into without overflowing.
terra Segs:min_w()
	var min_w = self._min_w
	if min_w == -1/0 then
		min_w = 0
		var seg_i, n = 0, self.array.len
		while seg_i < n do
			var segs_wx, _, next_seg_i = self:nowrap_segments(seg_i)
			min_w = max(min_w, segs_wx)
			seg_i = next_seg_i
		end
		self._min_w = min_w
	end
	return min_w
end

--text width when there's no wrapping.
terra Segs:max_w()
	var max_w = self._max_w
	if max_w == 1/0 then
		max_w = 0
		var line_w = 0
		var n = self.array.len
		for i = 0, n do
			var seg = self.array(i)
			var wx = seg.glyph_run.wrap_advance_x
			var ax = seg.glyph_run.advance_x
			var linebreak = seg.linebreak ~= BREAK_NONE or i == n
			wx = iif(linebreak, ax, wx)
			line_w = line_w + wx
			if linebreak then
				max_w = max(max_w, line_w)
				line_w = 0
			end
		end
		self._max_w = max_w
	end
	return max_w
end

terra Segs:wrap(w: num, tr: &TextRenderer)

	var lines = self.lines
	lines.array:clear()
	lines.h = 0
	lines.spaced_h = 0
	lines.baseline = 0
	lines.max_ax = 0
	lines.first_visible = 0
	lines.last_visible = -1

	--do line wrapping and compute line advance.
	var seg_i, seg_count = 0, self.array.len
	var line: &Line
	while seg_i < seg_count do
		var segs_wx, segs_ax, next_seg_i = self:nowrap_segments(seg_i)

		var hardbreak = line == nil
		var softbreak = not hardbreak
			and segs_wx > 0 --don't create a new line for an empty segment
			and line.advance_x + segs_wx > w

		if hardbreak or softbreak then

			var prev_seg = self.array:at(seg_i-1) --last segment of the previous line

			--adjust last segment due to being wrapped.
			if softbreak then
				var prev_run = prev_seg.glyph_run
				line.advance_x = line.advance_x - prev_seg.advance_x
				prev_seg.advance_x = prev_run.wrap_advance_x
				prev_seg.x = iif(prev_run.rtl,
					-(prev_run.advance_x - prev_run.wrap_advance_x), 0)
				prev_seg.wrapped = true
				line.advance_x = line.advance_x + prev_seg.advance_x
			end

			if prev_seg ~= nil then --break the next* chain.
				prev_seg.next = nil
				prev_seg.next_vis = nil
			end

			line = lines.array:push_junk()
			line.index = lines.array.len-1
			line.first = self.array:at(seg_i) --first segment in text order
			line.first_vis = line.first --first segment in visual order
			line.x = 0
			line.y = 0
			line.advance_x = 0
			line.ascent = 0
			line.descent = 0
			line.spaced_ascent = 0
			line.spaced_descent = 0
			line.visible = true --entirely clipped or not

		end

		line.advance_x = line.advance_x + segs_ax

		for seg_i = seg_i, next_seg_i do
			var seg = self.array:at(seg_i)
			seg.advance_x = seg.glyph_run.advance_x
			seg.x = 0
			seg.line = line
			seg.wrapped = false
			seg.next = self.array:at(seg_i+1)
			seg.next_vis = seg.next
		end

		var last_seg = self.array:at(next_seg_i-1)
		if last_seg.linebreak ~= BREAK_NONE then
			if last_seg.linebreak == BREAK_PARA then
				--we use this particular segment's `paragraph_spacing` property
				--since this is the segment asking for a paragraph break.
				--TODO: is there a more logical way to select this property?
				line.spacing = last_seg.text_run.paragraph_spacing
			else
				line.spacing = last_seg.text_run.hardline_spacing
			end
			line = nil
		end

		seg_i = next_seg_i
	end

	--reorder RTL segments on each line separately and concatenate the runs.
	if self.bidi then
		for _,line in lines.array do
			--UAX#9/L2: reorder segments based on their bidi_level property.
			line.first_vis = reorder_segs(line.first_vis, &tr.ranges)
		end
	end

	var last_line: &Line = nil
	for _,line in lines.array do

		lines.max_ax = max(lines.max_ax, line.advance_x)

		--compute line ascent and descent scaling based on paragraph spacing.
		var ascent_factor = iif(last_line ~= nil, last_line.spacing, 1)
		var descent_factor = line.spacing

		var ax = 0
		var seg = line.first_vis
		while seg ~= nil do
			--compute line's vertical metrics.
			var run = seg.glyph_run
			line.ascent = max(line.ascent, run.ascent)
			line.descent = min(line.descent, run.descent)
			var run_h = run.ascent - run.descent
			var line_spacing = seg.text_run.line_spacing
			var half_line_gap = run_h * (line_spacing - 1) / 2
			line.spaced_ascent
				= max(line.spaced_ascent,
					(run.ascent + half_line_gap) * ascent_factor)
			line.spaced_descent
				= min(line.spaced_descent,
					(run.descent - half_line_gap) * descent_factor)
			--set segments `x` to be relative to the line's origin.
			seg.x = ax + seg.x
			ax = ax + seg.advance_x
			seg = seg.next_vis
		end

		--compute line's y position relative to first line's baseline.
		if last_line ~= nil then
			var baseline_h = line.spaced_ascent - last_line.spaced_descent
			line.y = last_line.y + baseline_h
		end
		last_line = line
	end

	var first_line = lines.array:at(0)
	if first_line ~= nil then
		var last_line = lines.array:at(-1)
		--compute the bounding-box height excluding paragraph spacing.
		lines.h =
			first_line.ascent
			+ last_line.y
			- last_line.descent
		--compute the bounding-box height including paragraph spacing.
		lines.spaced_h =
			first_line.spaced_ascent
			+ last_line.y
			- last_line.spaced_descent
		--set the default visible line range.
		lines.last_visible = lines.array.len-1
	end

	return self
end
