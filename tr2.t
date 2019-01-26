
--Text shaping & rendering engine for Terra.
--Written by Cosmin Apreutesei. Public Domain.

--This is a port of github.com/luapower/tr which was written in Lua.
--Leverages harfbuzz, freetype, fribidi and libunibreak.
--A module for blitting the rasterized text onto a Cairo surface is included.

setfenv(1, require'tr2_env')
require'tr2_paint_cairo'
require'tr2_shape'
require'tr2_linewrap'
require'tr2_align'
require'tr2_clip'
require'tr2_rasterize'
require'tr2_paint'

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

				glyph_cache_size = 1024^2 * 10, --10MB net (arbitrary default)
				font_size_resolution = 1/8,     --in pixels
				subpixel_x_resolution = 1/16,   --1/64 pixels is max with freetype
				subpixel_y_resolution = 1,      --no subpixel positioning with vertical hinting

				glyphs=nil,
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
	self.glyphs:free()
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

return tr
