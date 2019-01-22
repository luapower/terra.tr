
setfenv(1, require'tr2_env')

terra Font:ref()
	if self.refcount == 0 then
		if not self.load(self) then
			return false
		end
		if not FT_New_Memory_Face(self.tr.ft_lib, [&uint8](self.file_data),
			self.file_size, 0, &self.ft_face) == 0
		then
			self.unload(self)
			return false
		end
		self.hb_font = hb_ft_font_create_referenced(self.ft_face)
		if self.hb_font == nil then
			FT_Done_Face(self.ft_face); self.ft_face = nil
			self.unload(self)
			return false
		end
		hb_ft_font_set_load_flags(self.hb_font, self.ft_load_flags)
	end
	inc(self.refcount)
	return true
end

terra Font:unref()
	assert(self.refcount > 0)
	dec(self.refcount)
	if self.refcount == 0 then
		hb_font_destroy(self.hb_font); self.hb_font = nil
		FT_Done_Face(self.ft_face); self.ft_face = nil
		self.unload(self)
	end
end

terra Font:setsize(size: float)
	if self.size == size then return end
	self.size = size

	--find the size index closest to input size.
	var size_index: int
	var fixed_size = size
	var found: bool
	var best_diff: float = 1.0/0
	for i = 0, self.ft_face.num_fixed_sizes do
		var sz = self.ft_face.available_sizes[i]
		var this_size = sz.height
		var diff = abs(size - this_size)
		if diff < best_diff then
			size_index = i
			fixed_size = this_size
			found = true
		end
	end

	if found then
		self.scale = size / fixed_size
		FT_Select_Size(self.ft_face, size_index)
	else
		self.scale = 1
		FT_Set_Pixel_Sizes(self.ft_face, fixed_size, 0)
	end

	var ft_scale = self.scale / 64
	var m = self.ft_face.size.metrics
	self.ascent = m.ascender * ft_scale
	self.descent = m.descender * ft_scale

	if self.size_changed ~= nil then
		self.size_changed(self)
	end
end
