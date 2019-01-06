
setfenv(1, require'tr2_types')

local detect_scripts = require'tr2_shape_script'
local lang_for_script = require'tr2_shape_lang'
local reorder_segs = require'tr2_shape_reorder'

local PS = FRIBIDI_CHAR_PS --paragraph separator codepoint
local LS = FRIBIDI_CHAR_LS --line separator codepoint

