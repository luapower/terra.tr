
--Module table & environment with dependencies, enums and types.

setfenv(1, require'trlib_env')

--dependencies ---------------------------------------------------------------

assert(color, 'require the graphics adapter first, eg. trlib_paint_cairo')

phf = require'phf'
fixedfreelist = require'fixedfreelist'
lrucache = require'lrucache'

require_h'freetype_h'
require_h'harfbuzz_h'
require_h'fribidi_h'
require_h'libunibreak_h'
require_h'xxhash_h'

linklibrary'harfbuzz'
linklibrary'fribidi'
linklibrary'unibreak'
linklibrary'freetype'
linklibrary'xxhash'

--replace the default hash function with faster xxhash.
memhash = macro(function(size_t, k, h, len)
	local size_t = size_t:astype()
	local T = k:getpointertype()
	local len = len or 1
	local xxh = sizeof(size_t) == 8 and XXH64 or XXH32
	return `[size_t](xxh([&opaque](k), len * sizeof(T), h))
end)

--enums ----------------------------------------------------------------------

--NOTE: starting enum values at 1 so that clients can reserve 0 for "default".
ALIGN_LEFT    = 1
ALIGN_RIGHT   = 2
ALIGN_CENTER  = 3
ALIGN_TOP     = ALIGN_LEFT
ALIGN_BOTTOM  = ALIGN_RIGHT
ALIGN_AUTO    = 4 --based on bidi dir
ALIGN_MAX     = 4

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

cursor_offset_t = int16
cursor_x_t = num

struct TextRenderer;

struct Font;

FontLoadFunc   = {&Font, &&opaque, &int64} -> {}
FontUnloadFunc = {&Font, &&opaque, &int64} -> {}
FontLoadFunc  .__typename_ffi = 'FontLoadFunc'
FontUnloadFunc.__typename_ffi = 'FontUnloadFunc'

struct Font {
	tr: &TextRenderer;
	--loading and unloading
	file_data: &opaque;
	file_size: int64;
	load: FontLoadFunc;
	unload: FontUnloadFunc;
	refcount: int;
	--freetype & harfbuzz font objects
	hb_font: &hb_font_t;
	ft_face: FT_Face;
	ft_load_flags: int;
	ft_render_flags: FT_Render_Mode;
	--font metrics per current size
	size: num;
	scale: num; --scaling factor for bitmap fonts
	ascent: num;
	descent: num;
	size_changed: {&Font} -> {};
}

TextRunState = TextRunState or struct {}

struct TextRun {
	offset: int; --offset in the text, in codepoints.
	font: &Font;
	font_size: num;
	features: arr(hb_feature_t);
	script: hb_script_t;
	lang: hb_language_t;
	dir: FriBidiParType; --bidi direction for current and subsequent paragraphs.
	line_spacing: num; --line spacing multiplication factor (1).
	hardline_spacing: num; --line spacing MF for hard-breaked lines (1).
	paragraph_spacing: num; --paragraph spacing MF (2).
	nowrap: bool; --disable word wrapping.
	color: color;
	opacity: double; --the opacity level in 0..1 (1).
	operator: int;   --blending operator (CAIRO_OPERATOR_OVER).
	_state: TextRunState;
}

terra TextRun:init()
	fill(self)
	self.script = HB_SCRIPT_COMMON
	self.dir = DIR_AUTO
	self.line_spacing = 1
	self.hardline_spacing = 1
	self.paragraph_spacing = 2
	self.color = default_color_constant_text
	self.opacity = 1
	self.operator = 2 --CAIRO_OPERATOR_OVER
end

terra TextRun:free()
	self.features:free()
end

struct TextRuns {
	array: arr(TextRun);
	text: arr(codepoint);
	maxlen: int;
}

terra TextRuns:eof(i: int)
	var following_run = self.array:at(i + 1, nil)
	return iif(following_run ~= nil, following_run.offset, self.text.len)
end

terra TextRuns:init()
	fill(self)
	self.array:init()
	self.text:init()
end

terra TextRuns:free()
	self.text:free()
	self.array:call'free'
	self.array:free()
end

function TextRuns.metamethods.__cast(from, to, exp)
	if from == niltype then
		return `TextRuns {
			array = [arr(TextRun)](nil);
			text = [arr(codepoint)](nil);
			maxlen = maxint;
		}
	else
		error'invalid cast'
	end
end

struct GlyphRun {
	--cache key fields: must not have alignment holes!
	text           : arr(codepoint);
	features       : arr(hb_feature_t);
	font           : &Font;
	font_size      : num;
	lang           : hb_language_t;
	script         : hb_script_t;
	rtl            : bool;
	--resulting glyphs and glyph metrics
	hb_buf         : &hb_buffer_t; --anchored
	info           : &hb_glyph_info_t; --0..len-1
	pos            : &hb_glyph_position_t; --0..len-1
	len            : int16; --glyph count
	--for positioning in horizontal flow
	ascent         : num;
	descent        : num;
	advance_x      : num;
	wrap_advance_x : num;
	--for cursor positioning and hit testing
	cursor_offsets : &cursor_offset_t; --0..text_len
	cursor_xs      : &cursor_x_t; --0..text_len
	trailing_space : bool;
}

do
	local key_offset = offsetof(GlyphRun, 'font')
	local key_size = offsetof(GlyphRun, 'rtl') + sizeof(bool) - key_offset

	terra GlyphRun:__hash32(h: uint32)
		h = hash(uint32, [&char](self) + key_offset, h, key_size)
		h = hash(uint32, &self.text, h)
		h = hash(uint32, &self.features, h)
		return h
	end

	terra GlyphRun:__eq(other: &GlyphRun)
		return equal(
				[&char](self)  + key_offset,
				[&char](other) + key_offset, key_size)
			and self.text == other.text
			and self.features == other.features
	end
end

GlyphRunCache = lrucache {key_t = GlyphRun}

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

--expose Seg.glyph_run.<field> as Seg.<field> since glyph runs are an
--implementation detail coming from the fact that we are caching shaped words.
forwardproperties('glyph_run')(Seg)

struct Lines;

struct Segs {
	array: arr(Seg);
	tr: &TextRenderer;
	bidi: bool; --`true` if the text is bidirectional.
	base_dir: FriBidiParType; --base paragraph direction of the first paragraph
	lines: Lines;
	--cached computed values
	_min_w: num;
	_max_w: num;
	page_h: num;
	clip_valid: bool;
}

terra Segs:init(tr: &TextRenderer)
	fill(self)
	self.array:init()
	self.tr = tr
	self.base_dir = FRIBIDI_PAR_ON
	self.lines.array:init()
end

terra Segs:free()
	self.lines.array:free()
	self.array:free()
end

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
	clip_valid: bool;
}

struct SegRange {
	left: &Seg;
	right: &Seg;
	prev: &SegRange;
	bidi_level: int8;
}

RangesFreelist = fixedfreelist(SegRange)

--TODO: finish this or drop it
function Segs.metamethods.__cast(from, to, exp)
	if from == niltype then
		return `Segs {
			array = [arr(Seg)](nil);
			tr = nil;
			text_runs = nil;
			bidi = false;
			base_dir = DIR_AUTO;
			clip_valid = false;
		}
	else
		error'invalid cast'
	end
end

struct Glyph {
	--cache key: must not have alignment holes!
	font        : &Font
	font_size   : num;
	offset_x    : num;
	offset_y    : num;
	glyph_index : int;
	--freetype bitmap
	ft_bitmap: FT_Bitmap;
	ft_bitmap_left: int;
	ft_bitmap_top: int;
	--graphics surface
	surface: &GraphicsSurface;
}

do
	local key_offset = offsetof(Glyph, 'font')
	local key_size = offsetof(Glyph, 'glyph_index') + sizeof(int) - key_offset

	terra Glyph:__hash32(h: uint32)
		return hash(uint32, [&char](self) + key_offset, h, key_size)
	end

	terra Glyph:__eq(other: &Glyph)
		return equal(
			[&char](self ) + key_offset,
			[&char](other) + key_offset, key_size)
	end
end

GlyphCache = lrucache {key_t = Glyph}

struct Selection {
	segs: &Segs;
	offset: int;
	len: int;
	color: color;
}

terra Selection:init(segs: &Segs)
	self.segs = segs
	self.offset = 0
	self.len = 0
	self.color = default_color_constant_selection
end

struct TextRenderer (gettersandsetters) {

	--rasterizer config
	font_size_resolution: num;
	subpixel_x_resolution: num;
	subpixel_y_resolution: num;

	ft_lib: FT_Library;

	glyphs: GlyphCache;
	glyph_runs: GlyphRunCache;

	--temporary arrays that grow as long as the longest input text.
	cpstack:         arr(codepoint);
	scripts:         arr(hb_script_t);
	langs:           arr(hb_language_t);
	bidi_types:      arr(FriBidiCharType);
	bracket_types:   arr(FriBidiBracketType);
	levels:          arr(FriBidiLevel);
	linebreaks:      arr(char);
	grapheme_breaks: arr(char);
	carets_buffer:   arr(hb_position_t);
	substack:        arr(SubSeg);
	ranges:          RangesFreelist;

	--constants that neeed to be initialized at runtime.
	HB_LANGUAGE_EN: hb_language_t;
	HB_LANGUAGE_DE: hb_language_t;
	HB_LANGUAGE_ES: hb_language_t;
	HB_LANGUAGE_FR: hb_language_t;
	HB_LANGUAGE_RU: hb_language_t;
	HB_LANGUAGE_ZH: hb_language_t;

}

return trlib
