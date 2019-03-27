
--Module table & environment with dependencies, enums and types.

if not ... then require'trlib_test'; return end

setfenv(1, require'trlib_env')

--dependencies ---------------------------------------------------------------

assert(color, 'require the graphics adapter first, eg. trlib_paint_cairo')

require'phf'
require'fixedfreelist'
require'lrucache'
require'arrayfreelist'
require'box2dlib'

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

--create getters and setters for converting from/to fixed-point decimal fields.
function fixpointfields(T)
	for i,e in ipairs(T.entries) do
		local priv = e.field
		local pub, digits, decimals = priv:match'^(.-)_(%d+)_(%d+)$'
		if pub then
			local intbits = tonumber(digits) - tonumber(decimals)
			local factor = 2^decimals
			T.methods['get_'..pub] = macro(function(self)
				return `[num](self.[priv] / [num](factor))
			end)
			local maxn = 2^intbits * 64 - 1
			T.methods['set_'..pub] = macro(function(self, x)
				return quote self.[priv] = clamp(x * factor, 0, maxn) end
			end)
		end
	end
end

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

--base types -----------------------------------------------------------------

num = float
font_id_t = uint16

struct TextRenderer;
struct Font;

--font type ------------------------------------------------------------------

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

--layout type ----------------------------------------------------------------

SpanState = SpanState or struct {}

struct Span (gettersandsetters) {
	offset: int; --offset in the text, in codepoints.
	font_id: font_id_t;
	font_size_16_6: uint16;
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
	_state: SpanState;
}
fixpointfields(Span)

terra Span:init()
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

terra Span:free()
	self.features:free()
end

struct SubSeg {
	i: int16;
	j: int16;
	span: &Span;
	clip_left: num;
	clip_right: num;
};

struct Seg {
	glyph_run_id: uint;
	line_num: int; --physical line number
	--for line breaking
	linebreak: enum;
	--for bidi reordering
	bidi_level: FriBidiLevel;
	--for cursor positioning
	span: &Span; --span of the first sub-segment
	offset: int; --codepoint offset into the text
	--slots filled by layouting
	x: num;
	advance_x: num; --segment's x-axis boundaries
	next: &Seg; --next segment on the same line in text order
	next_vis: &Seg; --next segment on the same line in visual order
	wrapped: bool; --segment is the last on a wrapped line
	visible: bool; --segment is not entirely clipped
	subsegs: arr(SubSeg);
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

struct Layout {
	tr: &TextRenderer;
	--input
	spans: arr(Span);
	text: arr(codepoint);
	maxlen: int;
	--shaping output: segments and bidi info
	segs: arr(Seg);
	bidi: bool; --`true` if the text is bidirectional.
	base_dir: FriBidiParType; --base paragraph direction of the first paragraph
	--wrap/align output: lines
	lines: arr(Line);
	max_ax: num; --text's maximum x-advance (equivalent to text's width).
	h: num; --text's wrapped height.
	spaced_h: num; --text's wrapped height including line and paragraph spacing.
	baseline: num;
	first_visible_line: int;
	last_visible_line: int;
	min_x: num;
	x: num;
	y: num;
	align_x: enum;
	clip_valid: bool;
	--cached computed values
	_min_w: num;
	_max_w: num;
	page_h: num;
}

Layout.methods.glyph_run = macro(function(self, seg)
	return `&self.tr.glyph_runs:pair(seg.glyph_run_id).key
end)

terra Layout:eof(i: int)
	var next_span = self.spans:at(i+1, nil)
	return iif(next_span ~= nil, next_span.offset, self.text.len)
end

terra Layout:init(tr: &TextRenderer)
	fill(self)
	self.maxlen = maxint
	self.base_dir = FRIBIDI_PAR_ON
	self.tr = tr
end

terra Layout:free()
	self.lines:free()
	self.segs:free()
	self.text:free()
	self.spans:call'free'
	self.spans:free()
end

newcast(Layout, niltype, Layout.empty)

--glyph run type -------------------------------------------------------------

struct GlyphInfo (gettersandsetters) {
	glyph_index: uint;
	x: num; --glyph origin relative to glyph run origin
	image_x_16_6: int16; --glyph image origin relative to glyph origin
	image_y_16_6: int16;
	cluster: uint16;
}
fixpointfields(GlyphInfo)

struct GlyphRun (gettersandsetters) {
	--cache key fields: no alignment holes between lang..rtl!
	text            : arr(codepoint);
	features        : arr(hb_feature_t);
	lang            : hb_language_t;     --8
	script          : hb_script_t;       --4
	font_id         : font_id_t;         --2
	font_size_16_6  : uint16;            --2
	rtl             : bool;              --1
	--resulting glyphs and glyph metrics
	glyphs          : arr(GlyphInfo);
	--for positioning in horizontal flow
	ascent          : num;
	descent         : num;
	advance_x       : num;
	wrap_advance_x  : num;
	--cached surfaces for each subpixel-offset with painted glyph on them.
	surfaces        : arr(&GraphicsSurface);
	surfaces_memsize : uint32;
	surface_x       : int16;
	surface_y       : int16;
	--for cursor positioning and hit testing (len = text_len+1)
	cursor_offsets  : arr(uint16);
	cursor_xs       : arr(num);
	trailing_space  : bool;
}
fixpointfields(GlyphRun)

local key_offset = offsetof(GlyphRun, 'lang')
local key_size = offsetafter(GlyphRun, 'rtl') - key_offset

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
		and equal(&self.text, &other.text)
		and equal(&self.features, &other.features)
end

terra GlyphRun:__memsize()
	return
		  memsize(self.text)
		+ memsize(self.features)
		+ memsize(self.glyphs)
		+ memsize(self.surfaces)
		+ memsize(self.cursor_offsets)
		+ memsize(self.cursor_xs)
		+ self.surfaces_memsize
end

--glyph type -----------------------------------------------------------------

struct Glyph (gettersandsetters) {
	--cache key: must not have alignment holes!
	font_id         : font_id_t;
	font_size_16_6  : uint16;
	glyph_index     : uint;
	subpixel_offset_x_8_6 : uint8; -- 0..63 representing 0..1
	--graphics surface
	surface: &GraphicsSurface;
	surface_x: int16; --bitmap coordinates relative to the glyph origin
	surface_y: int16;
}
fixpointfields(Glyph)

Glyph.empty = `Glyph {
	font_id = -1;
	font_size_16_6 = 0;
	subpixel_offset_x_8_6 = 0;
	glyph_index = 0;
	surface = nil;
	surface_x = 0; surface_y = 0;
}

local key_offset = offsetof(Glyph, 'font_id')
local key_size = offsetafter(Glyph, 'subpixel_offset_x_8_6') - key_offset

terra Glyph:__hash32(h: uint32)
	return hash(uint32, [&char](self) + key_offset, h, key_size)
end

terra Glyph:__eq(other: &Glyph)
	return equal(
		[&char](self ) + key_offset,
		[&char](other) + key_offset, key_size)
end

terra Glyph:__memsize()
	return iif(self.surface ~= nil,
		1024 + self.surface:stride() * self.surface:height(), 0)
end

--renderer type --------------------------------------------------------------

struct SegRange {
	left: &Seg;
	right: &Seg;
	prev: &SegRange;
	bidi_level: int8;
}

RangesFreelist = fixedfreelist(SegRange)

GlyphRunCache = lrucache {key_t = GlyphRun}
GlyphCache = lrucache {key_t = Glyph}

struct TextRenderer (gettersandsetters) {

	--rasterizer config
	font_size_resolution: num;
	subpixel_x_resolution: num;
	word_subpixel_x_resolution: num;

	ft_lib: FT_Library;

	fonts: arrayfreelist(Font, uint16);

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

	paint_glyph_num: int;
}

--[[
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
]]

return trlib
