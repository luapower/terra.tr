
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

