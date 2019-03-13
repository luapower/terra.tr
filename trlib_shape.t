
--Shaping text runs into an array of segments.

if not ... then require'trlib_test'; return end

setfenv(1, require'trlib_types')
require'trlib_shape_word'
require'trlib_rle'

local detect_scripts = require'trlib_shape_detect_script'
local lang_for_script = require'trlib_shape_detect_lang'

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

--iterate text segments with the same language.

local lang1 = symbol(hb_language_t)
local lang0 = symbol(hb_language_t)

local langs_iter = rle_iterator{
	state = &arr(hb_language_t),
	for_variables = {lang0},
	declare_variables = function()        return quote var [lang1], [lang0] end end,
	save_values       = function()        return quote lang0 = lang1 end end,
	load_values       = function(self, i) return quote lang1 = self(i) end end,
	values_different  = function()        return `lang0 ~= lang1 end,
}

TextRenderer.methods.lang_runs = macro(function(self, len)
	return `langs_iter{&self.langs, 0, len}
end)

--iterate paragraphs (empty paragraphs are kept separate).

local c0 = symbol(codepoint)
local c1 = symbol(codepoint)

local para_iter = rle_iterator{
	state = &TextRuns,
	for_variables = {},
	declare_variables = function()        return quote var [c0], [c1] end end,
	save_values       = function()        return quote c0 = c1 end end,
	load_values       = function(self, i) return quote c1 = self.text.elements[i] end end,
	values_different  = function()        return `c0 == PS end,
}

TextRuns.methods.paragraphs = macro(function(self)
	return `para_iter{&self, 0, self.text.len}
end)

--iterate text segments having the same shaping-relevant properties.

local word_iter_state = struct {
	text_runs: &TextRuns;
	levels: &FriBidiLevel;
	scripts: &hb_script_t;
	langs: &hb_language_t;
	linebreaks: &char;
}

local iter = {state = word_iter_state}

local tr_index   = symbol(int)
local tr_eof     = symbol(int)
local tr_diff    = symbol(bool)
local tr0        = symbol(&TextRun)
local tr1        = symbol(&TextRun)
local level0     = symbol(FriBidiLevel)
local level1     = symbol(FriBidiLevel)
local script0    = symbol(hb_script_t)
local script1    = symbol(hb_script_t)
local lang0      = symbol(hb_language_t)
local lang1      = symbol(hb_language_t)

iter.for_variables = {tr0, tr1, level0, script0, lang0}

iter.declare_variables = function(self)
	return quote
		var [tr_index] = -1
		var [tr_eof] = 0
		var [tr_diff] = false
		var [tr0], [level0], [script0], [lang0]
		var [tr1], [level1], [script1], [lang1]
		tr0 = nil
	end
end

iter.save_values = function()
	return quote
		tr0, level0, script0, lang0 =
		tr1, level1, script1, lang1
	end
end

iter.load_values = function(self, i)
	return quote
		level1     = self.levels[i]
		script1    = self.scripts[i]
		lang1      = self.langs[i]
		if i >= tr_eof then --time to load a new text run
			inc(tr_index)
			tr_eof = self.text_runs:eof(tr_index)
			tr1 = self.text_runs.array:at(tr_index)
			tr_diff = tr0 == nil
				or tr1.font      ~= tr0.font
				or tr1.font_size ~= tr0.font_size
				or tr1.features  ~= tr0.features
		else
			tr_diff = false
		end
	end
end

iter.values_different = function(self, i)
	return `
		tr_diff
		or self.linebreaks[i-1] < 2 --0: required, 1: allowed, 2: not allowed
		or level1  ~= level0
		or script1 ~= script0
		or lang1   ~= lang0
end

local word_iter = rle_iterator(iter)

TextRuns.methods.word_runs = macro(function(self, levels, scripts, langs, linebreaks)
	return `word_iter{
		word_iter_state{
			text_runs = &self,
			levels = levels,
			scripts = scripts,
			langs = langs,
			linebreaks = linebreaks
		}, 0, self.text.len}
end)

--search for the text run that is spanning over a specific text position.

terra TextRuns:run_index_at_offset(offset: int, i0: int)
	for i = i0 + 1, self.array.len do
		if self.array:at(i).offset > offset then
			return i-1
		end
	end
	return self.array.len-1
end

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

terra TextRenderer:ub_lang(hb_lang: hb_language_t): rawstring
	    if hb_lang == self.HB_LANGUAGE_EN then return 'en'
	elseif hb_lang == self.HB_LANGUAGE_DE then return 'de'
	elseif hb_lang == self.HB_LANGUAGE_ES then return 'es'
	elseif hb_lang == self.HB_LANGUAGE_FR then return 'fr'
	elseif hb_lang == self.HB_LANGUAGE_RU then return 'ru'
	elseif hb_lang == self.HB_LANGUAGE_ZH then return 'zh'
	else return nil end
end

terra TextRenderer:shape(text_runs: &TextRuns, segs: &Segs)

	for _,seg in segs.array do
		seg.subsegs:free()
	end
	segs.array.len = 0
	--remove cached values.
	segs.lines.array.len = 0
	segs._min_w = -inf
	segs._max_w =  inf
	if text_runs.array.len == 0 then
		return
	end

	var str = text_runs.text.elements
	var len = text_runs.text.len

	--script and language detection and assignment
	self.scripts.len = len
	self.langs.len = len

	--script/lang detection is expensive: see if we can avoid it.
	var do_detect_scripts = false
	var do_detect_langs = false
	for run_index, run in text_runs.array do
		if run.script == HB_SCRIPT_COMMON then do_detect_scripts = true end
		if run.lang == nil then do_detect_langs = true end
		if do_detect_scripts and do_detect_langs then break end
	end

	--detect the script property for each char of the entire text.
	if do_detect_scripts then
		detect_scripts(self, str, len, self.scripts.elements)
	end

	--override scripts with user-provided values.
	for run_index, run in text_runs.array do
		if run.script ~= HB_SCRIPT_COMMON then
			for i = run.offset, text_runs:eof(run_index) do
				self.scripts.elements[i] = run.script
			end
		end
	end

	--detect the lang property based on the script property.
	if do_detect_langs then
		for i = 0, len do
			self.langs.elements[i] = lang_for_script(self.scripts.elements[i])
		end
	end

	--override langs with user-provided values.
	for run_index, run in text_runs.array do
		if run.lang ~= nil then
			for i = run.offset, text_runs:eof(run_index) do
				self.langs.elements[i] = run.lang
			end
		end
	end

	--Split text into paragraphs and run fribidi over each paragraph as follows:
	--Skip mirroring since harfbuzz also does that.
	--Skip arabic shaping since harfbuzz does that better with font assistance.
	--Skip RTL reordering because 1) fribidi also reverses the _contents_ of
	--the RTL runs, which harfbuzz also does, and 2) because bidi reordering
	--needs to be done after line breaking and so it's part of layouting.

	self.bidi_types    .len = len
	self.bracket_types .len = len
	self.levels        .len = len

	segs.bidi = false --is bidi reordering needed on line-wrapping or not?
	segs.base_dir = DIR_AUTO --bidi direction of the first paragraph of the text.

	var text_run_index = 0
	for offset, len in text_runs:paragraphs() do
		var str = str + offset

		text_run_index = text_runs:run_index_at_offset(offset, text_run_index)
		var text_run = text_runs.array:at(text_run_index)

		--the text run that starts exactly where the paragraph starts can set
		--the paragraph base direction, otherwise it is auto-detected.
		var dir = iif(text_run.offset == offset, text_run.dir, DIR_AUTO)

		fribidi_get_bidi_types(str, len, self.bidi_types:at(offset))

		fribidi_get_bracket_types(str, len,
			self.bidi_types:at(offset),
			self.bracket_types:at(offset))

		var max_bidi_level = fribidi_get_par_embedding_levels_ex(
			self.bidi_types:at(offset),
			self.bracket_types:at(offset),
			len,
			&dir,
			self.levels:at(offset)) - 1

		assert(max_bidi_level >= 0)

		segs.bidi = segs.bidi
			or max_bidi_level > iif(dir == DIR_RTL, 1, 0)

		if segs.base_dir == 0 then --take the dir of the first paragraph
			segs.base_dir = dir
		end
	end

	--Run Unicode line breaking over each run of text with the same language.
	--NOTE: libunibreak always puts a hard break at the end of the text.
	--We don't want that so we're passing it one more codepoint than needed.

	self.linebreaks.len = len + 1
	for offset, len, lang in self:lang_runs(len) do
		set_linebreaks_utf32(str + offset, len + 1,
			self:ub_lang(lang), self.linebreaks:at(offset))
	end

	--Split the text into segs of characters with the same properties,
	--shape the segs individually and cache the shaped results.
	--The splitting is two-level: each text seg that requires separate
	--shaping can contain sub-segs that require separate styling.
	--NOTE: Empty segs (len=0) are valid.

	var line_num = 0

	for offset, len, tr, tr1, level, script, lang in text_runs:word_runs(
		self.levels.elements,
		self.scripts.elements,
		self.langs.elements,
		self.linebreaks.elements
	) do
		var str = str + offset

		--find the seg length without trailing linebreak chars.
		while len > 0 and isnewline(str[len-1]) do
			dec(len)
		end

		--find if the seg has a trailing space char.
		var trailing_space = len > 0
			and FRIBIDI_IS_EXPLICIT_OR_BN_OR_WS(self.bidi_types(offset+len-1))

		--shape the seg excluding trailing linebreak chars.
		var gr = GlyphRun {
			text      = arr(codepoint);
			font      = tr.font;
			font_size = tr.font_size;
			features  = tr.features;
			script    = script;
			lang      = lang;
			rtl       = isodd(level);
			trailing_space = trailing_space;
		}
		assert(gr.text.elements == nil)
		gr.text.view = arrview(str, len)
		var glyph_run = self:shape_word(gr)

		--UBA codes: 0: required, 1: allowed, 2: not allowed.
		var linebreak_code = iif(offset > 0, self.linebreaks(offset-1), 2)
		--user codes: 2: paragraph, 1: line, 0: softbreak.
		var linebreak = iif(linebreak_code == 0,
			iif(str[-1] == PS, BREAK_PARA, BREAK_LINE), BREAK_NONE)
		if linebreak ~= BREAK_NONE then inc(line_num) end

		if glyph_run ~= nil then --font loaded successfully
			var seg = segs.array:add()
			assert(seg ~= nil)
			seg.glyph_run = glyph_run
			seg.line_num = line_num --physical line number (unused)
			seg.linebreak = linebreak --for line breaking
			seg.bidi_level = level --for bidi reordering
			--for cursor positioning
			seg.text_run = tr --text run of the first sub-seg
			seg.offset = offset
			--slots filled by layouting
			seg.x = 0; seg.advance_x = 0 --seg's x-axis boundaries
			seg.next = nil--next seg on the same line in text order
			seg.next_vis = nil --next seg on the same line in visual order
			seg.line = nil
			seg.wrapped = false --seg is the last on a wrapped line
			seg.visible = true --seg is not entirely clipped
		end

	end

end
