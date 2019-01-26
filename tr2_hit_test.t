
setfenv(1, require'tr2_env')

--hit-test the lines array for a line number given a relative(!) y-coord.
local terra cmp_ys(line1: &Line, line2: &Line)
	return line1.y - line1.spaced_descent < line2.y -- < < [=] = < <
end

terra Lines:line_at_y(y: num)
	if self.array.len == 0 then
		return -1 --no lines
	end
	if y < -self.array(1).spaced_ascent then
		return -1 --above first line
	end
	return self.array:binsearch(Line{y = y}, cmp_ys)
end
