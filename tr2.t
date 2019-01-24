
setfenv(1, require'tr2_env')
require'tr2_shape'
require'tr2_wrap'
require'tr2_align'

--TextRuns -------------------------------------------------------------------


function TextRuns.metamethods.__cast(from, to, exp)
	if from == niltype or from:isunit() then
		return `TextRuns {runs = nil, codepoints = nil, len = 0}
	else
		error'invalid cast'
	end
end

function TextRun.metamethods.__cast(from, to, exp)
	if from == niltype or from:isunit() then
		return `TextRun {
			offset = 0,
			font = nil,
			font_size = 0,
			features = nil,
			num_features = 0,
			script = HB_SCRIPT_COMMON,
			lang = nil,
			dir = DIR_AUTO,
			line_spacing = 1,
			hardline_spacing = 1,
			paragraph_spacing = 2,
			nowrap = false,
			color = {0, 0, 0, 1},
			opacity = 1,
			operator = 0 --CAIRO_OPERATOR_OVER
		}
	else
		error'invalid cast'
	end
end

--TextRenderer ---------------------------------------------------------------

function TextRenderer.metamethods.__cast(from, to, exp)
	if from == niltype or from:isunit() then
		return quote
			var self = TextRenderer {
				glyph_runs=nil,
				cpstack=nil,
				scripts=nil,
				langs=nil,
				bidi_types=nil,
				bracket_types=nil,
				levels=nil,
				linebreaks=nil,
				grapheme_breaks=nil,
				carets_buffer=nil,
				substack=nil,
				ranges=nil,
			}
			assert(self.ranges:preallocate(64))
			assert(self.cpstack:preallocate(64))
			assert(FT_Init_FreeType(&self.ft_lib) == 0)
			self:init_ub_lang()
			in self
		end
	else
		error'invalid cast'
	end
end

terra TextRenderer:free()
	self.glyph_runs:free()
	self.cpstack:free()
	self.scripts:free()
	self.langs:free()
	self.bidi_types:free()
	self.bracket_types:free()
	self.levels:free()
	self.linebreaks:free()
	self.grapheme_breaks:free()
	self.carets_buffer:free()
	self.substack:free()
	self.ranges:free()
	FT_Done_FreeType(self.ft_lib)
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

	var runs: TextRuns = nil
	runs.len = 5
	runs.codepoints = new(codepoint, 3)
	runs.codepoints[0] = 65
	runs.codepoints[1] = 66
	runs.codepoints[2] = 67
	var r = TextRun(nil)
	r.offset = 0
	r.font = &font
	r.font_size = 14
	runs.runs:push(r)

	free(runs.codepoints)

	--[[
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
	]]

	tr:free()
end
test()
