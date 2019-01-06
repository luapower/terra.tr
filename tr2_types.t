
setfenv(1, require'tr2_env')

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

struct Rasterizer {
	--
}

struct TR {
	glyph_run_cache_size: int;
	rasterizer: &Rasterizer;
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
	--for glyph painting
	font: &Font;
	font_size: float;
	len: int16; --glyph count
	info: &hb_glyph_info_t; --0..len-1
	pos: &hb_glyph_position_t; --0..len-1
	hb_buf: &hb_buffer_t; --anchored
	--for positioning in horizontal flow
	advance_x: float;
	wrap_advance_x: float;
	--for lru cache
	mem_size: int;
	--for cursor positioning and hit testing
	text_len: int16;
	cursor_offsets: &int16; --0..text_len
	cursor_xs: &float; --0..text_len
	rtl: bool;
	trailing_space: bool;
}

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

return tr
