
--Shaping a single word into an array of glyphs.

setfenv(1, require'tr2_types')

terra GlyphRun:shape(
	str: &uint32,
	str_len: int,
	font: &Font,
	font_size: float,
	script: hb_script_t,
	lang: hb_language_t,
	features: &hb_feature_t,
	num_features: int,
	rtl: bool
)
	--if not font:ref() then return end
	--font:setsize(font_size)

	var hb_dir = iif(rtl, HB_DIRECTION_RTL, HB_DIRECTION_LTR)
	var hb_buf = hb_buffer_create()
	hb_buffer_set_cluster_level(hb_buf,
		--HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS
		HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES
		--HB_BUFFER_CLUSTER_LEVEL_CHARACTERS
	)
	hb_buffer_set_direction(hb_buf, hb_dir)
	hb_buffer_set_script(hb_buf, script)
	hb_buffer_set_language(hb_buf, lang)
	hb_buffer_add_codepoints(hb_buf, str, str_len, 0, str_len)
	hb_shape(font.hb_font, hb_buf, features, num_features)

	self.len  = hb_buffer_get_length(hb_buf)
	self.info = hb_buffer_get_glyph_infos(hb_buf, nil)
	self.pos  = hb_buffer_get_glyph_positions(hb_buf, nil)

	self.hb_buf = hb_buf --anchor it
	self.font = font --anchor it; also for glyph rasterization
	self.font_size = font_size --for glyph rasterization
	self.text_len = str_len --for how many cursors to allocate
	self.rtl = rtl --for cursors

	--1. scale advances and offsets based on `font.scale` (for bitmap fonts).
	--2. make the advance of each glyph relative to the start of the run
	--   so that pos_x() is O(1) for any index.
	--3. compute the run's total advance.
	var ax: int = 0
	for i = 0, self.len do
		ax = (ax + self.pos[i].x_advance) * font.scale
		self.pos[i].x_offset = self.pos[i].x_offset * font.scale
		self.pos[i].x_advance = ax
	end
	self.advance_x = [float](ax) / 64 --for positioning in horizontal flow

	--for lru cache
	self.mem_size =
		sizeof(GlyphRun)
		+ (sizeof(hb_glyph_info_t) + sizeof(hb_glyph_position_t)) * self.len
		+ (sizeof(int16) + sizeof(float)) * (str_len + 1) --cursors

end

function GlyphRun:free()
	--hb_buffer_free(self.hb_buf)
	--self.font:unref()
	fill(self)
end

--iterate clusters in RLE-compressed form.
local struct Clusters {
	run: &GlyphRun;
}
function Clusters.metamethods.__for(self, body)
	return quote
		var c0: uint32 = self.info[0].cluster
		var i0 = 0
		for i = 0, self.len do
			var c = self.info[i].cluster
			if c ~= c0 then
				[ body(i0, i - i0, c0) ]
				c0 = c
				i0 = i
			end
		end
		[ body(i0, self.len - i0, c0) ]
	end
end

local alloc_grapheme_breaks = global(growbuffer(int8))

local terra count_graphemes(grapheme_breaks: &int8, start: int, len: int)
	var n = 0
	for i = start, start+len do
		if grapheme_breaks[i] == 0 then
			n = n + 1
		end
	end
	return n
end

local terra next_grapheme(grapheme_breaks: &int8, i: int, len: int)
	while grapheme_breaks[i] ~= 0 do
		i = i + 1
	end
	i = i + 1
	check(i < len)
	return i
end

local alloc_carets_buffer = global(growbuffer(hb_position_t))

local get_ligature_carets = macro(function(
	hb_font, direction, glyph_index
)
	return quote
		var count = hb_ot_layout_get_ligature_carets(hb_font, direction,
			glyph_index, 0, nil, nil)
		var carets_buf = alloc_carets_buffer(count)
		var count_buf: uint
		hb_ot_layout_get_ligature_carets(hb_font, direction, glyph_index,
			0, &count_buf, carets_buf)
	in
		carets_buf, count_buf
	end
end)

terra GlyphRun:pos_x(i: int)
	check(i >= 0)
	check(i <= self.len)
	return iif(i > 0, self.pos[i-1].x_advance / 64, 0)
end

terra GlyphRun:_add_cursors(
	glyph_offset: int,
	glyph_len: int,
	cluster: int,
	cluster_len: int,
	cluster_x: float,
	--closure environment
	str: &uint32,
	str_len: int
)
	self.cursor_offsets[cluster] = cluster
	self.cursor_xs[cluster] = cluster_x
	if cluster_len <= 1 then return end

	--the cluster is made of multiple codepoints. check how many
	--graphemes it contains since we need to add additional cursor
	--positions at each grapheme boundary.
	var grapheme_breaks = alloc_grapheme_breaks(str_len)
	var lang = nil --not used in current libunibreak impl.
	set_graphemebreaks_utf32(str, str_len, lang, grapheme_breaks)
	var grapheme_count =
		count_graphemes(grapheme_breaks, cluster, cluster_len)
	if grapheme_count <= 1 then return end

	--the cluster is made of multiple graphemes, which can be the
	--result of forming ligatures, which the font can provide carets
	--for. missing ligature carets, we divide the combined x-advance
	--of the glyphs evenly between graphemes.
	for i = glyph_offset, glyph_offset + glyph_len - 1 do
		var glyph_index = self.info[i].codepoint
		var cluster_x = self:pos_x(i)
		var carets, caret_count =
			get_ligature_carets(
				self.font.hb_font,
				iif(self.rtl, HB_DIRECTION_RTL, HB_DIRECTION_LTR),
				glyph_index)
		if caret_count > 0 then
			-- there shouldn't be more carets than grapheme_count-1.
			caret_count = min(caret_count, grapheme_count - 1)
			--add the ligature carets from the font.
			for i = 0, caret_count-1 do
				--create a synthetic cluster at each grapheme boundary.
				cluster = next_grapheme(grapheme_breaks, cluster, str_len)
				var lig_x = carets[i] / 64
				self.cursor_offsets[cluster] = cluster
				self.cursor_xs[cluster] = cluster_x + lig_x
			end
			--infer the number of graphemes in the glyph as being
			--the number of ligature carets in the glyph + 1.
			grapheme_count = grapheme_count - (caret_count + 1)
		else
			--font doesn't provide carets: add synthetic carets by
			--dividing the total x-advance of the remaining glyphs
			--evenly between remaining graphemes.
			var next_i = glyph_offset + glyph_len
			var total_advance_x = self:pos_x(next_i) - self:pos_x(i)
			var w = total_advance_x / grapheme_count
			for i = 1, grapheme_count-1 do
				--create a synthetic cluster at each grapheme boundary.
				cluster = next_grapheme(grapheme_breaks, cluster, str_len)
				var lig_x = i * w
				self.cursor_offsets[cluster] = cluster
				self.cursor_xs[cluster] = cluster_x + lig_x
			end
			grapheme_count = 0
		end
		if grapheme_count == 0 then
			break --all graphemes have carets
		end
	end
end

--[==[

--	self.trailing_space = trailing_space
--	rtl: bool,
--	trailing_space: bool,

local glyph_count = symbol(int)
local glyph_pos = symbol(&hb_glyph_position_t)

local function cmp_clusters(glyph_info, i, cluster)
	return glyph_info[i].cluster < cluster -- < < [=] = < <
end

local function cmp_clusters_reverse(glyph_info, i, cluster)
	return cluster < glyph_info[i].cluster -- < < [=] = < <
end

]==]

terra GlyphRun:compute_cursors()

	var cursor_offsets = new(int16, str_len + 1) --in logical order
	var cursor_xs = new(float, len + 1) --in logical order
	for i = 0, len+1 do
		cursor_offsets[i] = -1 --invalid offset, fixed later
	end
	self.cursor_offsets = cursor_offsets --0..text_len
	self.cursor_xs = cursor_xs --0..text_len

	var grapheme_breaks: &int8 --allocated on demand for multi-codepoint clusters

	if rtl then
		--add last logical (first visual), after-the-text cursor
		cursor_offsets[len] = len
		cursor_xs[len] = 0
		var i: int --index in glyph_info
		var n: int --glyph count
		var c: int --cluster
		var cn: int --cluster len
		var cx: float --cluster x
		c = len
		for i1, n1, c1 in Clusters{self} do
			cx = pos_x(i1)
			if i then
				add_cursors(i, n, c, cn, cx)
			end
			var cn1 = c - c1
			i, n, c, cn = i1, n1, c1, cn1
		end
		if i then
			cx = ax
			add_cursors(i, n, c, cn, cx)
		end
	else
		var i: int --index in glyph_info
		var n: int --glyph count
		var c: int --cluster
		var cx: float --cluster x
		for i1, n1, c1 in rle_runs(glyph_info, glyph_count, get_cluster) do
			if c then
				var cn = c1 - c
				add_cursors(i, n, c, cn, cx)
			end
			var cx1 = pos_x(i1)
			i, n, c, cx = i1, n1, c1, cx1
		end
		if i then
			var cn = len - c
			add_cursors(i, n, c, cn, cx)
		end
		--add last logical (last visual), after-the-text cursor
		cursor_offsets[len] = len
		cursor_xs[len] = ax
	end

	--add cursor offsets for all codepoints which are missing one.
	if grapheme_breaks then --there are clusters with multiple codepoints.
		var c, x --cluster, cluster x.
		for i = 0, len do
			if cursor_offsets[i] == -1 then
				cursor_offsets[i] = c
				cursor_xs[i] = x
			else
				c = cursor_offsets[i]
				x = cursor_xs[i]
			end
		end
	end

	--compute `wrap_advance_x` by removing the advance of the trailing space.
	var wx = ax
	if trailing_space then
		var i = rtl and 0 or glyph_count-1
		assert(glyph_info[i].cluster == len-1)
		wx = wx - (pos_x(i+1) - pos_x(i))
	end
end

--[==[
terra glyph_run(
	str: &uint32,
	str_offset: int,
	len: int,
	trailing_space: bool,
	font: &Font,
	font_size: float,
	features: &hb_feature_t,
	rtl: bool,
	script: hb_script_t,
	lang: hb_language_t
)
	--if not font:ref() then return end

	--[[
	--compute cache key for this run.
	var text = ffi.string(str + str_offset, 4 * len)
	var lang_id = tonumber(lang) or false
	var key = font.tuple(text, font_size, rtl, script, lang_id)

	--get the shaped run from cache or shape it and cache it.
	var glyph_run = self.glyph_runs:get(key)
	if not glyph_run then
		glyph_run = self:shape_word(
			str, str_offset, len, trailing_space,
			font, font_size, features,
			rtl, script, lang
		)
		self.glyph_runs:put(key, glyph_run)
	end
	]]

	--font:unref()
	return glyph_run
end

]==]
