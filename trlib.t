
--Text shaping & rendering engine for Terra.
--Written by Cosmin Apreutesei. Public Domain.

--This is a port of github.com/luapower/tr which was written in Lua.
--Leverages harfbuzz, freetype, fribidi and libunibreak.
--A module for blitting the rasterized text onto a Cairo surface is included.

if not ... then require'trlib_test'; return end

setfenv(1, require'trlib_types')

require'trlib_shape'
require'trlib_linewrap'
require'trlib_align'
require'trlib_clip'
require'trlib_rasterize'
require'trlib_paint'

terra Renderer:init()
	fill(self) --this initializes all arr() types.

	self.font_size_resolution  = 1.0/8  --in pixels
	self.subpixel_x_resolution = 1.0/4 --1/64 pixels is max with freetype
	self.word_subpixel_x_resolution = 1.0/4
	self.fonts:init()
	self.glyphs:init()
	self.glyphs.max_size = 1024 * 1024 * 20 --20MB net (arbitrary default)
	self.glyph_runs:init()
	self.glyph_runs.max_size = 1024 * 1024 * 10 --10MB net (arbitrary default)
	self.ranges.min_capacity = 64
	self.cpstack.min_capacity = 64
	assert(FT_Init_FreeType(&self.ft_lib) == 0)
	self:init_ub_lang()
end

terra Renderer:free()
	self.fonts           :free()
	self.glyphs          :free()
	self.glyph_runs      :free()
	self.cpstack         :free()
	self.scripts         :free()
	self.langs           :free()
	self.bidi_types      :free()
	self.bracket_types   :free()
	self.levels          :free()
	self.linebreaks      :free()
	self.grapheme_breaks :free()
	self.carets_buffer   :free()
	self.substack        :free()
	self.ranges          :free()
	FT_Done_FreeType(self.ft_lib)
end

terra Layout:free()
	self.lines:free()
	for _,seg in self.segs do
		self.r.glyph_runs:forget(seg.glyph_run_id)
	end
	self.segs:free()
	self.text:free()
	self.spans:free()
end

terra Renderer:font(load: FontLoadFunc, unload: FontUnloadFunc)
	assert(self.fonts.items.len <= 65000)
	var font_id = self.fonts:alloc()
	var font = self.fonts:at(font_id)
	font:init(self, load, unload)
	return font_id
end

terra Renderer:free_font(font_id: uint16)
	assert(self.fonts:at(font_id).refcount == 0)
	self.fonts:release(font_id)
end

return trlib
