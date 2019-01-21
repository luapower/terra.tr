
setfenv(1, require'tr2_env')
require'tr2_shape'

--TextRenderer ---------------------------------------------------------------

function TextRenderer.metamethods.__cast(from, to, exp)
	if from == niltype or from:isunit() then
		return quote
			var tr = TextRenderer {
				glyph_runs=nil,

				scripts=nil,
				langs=nil,
				bidi_types=nil,
				bracket_types=nil,
				levels=nil,
				linebreaks=nil,
			}
			assert(FT_Init_FreeType(&tr.ft_lib) == 0)
			in tr
		end
	else
		error'invalid cast'
	end
end

terra TextRenderer:free()
	self.glyph_runs:free()

	self.scripts:free()
	self.langs:free()
	self.bidi_types:free()
	self.bracket_types:free()
	self.levels:free()
	self.linebreaks:free()
end

terra TextRenderer:shape_word(glyph_run: &GlyphRun)
	--get the shaped run from cache or shape it and cache it.
	var pair = self.glyph_runs:get(@glyph_run)
	if pair == nil then
		if not glyph_run:shape() then return nil end
		glyph_run:compute_cursors()
		pair = self.glyph_runs:put(@glyph_run, true)
	end
	return &pair.key
end

--test -----------------------------------------------------------------------

terra load_font(self: &Font)
	var f = fopen('media/fonts/OpenSans-Regular.ttf', 'rb')
   if f == nil then return false end
	if fseek(f, 0, SEEK_END) ~= 0 then fclose(f); return false end
	var size = ftell(f)
	if size == -1 then fclose(f); return false end
	rewind(f)
	self.file_data = new(uint8, size)
	var ok = fread(self.file_data, 1, size, f) == size
	if ok then
		self.file_size = size
	else
		self.file_data = nil
	end
	fclose(f)
	return ok
end

terra unload_font(self: &Font)
	free(self.file_data)
	self.file_data = nil
	self.file_size = 0
end

terra test()
	var tr: TextRenderer = nil

	var font: Font
	fill(&font)
	font.tr = &tr
	font.load = load_font
	font.unload = unload_font

	var run: GlyphRun; fill(&run)
	var a = arrayof(uint32, 65, 66, 67)
	run.text = a
	run.text_len = 3
	run.font = &font
	run.font_size = 14
	run.features = nil
	run.num_features = 0
	run.script = HB_SCRIPT_INVALID
	run.lang = nil
	run.rtl = false

	var runp = tr:shape_word(&run)
	assert(runp ~= nil)

	tr:free()
end
test()
