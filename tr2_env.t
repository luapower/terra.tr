
local low = require'low'
local tr = setmetatable({}, {__index = low.C})
tr.tr = tr
setfenv(1, tr)

I'$L/csrc/harfbuzz/src'
I'$L/csrc/fribidi/src'
I'$L/csrc/libunibreak/src'
I'$L/csrc/freetype/include'

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

link'harfbuzz'
link'fribidi'
link'unibreak'
link'freetype'

return tr
