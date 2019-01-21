
--Shaping text runs into an array of segments.

setfenv(1, require'tr2_env')
require'tr2_glyph_run'

local detect_scripts = require'tr2_shape_script'
local lang_for_script = require'tr2_shape_lang'
local reorder_segs = require'tr2_shape_reorder'

local PS = FRIBIDI_CHAR_PS --paragraph separator codepoint
local LS = FRIBIDI_CHAR_LS --line separator codepoint

local terra isnewline(c: codepoint)
	return
		(c >= 10 and c <= 13) --LF, VT, FF, CR
		or c == PS
		or c == LS
		or c == 0x85 --NEL
end

--Is explicit or BN or WS: LRE, RLE, LRO, RLO, PDF, BN, WS?
local FRIBIDI_IS_EXPLICIT_OR_BN_OR_WS = macro(function(p)
	return `(p and (FRIBIDI_MASK_EXPLICIT or FRIBIDI_MASK_BN or FRIBIDI_MASK_WS)) ~= 0
end)

--iterate clusters in RLE-compressed form.
local langs_iter = rle_iterator(arr(hb_language_t),
	macro(function(self, i) return `self(i) end))
TextRenderer.methods.lang_runs = macro(function(self, len)
	return `langs_iter{&self.langs, 0, len}
end)

--for harfbuzz, language is a IETF BCP 47 language code + country code,
--but libunibreak only uses the language code part for a few languages.

terra TextRenderer:init_ub_lang()
	self.HB_LANGUAGE_EN = hb_language_from_string('en', 2)
	self.HB_LANGUAGE_DE = hb_language_from_string('de', 2)
	self.HB_LANGUAGE_ES = hb_language_from_string('es', 2)
	self.HB_LANGUAGE_FR = hb_language_from_string('fr', 2)
	self.HB_LANGUAGE_RU = hb_language_from_string('ru', 2)
	self.HB_LANGUAGE_ZH = hb_language_from_string('zh', 2)
end

terra TextRenderer:ub_lang(hb_lang: hb_language_t): cstring
	    if hb_lang == self.HB_LANGUAGE_EN then return 'en'
	elseif hb_lang == self.HB_LANGUAGE_DE then return 'de'
	elseif hb_lang == self.HB_LANGUAGE_ES then return 'es'
	elseif hb_lang == self.HB_LANGUAGE_FR then return 'fr'
	elseif hb_lang == self.HB_LANGUAGE_RU then return 'ru'
	elseif hb_lang == self.HB_LANGUAGE_ZH then return 'zh'
	else return nil end
end

terra TextRenderer:shape_word(glyph_run: GlyphRun)
	--get the shaped run from cache or shape it and cache it.
	var pair = self.glyph_runs:get(glyph_run)
	if pair == nil then
		if not glyph_run:shape() then return nil end
		glyph_run:compute_cursors()
		pair = self.glyph_runs:put(glyph_run, true)
	end
	return &pair.key
end

terra TextRenderer:shape(text_runs: &TextRuns, segments: &Segs)

	segments.segs:clear()
	--TODO: remove cached values.
	--segments._min_w = false
	--segments._max_w = false
	--segments.lines = false
	if text_runs.runs.len == 0 then return end

	var str = text_runs.codepoints
	var len = text_runs.len

	--detect the script property for each char of the entire text.
	self.scripts:preallocate(len)
	detect_scripts(str, len, self.scripts.elements)
	self.scripts.len = len

	--detect the lang property based on script.
	self.langs:preallocate(len)
	for i = 0, len do
		self.langs.elements[i] = lang_for_script(self.scripts.elements[i])
	end
	self.langs.len = len

	--override scripts and langs with user-provided values.
	for _,run in text_runs.runs do
		if run.script ~= HB_SCRIPT_INVALID then
			for i = 0, run.len do
				self.scripts.elements[run.offset + i] = run.script
			end
		end
		if run.lang ~= nil then
			for i = 0, run.len do
				self.langs.elements[run.offset + i] = run.lang
			end
		end
	end

	--Split text into paragraphs and run fribidi over each paragraph as follows:
	--Skip mirroring since harfbuzz also does that.
	--Skip arabic shaping since harfbuzz does that better with font assistance.
	--Skip RTL reordering because 1) fribidi also reverses the _contents_ of
	--the RTL runs, which harfbuzz also does, and 2) because bidi reordering
	--needs to be done after line breaking and so it's part of layouting.
	self.bidi_types    :preallocate(len)
	self.bracket_types :preallocate(len)
	self.levels        :preallocate(len)

	--flag indicating that bidi reordering will be needed on line-wrapping.
	var reorder_segments = false
	--bidi direction for the first paragraph of the text.
	var base_dir = FRIBIDI_PAR_ON

	if text_runs.runs.len > 0 then

		var text_run_index = -1
		var next_i = 0 --char offset of the next text run
		var par_offset = 0
		var dir: FriBidiParType; --last text run's paragraph's base direction

		for i = 0, len+1 do --NOTE: going one char beyond the text!

			--per-text-run attrs for the current char.
			var dir1 = dir

			--change to the next text run if we're past the current text run.
			--NOTE: the paragraph `dir` is that of the last text run which sets it.
			--NOTE: this runs when i == 0 and when len == 0 but not when i == len.
			if i == next_i then
				text_run_index = text_run_index + 1
				var text_run = text_runs.runs(text_run_index)

				dir1 = iif(text_run.dir ~= FRIBIDI_PAR_ON, text_run.dir, dir)

				next_i = text_run.offset + text_run.len
				next_i = iif(next_i < len, next_i, -1)
			end

			if i == len or (i > 0 and str[i-1] == PS) then

				var par_len = i - par_offset

				if par_len > 0 then

					fribidi_get_bidi_types(
						str + par_offset,
						par_len,
						self.bidi_types:at(par_offset)
					)

					fribidi_get_bracket_types(
						str + par_offset,
						par_len,
						self.bidi_types:at(par_offset),
						self.bracket_types:at(par_offset)
					)

					var max_bidi_level = fribidi_get_par_embedding_levels_ex(
						self.bidi_types:at(par_offset),
						self.bracket_types:at(par_offset),
						par_len,
						&dir,
						self.levels:at(par_offset)
					)
					dec(max_bidi_level)
					assert(max_bidi_level >= 0)

					reorder_segments = reorder_segments
						or max_bidi_level > iif(dir == FRIBIDI_PAR_RTL, 1, 0)

					base_dir = iif(base_dir ~= FRIBIDI_PAR_ON, base_dir, dir)
				end

				par_offset = i
			end

			dir = dir1
		end

	end --if text_runs.runs.len > 0

	--run Unicode line breaking over each run of text with the same language.
	--NOTE: libunibreak always puts a hard break at the end of the text:
	--we don't want that so we're passing it one more codepoint than needed.
	self.linebreaks:preallocate(len + 1)
	for i, len, lang in self:lang_runs(len) do
		set_linebreaks_utf32(str + i, len + 1, self:ub_lang(lang), self.linebreaks:at(i))
	end

	--split the text into segments of characters with the same properties,
	--shape the segments individually and cache the shaped results.
	--the splitting is two-level: each text segment that requires separate
	--shaping can contain sub-segments that require separate styling.

	segments.text_runs = text_runs --for accessing codepoints by clients
	segments.bidi = reorder_segments --for optimization
	segments.base_dir = base_dir

	var seg_count = 0
	var line_num = 1

	var text_run_index = -1
	var next_i = 0 --char offset of the next text run

	--per-text-run attrs
	var text_run: &TextRun
	var font: &Font
	var font_size: float
	var features: &hb_feature_t

	--per-char attrs
	var level: int8
	var script: hb_script_t
	var lang: hb_language_t

	var seg_offset = 0 --curent segment's offset in text
	var sub_offset = 0 --current sub-segment's relative text offset
	self.substack:clear()

	for i = 0, len+1 do --NOTE: going one char beyond the text!

		--per-text-run attts for the current char.
		var text_run1: &TextRun;
		var font1: &Font;
		var font_size1: float;
		var features1: &hb_feature_t;

		--change to the next text run if we're past the current text run.
		--NOTE: this runs when i == 0 and when len == 0 but not when i == len.
		if i == next_i then

			text_run_index = text_run_index + 1
			text_run1 = text_runs.runs:at(text_run_index)

			font1 = text_run1.font
			font_size1 = text_run1.font_size
			features1 = text_run1.features

			next_i = text_run1.offset + text_run1.len
			next_i = iif(next_i < len, next_i, -1)

		elseif i < len then

			--use last char's attrs.
			text_run1 = text_run
			font1 = font
			font_size1 = font_size
			features1 = features

		end

		--per-char attrs for the current char.
		var level1: int8
		var script1: hb_script_t
		var lang1: hb_language_t
		if len == 0 then

			--the string is empty so init those with defaults.
			level1 = iif(text_run1.dir == FRIBIDI_PAR_RTL, 1, 0)
			script1 = iif(text_run1.script ~= HB_SCRIPT_INVALID, text_run1.script, HB_SCRIPT_COMMON)
			lang1 = text_run1.lang

		elseif i < len then

			level1 = self.levels(i)
			script1 = self.scripts(i)
			lang1 = self.langs(i)

		end

		--init last char's state on first iteration. this works both to prevent
		--making a first empty segment and to provide state for when len == 0.
		if i == 0 then

			text_run = text_run1
			font = font1
			font_size = font_size1
			features = features1

			level = level1
			script = script1
			lang = lang1

			if len == 0 then
				font1 = nil --force making a new segment
			end
		end

		--unicode line breaking: 0: required, 1: allowed, 2: not allowed.
		var linebreak_code = iif(i > 0, self.linebreaks(i-1), 2)

		--check if any attributes that require a new segment have changed.
		var new_segment =
			linebreak_code < 2
			or font1 ~= font
			or font_size1 ~= font_size
			or features1 ~= features
			or level1 ~= level
			or script1 ~= script
			or lang1 ~= lang

		--check if any attributes that require a new sub-segment have changed.
		var new_subsegment =
			new_segment
			or text_run1 ~= text_run

		if new_segment then

			::again::

			var seg_len = i - seg_offset
			var rtl = (level and 1) == 1

			--find the segment length without trailing linebreak chars.
			--NOTE: this can result in seg_len == 0, which is still valid.
			for i = seg_offset + seg_len-1, seg_offset, -1 do
				if isnewline(str[i]) then
					seg_len = seg_len - 1
				else
					break
				end
			end

			--find if the segment has a trailing space char.
			var trailing_space = seg_len > 0
				and FRIBIDI_IS_EXPLICIT_OR_BN_OR_WS(self.bidi_types(seg_offset + seg_len-1))

			--shape the segment excluding trailing linebreak chars.
			var glyph_run = self:shape_word(GlyphRun {
				text = str + seg_offset;
				text_len = seg_len;
				trailing_space = trailing_space;
				font = font;
				font_size = font_size;
				features = features;
				rtl = rtl;
				script = script;
				lang = lang;
			})

			--2: paragraph, 1: line, 0: softbreak
			var linebreak = iif(linebreak_code == 0, iif(str[i-1] == PS, 2, 1), 0)

			if glyph_run ~= nil then --font loaded successfully

				seg_count = seg_count + 1

				var segment = segments.segs:ensure(seg_count)
				assert(segment ~= nil) --TODO: failure case

				segment.glyph_run = glyph_run
				--for line breaking
				segment.linebreak = linebreak --hard break
				--for bidi reordering
				segment.bidi_level = level
				--for cursor positioning
				segment.text_run = text_run --text run of the last sub-segment
				segment.offset = seg_offset
				segment.index = seg_count
				--slots filled by layouting
				segment.x = false; segment.advance_x = false --segment's x-axis boundaries
				segment.next = false --next segment on the same line in text order
				segment.next_vis = false --next segment on the same line in visual order
				segment.line = false
				segment.line_num = line_num --physical line number
				segment.wrapped = false --segment is the last on a wrapped line
				segment.visible = true --segment is not entirely clipped

				--add sub-segments from the sub-segment stack and empty the stack.
				if self.substack.len > 0 then
					var last_sub_len = seg_len - sub_offset
					var sub_offset = 0
					var glyph_i = 0
					var clip_left, clip_right = false, false --from run's origin
					for i = 1, substack_n + 1, 2 do
						var sub_len, sub_text_run
						if i < substack_n  then
							sub_len, sub_text_run = substack[i], substack[i+1]
						else --last iteration outside the stack for last sub-segment
							sub_len, sub_text_run = last_sub_len, text_run
						end

						--adjust `next_sub_offset` to a grapheme position.
						var next_sub_offset = sub_offset + sub_len
						assert(next_sub_offset >= 0)
						assert(next_sub_offset <= seg_len)
						var next_sub_offset = glyph_run.cursor_offsets[next_sub_offset]
						var sub_len = next_sub_offset - sub_offset

						if sub_len == 0 then
							break
						end

						--find the last sub's glyph which is before any glyph which
						--*starts* representing the graphemes at `next_sub_offset`,
						--IOW the last glyph with a cluster value < `next_sub_offset`.

						var last_glyph_i

						if rtl then

							last_glyph_i = (binsearch(
								next_sub_offset, glyph_run.info,
								cmp_clusters_reverse,
								glyph_i, 0
							) or -1) + 1

							assert(last_glyph_i >= 0)
							assert(last_glyph_i < glyph_run.len)

							--check whether the last glyph represents additional graphemes
							--beyond the current sub-segment, if so we have to clip it.
							var next_cluster =
								last_glyph_i > 0
								and glyph_run.info[last_glyph_i-1].cluster
								or 0

							clip_left = next_cluster > next_sub_offset
							clip_left = clip_left and glyph_run.cursor_xs[next_sub_offset]

							push(segment, glyph_i)
							push(segment, last_glyph_i)
							push(segment, sub_text_run)
							push(segment, clip_left)
							push(segment, clip_right)

							sub_offset = next_sub_offset
							glyph_i = last_glyph_i - (clip_left and 0 or 1)
							clip_right = clip_left

						else --ltr

							last_glyph_i = (binsearch(
								next_sub_offset, glyph_run.info,
								cmp_clusters,
								glyph_i, glyph_run.len-1
							) or glyph_run.len) - 1

							assert(last_glyph_i >= 0)
							assert(last_glyph_i < glyph_run.len)

							--check whether the last glyph represents additional graphemes
							--beyond the current sub-segment, if so we have to clip it.
							var next_cluster =
								last_glyph_i < glyph_run.len-1
								and glyph_run.info[last_glyph_i+1].cluster
								or seg_len

							clip_right = next_cluster > next_sub_offset
							clip_right = clip_right and glyph_run.cursor_xs[next_sub_offset]

							push(segment, glyph_i)
							push(segment, last_glyph_i)
							push(segment, sub_text_run)
							push(segment, clip_left)
							push(segment, clip_right)

							sub_offset = next_sub_offset
							glyph_i = last_glyph_i + (clip_right and 0 or 1)
							clip_left = clip_right

						end

					end --for each subsegment
					self.substack:clear() --empty the stack
				end --if subsegments

			end --if glyph_run

			if linebreak then
				line_num = line_num + 1
			end

			seg_offset = i
			sub_offset = 0

			--if the last segment ended with a hard line break, add another
			--empty segment at the end, in order to have a cursor on the last
			--empty line.
			if i == len and linebreak then
				linebreak_code = 2 --prevent recursion
				goto again
			end

		elseif new_subsegment then

			var sub_len = i - (seg_offset + sub_offset)
			substack = substack or {}
			substack[substack_n + 1] = sub_len
			substack[substack_n + 2] = text_run
			substack_n = substack_n + 2

			sub_offset = sub_offset + sub_len
		end

		--update last char state with current char state.
		text_run = text_run1
		font = font1
		font_size = font_size1
		features = features1

		level = level1
		script = script1
		lang = lang1

	end --for i = 0, len+1
end

