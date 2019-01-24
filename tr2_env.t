
local low = require'low'

local tr = {}; setmetatable(tr, tr)
tr.__index = low
tr.tr = tr
setfenv(1, tr)

--dependencies ---------------------------------------------------------------

phf = require'phf'
fixedfreelist = require'fixedfreelist'
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

--enums ----------------------------------------------------------------------

ALIGN_AUTO = 0 --align_x

--align_x
ALIGN_LEFT = 1
ALIGN_RIGHT = 2
ALIGN_CENTER = 3

--align_y
ALIGN_TOP = 1
ALIGN_BOTTOM = 2
ALIGN_CENTER = 3

--dir
DIR_AUTO = FRIBIDI_PAR_ON
DIR_LTR  = FRIBIDI_PAR_LTR
DIR_RTL  = FRIBIDI_PAR_RTL
DIR_WLTR = FRIBIDI_PAR_WLTR
DIR_WRTL = FRIBIDI_PAR_WRTL

--linebreak codes
BREAK_NONE = 0
BREAK_LINE = 1
BREAK_PARA = 2

--types ----------------------------------------------------------------------

codepoint = uint32
cursor_offset_t = int16
cursor_x_t = num

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
	size: num;
	scale: num; --scaling factor for bitmap fonts
	ascent: num;
	descent: num;
	size_changed: {&Font} -> {};
}

local Color = tuple(double, double, double, double)

struct TextRun {
	offset: int; --offset in the text, in codepoints.
	font: &Font;
	font_size: num;
	features: &hb_feature_t;
	num_features: int8;
	script: hb_script_t;
	lang: hb_language_t;
	dir: FriBidiParType; --bidi direction for current and subsequent paragraphs.
	line_spacing: num; --line spacing multiplication factor (1).
	hardline_spacing: num; --line spacing MF for hard-breaked lines (1).
	paragraph_spacing: num; --paragraph spacing MF (2).
	nowrap: bool; --disable word wrapping.
	color: Color;
	opacity: double; --the opacity level in 0..1 (1).
	operator: int;   --blending operator (CAIRO_OPERATOR_OVER).
}

struct TextRuns {
	runs: arr(TextRun);
	codepoints: &codepoint;
	len: int; --text length in codepoints.
}
terra TextRuns:eof(i: int)
	var following_run = self.runs:at(i + 1)
	return iif(following_run ~= nil, following_run.offset, self.len)
end

struct GlyphRun {
	--cache key fields
	text: &codepoint;
	text_len: int16;
	font: &Font;
	font_size: num;
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
	ascent: num;
	descent: num;
	advance_x: num;
	wrap_advance_x: num;
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
	line_num: int; --physical line number
	--for line breaking
	linebreak: enum;
	--for bidi reordering
	bidi_level: FriBidiLevel;
	--for cursor positioning
	text_run: &TextRun; --text run of the first sub-segment
	offset: int; --codepoint offset into the text
	--slots filled by layouting
	x: num;
	advance_x: num; --segment's x-axis boundaries
	next: &Seg; --next segment on the same line in text order
	next_vis: &Seg; --next segment on the same line in visual order
	line: &Line;
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

struct Lines;

struct Segs {
	array: arr(Seg);
	text_runs: &TextRuns;
	bidi: bool; --`true` if the text is bidirectional.
	base_dir: FriBidiParType; --base paragraph direction of the first paragraph
	lines: Lines;
	--cached computed values
	_min_w: num;
	_max_w: num;
	page_h: num;
}

struct Line {
	index: int;
	first: &Seg; --first segment in text order
	first_vis: &Seg; --first segment in visual order
	x: num;
	y: num;
	advance_x: num;
	ascent: num;
	descent: num;
	spaced_ascent: num;
	spaced_descent: num;
	spacing: num;
	visible: bool; --entirely clipped or not
}

struct Lines {
	array: arr(Line);
	max_ax: num; --text's maximum x-advance (equivalent to text's width).
	h: num; --text's wrapped height.
	spaced_h: num; --text's wrapped height including line and paragraph spacing.
	baseline: num;
	first_visible: int;
	last_visible: int;
	min_x: num;
	x: num;
	y: num;
	align_x: enum;
	align_y: enum;
	clip_valid: bool;
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

RangesFreelist = fixedfreelist(SegRange)

struct TextRenderer {
	ft_lib: FT_Library;

	glyph_runs: GlyphRunCache;

	--temporary arrays that grow as long as the longest input text.
	cpstack: arr(codepoint);
	scripts: arr(hb_script_t);
	langs: arr(hb_language_t);
	bidi_types: arr(FriBidiCharType);
	bracket_types: arr(FriBidiBracketType);
	levels: arr(FriBidiLevel);
	linebreaks: arr(char);
	grapheme_breaks: arr(char);
	carets_buffer: arr(hb_position_t);
	substack: arr(SubSeg);
	ranges: RangesFreelist;

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
