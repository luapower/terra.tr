
setfenv(1, require'trlib_types')

--hit-test the lines array for a line number given a relative(!) y-coord.
local terra cmp_ys(line1: &Line, line2: &Line)
	return line1.y - line1.spaced_descent < line2.y -- < < [=] = < <
end

terra Layout:line_at_y(y: num)
	if self.lines.len == 0 then
		return -1 --no lines
	end
	if y < -self.lines(0).spaced_ascent then
		return -1 --above first line
	end
	return self.lines:binsearch(Line{y = y}, cmp_ys)
end
