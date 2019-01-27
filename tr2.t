
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

terra TextRenderer:init()
	fill(self)
	self.glyph_cache_size = 1024^2 * 10 --10MB net (arbitrary default)
	self.font_size_resolution = 1/8     --in pixels
	self.subpixel_x_resolution = 1/16   --1/64 pixels is max with freetype
	self.subpixel_y_resolution = 1      --no subpixel positioning with vertical hinting
	self.glyphs:init()
	self.glyph_runs:init()
	self.cpstack:init()
	self.scripts:init()
	self.langs:init()
	self.bidi_types:init()
	self.bracket_types:init()
	self.levels:init()
	self.linebreaks:init()
	self.grapheme_breaks:init()
	self.carets_buffer:init()
	self.substack:init()
	self.ranges:init()
	assert(self.ranges:preallocate(64))
	assert(self.cpstack:preallocate(64))
	assert(FT_Init_FreeType(&self.ft_lib) == 0)
	self:init_ub_lang()
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
	fill(self)
end

return tr
