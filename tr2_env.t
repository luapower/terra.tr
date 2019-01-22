
local low = require'low'

local tr = {}; setmetatable(tr, tr)
tr.__index = low
tr.tr = tr
setfenv(1, tr)

--dependencies ---------------------------------------------------------------

phf = require'phf'
freelist = require'freelist'
lrucache = require'lrucache'

includepath'$L/csrc/harfbuzz/src'
includepath'$L/csrc/fribidi/src'
includepath'$L/csrc/libunibreak/src'
includepath'$L/csrc/freetype/include'
includepath'$L/csrc/xxhash'

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
include'xxhash.h'

linklibrary'harfbuzz'
linklibrary'fribidi'
linklibrary'unibreak'
linklibrary'freetype'
linklibrary'xxhash'

--replace the default hash function with faster xxhash.
hash = macro(function(size_t, buf, len)
	size_t = size_t:astype()
	local xxh = sizeof(size_t) == 8 and XXH64 or XXH32
	return `xxh(buf, len, 0)
end)

--utils ----------------------------------------------------------------------

local direct_equal = macro(function(a, b) return `a == b end)

--iterate the RLE chunks of any object with indexable elements.
function rle_iterator(T, get_value, equal)
	equal = equal or direct_equal
	local struct rle_iter { t: &T; i: int; j: int; }
	function rle_iter.metamethods.__for(self, body)
		return quote
			if self.i < self.j then
				var v0 = get_value(self.t, self.i)
				var i0 = 0
				for i = self.i + 1, self.j do
					var v = get_value(self.t, i)
					if not equal(v0, v) then
						[ body(i0, `i - i0, v0) ]
						v0 = v
						i0 = i
					end
				end
				[ body(i0, `self.j - self.i - i0, v0) ]
			end
		end
	end
	return rle_iter
end

--types ----------------------------------------------------------------------

codepoint = uint32
cursor_offset_t = int16
cursor_x_t = float

struct TextRenderer;

struct Font {
	tr: &TextRenderer; --for ft_lib
	--loading and unloading
	file_data: &opaque;
	file_size: int;
	load: {&Font} -> bool;
	unload: {&Font} -> {};
	refcount: int;
	--freetype & harfbuzz font objects
	hb_font: &hb_font_t;
	ft_face: FT_Face;
	ft_load_flags: int;
	--font metrics per current size
	size: float;
	scale: float; --scaling factor for bitmap fonts
	ascent: float;
	descent: float;
	size_changed: {&Font} -> {};
}

struct Color {
	r: float;
	g: float;
	b: float;
	a: float;
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
	num_features: int8;
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
	runs: arr(TextRun);
	codepoints: &codepoint;
	len: int; --text length in codepoints.
}

struct GlyphRun {
	--cache key fields
	text: &codepoint;
	text_len: int16;
	font: &Font;
	font_size: float;
	features: &hb_feature_t;
	num_features: int8;
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
	cursor_offsets: &cursor_offset_t; --0..text_len
	cursor_xs: &cursor_x_t; --0..text_len
	trailing_space: bool;
}

GlyphRun_key_offset = offsetof(GlyphRun, 'text_len')
GlyphRun_val_offset = offsetof(GlyphRun, 'hb_buf')
GlyphRun_key_size = GlyphRun_val_offset - GlyphRun_key_offset

struct Line;

struct SubSeg {
	i: int16;
	j: int16;
	text_run: &TextRun;
	clip_left: cursor_x_t;
	clip_right: cursor_x_t;
};

struct Seg {
	glyph_run: &GlyphRun;
	--for line breaking
	linebreak: int8; --hard break
	--for bidi reordering
	bidi_level: int8;
	--for cursor positioning
	text_run: &TextRun; --text run of the last sub-segment
	offset: int; --codepoint offset into the text
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
	subsegs: arr(SubSeg);
}

local props = addproperties(Seg)
local function fw(prop, field)
	props[prop] = macro(function(self)
		return `self.[field].[prop]
	end)
end
fw('text'           , 'glyph_run')
fw('text_len'       , 'glyph_run')
fw('font'           , 'glyph_run')
fw('font_size'      , 'glyph_run')
fw('script'         , 'glyph_run')
fw('lang'           , 'glyph_run')
fw('rtl'            , 'glyph_run')
fw('info'           , 'glyph_run')
fw('pos'            , 'glyph_run')
fw('len'            , 'glyph_run')
fw('cursor_offsets' , 'glyph_run')
fw('cursor_xs'      , 'glyph_run')
fw('trailing_space' , 'glyph_run')

SegArray = arr(Seg)

struct Segs {
	segs: SegArray;
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

GlyphRunCache = lrucache {key_t = GlyphRun}

struct SegRange {
	left: &Seg;
	right: &Seg;
	prev: &SegRange;
	bidi_level: int8;
}

struct TextRenderer {
	ft_lib: FT_Library;

	glyph_runs: GlyphRunCache;

	--temporary arrays that grow as long as the longest input text.
	scripts: arr(hb_script_t);
	langs: arr(hb_language_t);
	bidi_types: arr(FriBidiCharType);
	bracket_types: arr(FriBidiBracketType);
	levels: arr(FriBidiLevel);
	linebreaks: arr(char);
	grapheme_breaks: arr(char);
	carets_buffer: arr(hb_position_t);
	substack: arr(SubSeg);
	ranges: freelist(SegRange);

	--constants that neeed to be initialized at runtime.
	HB_LANGUAGE_EN: hb_language_t;
	HB_LANGUAGE_DE: hb_language_t;
	HB_LANGUAGE_ES: hb_language_t;
	HB_LANGUAGE_FR: hb_language_t;
	HB_LANGUAGE_RU: hb_language_t;
	HB_LANGUAGE_ZH: hb_language_t;

	rasterizer: Rasterizer;
}

return tr
