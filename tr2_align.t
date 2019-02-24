
--Fit line-wrapped text inside a box.

setfenv(1, require'tr2_env')

terra Segs:align(x: num, y: num, w: num, h: num, align_x: enum, align_y: enum)

	var lines = self.lines
	if lines.array.len == 0 then return self end
	if w == -1 then w = lines.max_ax end   --self-box
	if h == -1 then h = lines.spaced_h end --self-box

	lines.min_x = inf

	if align_x == ALIGN_AUTO then
		    if self.base_dir == DIR_AUTO then align_x = ALIGN_LEFT
		elseif self.base_dir == DIR_LTR  then align_x = ALIGN_LEFT
		elseif self.base_dir == DIR_RTL  then align_x = ALIGN_RIGHT
		elseif self.base_dir == DIR_WLTR then align_x = ALIGN_LEFT
		elseif self.base_dir == DIR_WRTL then align_x = ALIGN_RIGHT
		end
	end

	for line_i, line in lines.array do
		--compute line's aligned x position relative to the textbox origin.
		if align_x == ALIGN_RIGHT then
			line.x = w - line.advance_x
		elseif align_x == ALIGN_CENTER then
			line.x = (w - line.advance_x) / 2.0
		end
		lines.min_x = min(lines.min_x, line.x)
	end

	--compute first line's baseline based on vertical alignment.
	var first_line = lines.array:at(1)
	var last_line  = lines.array:at(-1)
	if first_line == nil then
		lines.baseline = 0
	else
		if align_y == ALIGN_TOP then
			lines.baseline = first_line.spaced_ascent
		else
			if align_y == ALIGN_BOTTOM then
				lines.baseline = h - (last_line.y - last_line.spaced_descent)
			elseif align_y == ALIGN_CENTER then
				lines.baseline = first_line.spaced_ascent + (h - lines.spaced_h) / 2
			end
		end
	end

	--store textbox's origin, which can be changed anytime after layouting.
	lines.x = x
	lines.y = y

	--store textbox's height to be used for page up/down cursor navigation.
	self.page_h = h

	--store the actual x-alignment for adjusting the caret x-coord.
	lines.align_x = align_x

	if lines.clip_valid then
		--must reset clip on paint() if clip() won't be called until paint().
		lines.clip_valid = false
	end

	return self
end
