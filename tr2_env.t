
local low = require'low'

local tr = {}; setmetatable(tr, tr)
tr.__index = low
tr.tr = tr
setfenv(1, tr)

--dependencies ---------------------------------------------------------------

lrucache = require'lrucache'
phf = require'phf'

includepath'$L/csrc/harfbuzz/src'
includepath'$L/csrc/fribidi/src'
includepath'$L/csrc/libunibreak/src'
includepath'$L/csrc/freetype/include'

include'stdio.h'
include'hb.h'
include'hb-ot.h'
include'hb-ft.h'
include'fribidi.h'
include'linebreak.h'
include'wordbreak.h'
include'graphemebreak.h'
include'ft2build.h'
include'freetype/freetype.h'

linklibrary'harfbuzz'
linklibrary'fribidi'
linklibrary'unibreak'
linklibrary'freetype'

--types ----------------------------------------------------------------------

codepoint = uint32

struct Color {
	r: float;
	g: float;
	b: float;
	a: float;
}

struct Font {
	hb_font: &hb_font_t;
	ft_face: FT_Face;
	ft_load_flags: int;
	scale: float;
}

DIR_AUTO = 0
DIR_LTR = 1
DIR_RTL = 2

struct TextRun {
	offset: int; --offset in the text, in codepoints.
	len: int; --text run length in codepoints.
	font: &Font;
	font_size: float;
	features: &hb_feature_t;
	script: hb_script_t;
	lang: hb_language_t;
	dir: int8; --bidi direction for current and subsequent paragraphs.
	line_spacing: float; --line spacing multiplication factor (1).
	hardline_spacing: float; --line spacing MF for hard-breaked lines (1).
	paragraph_spacing: float; --paragraph spacing MF (2).
	nowrap: bool; --disable word wrapping.
	color: Color;
	opacity: float; --the opacity level in 0..1 (1).
	operator: int; --blending operator (CAIRO_OPERATOR_OVER).
}

struct TextRuns {
	runs: &TextRun;
	codepoints: &uint32;
	len: int; --text length in codepoints.
}

struct GlyphRun {
	--cache key fields
	text: &codepoint;
	text_len: int16;
	font: &Font;
	font_size: float;
	script: hb_script_t;
	lang: hb_language_t;
	rtl: bool;
	--resulting glyphs and glyph metrics
	hb_buf: &hb_buffer_t; --anchored
	info: &hb_glyph_info_t; --0..len-1
	pos: &hb_glyph_position_t; --0..len-1
	len: int16; --glyph count
	--for positioning in horizontal flow
	advance_x: float;
	wrap_advance_x: float;
	--for cursor positioning and hit testing
	cursor_offsets: &int16; --0..text_len
	cursor_xs: &float; --0..text_len
	trailing_space: bool;
	--rtl: bool;
}

terra GlyphRun:__hash() --for the LRU cache

end

terra GlyphRun:__size() --for the LRU cache
	return
		sizeof(GlyphRun)
		+ (sizeof(hb_glyph_info_t) + sizeof(hb_glyph_position_t)) * self.len
		+ (sizeof(int16) + sizeof(float)) * (self.text_len + 1) --cursors
end

struct Seg {
	glyph_run: &GlyphRun;
	--for line breaking
	linebreak: int8; --hard break
	--for bidi reordering
	bidi_level: int8;
	--for cursor positioning
	text_run: TextRun; --text run of the last sub-segment
	offset: int16;
	index: int;
	--slots filled by layouting
	x: float;
	advance_x: float; --segment's x-axis boundaries
	next: &Seg; --next segment on the same line in text order
	next_vis: &Seg; --next segment on the same line in visual order
	line: &Line;
	line_num: int; --physical line number
	wrapped: bool; --segment is the last on a wrapped line
	visible: bool; --segment is not entirely clipped
}

struct Segs {
	segs: &Seg;
	text_runs: &TextRuns;
	bidi: bool; --`true` if the text is bidirectional.
	base_dir: FriBidiParType; --base paragraph direction of the first paragraph
}

struct Line {
	index: int;
	first: &Seg; --first segment in text order
	first_vis: &Seg; --first segment in visual order
	x: float;
	y: float;
	advance_x: float;
	ascent: float;
	descent: float;
	spaced_ascent: float;
	spaced_descent: float;
	visible: bool; --entirely clipped or not
}

struct Lines {
	lines: &Line;
	max_ax: float; --text's maximum x-advance (equivalent to text's width).
	h: float; --text's wrapped height.
	spaced_h: float; --text's wrapped height including line and paragraph spacing.
}

struct Rasterizer {

}

--local GlyphRunCache = lrucache {key_t = GlyphRunCacheKey, val_t = GlyphRun}

struct TextRenderer {
	--glyph_runs: GlyphRunCache;
	rasterizer: Rasterizer;
}

struct GlyphRunKey {
	--cache key fields
	text: &codepoint;
	text_len: int16;
	font: &Font;
	font_size: float;
	script: hb_script_t;
	lang: hb_language_t;
	rtl: bool;
}
print(sizeof(GlyphRunKey))

return tr