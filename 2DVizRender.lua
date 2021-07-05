local M = {}

M.lights = {}

local id = 0

function M.create_targets(self)
	-- width and height
	local color_params = { format = render.FORMAT_RGBA,
							width = 64,
							height = 64,
							min_filter = render.FILTER_LINEAR,
							mag_filter = render.FILTER_LINEAR,
							u_wrap = render.WRAP_CLAMP_TO_EDGE,
							v_wrap = render.WRAP_CLAMP_TO_EDGE }

	self.occluder_target = render.render_target({[render.BUFFER_COLOR_BIT] = color_params})
	self.shadow_map_target = render.render_target({[render.BUFFER_COLOR_BIT] = color_params})
end

function M.all(self, view, projection)
	local window_width = render.get_window_width()
	local window_height = render.get_window_height()

	for index, value in ipairs(M.lights) do
		M.draw_occluder(self, value, function ()
			render.set_depth_mask(false)
			render.disable_state(render.STATE_DEPTH_TEST)
			render.disable_state(render.STATE_STENCIL_TEST)
			render.enable_state(render.STATE_BLEND)
			render.set_blend_func(render.BLEND_SRC_ALPHA, render.BLEND_ONE_MINUS_SRC_ALPHA)
			render.disable_state(render.STATE_CULL_FACE)

			render.draw(self.tile_pred)
		end)

		M.draw_shadow_map(self, value)

		M.draw_lights(self, value, view, projection, window_width, window_height, function ()
			--render.set_blend_func(render.BLEND_ONE, render.BLEND_ONE)
		end)
	end
end

function M.draw_occluder(self, property, draw_func)
	-- Set render target size to precision
	render.set_render_target_size(self.occluder_target, property.size_scaled.x, property.size_scaled.y)

	-- Set viewport
	render.set_viewport(0, 0, property.size_scaled.x, property.size_scaled.y)

	-- Set projection so occluders fill the render target
	render.set_projection(vmath.matrix4_orthographic(0, property.size.x, 0, property.size.y, -5, 5))

	-- Set view matrix to lightPos
	render.set_view(vmath.matrix4_look_at(vmath.vector3(-property.size_half.x, -property.size_half.y, 0) + property.lightPos, vmath.vector3(-property.size_half.x, -property.size_half.y, -1) + property.lightPos, vmath.vector3(0, 1, 0)))

	-- Clear then draw
	render.set_render_target(self.occluder_target, { transient = { render.BUFFER_DEPTH_BIT, render.BUFFER_STENCIL_BIT } } )
	render.clear({[render.BUFFER_COLOR_BIT] = self.clear_color})

	draw_func()
end

function M.draw_shadow_map(self, property)
	-- Set render target size to precision
	render.set_render_target_size(self.shadow_map_target, property.size_scaled.x, 1)

	-- Viewport is already set

	-- Set projection so occluders fill the render target
	render.set_projection(vmath.matrix4_orthographic(0, property.size.x, 0, 1, -5, 5))

	-- Set view matrix to middle
	render.set_view(vmath.matrix4_look_at(vmath.vector3(-property.size_half.x, -property.size_half.y, 0), vmath.vector3(-property.size_half.x, -property.size_half.y, -1), vmath.vector3(0, 1, 0)))

	-- Clear then draw
	render.set_render_target(self.shadow_map_target, { transient = { render.BUFFER_DEPTH_BIT, render.BUFFER_STENCIL_BIT } } )
	render.clear({[render.BUFFER_COLOR_BIT] = self.clear_color})

	render.enable_material("shadow_map")
	render.enable_texture(0, self.occluder_target, render.BUFFER_COLOR_BIT)

	-- Only resolution.x
	local constants = render.constant_buffer()
	constants.resolution = vmath.vector4(property.size_scaled.x)
	constants.size = vmath.vector4(property.size.x, property.size.y, property.size.z, 0)
	render.draw(self.quad_pred, constants)

	render.disable_texture(0, self.occluder_target)
	render.disable_material()
end

function M.draw_lights(self, property, view, projection, window_width, window_height, blend_func)
	-- Render target is default

	-- Set viewport
	render.set_viewport(0, 0, window_width, window_height)

	-- Set proj to param
	render.set_projection(projection)

	-- Set view to param
	render.set_view(view)

	-- Draw whitout clear
	render.set_render_target(render.RENDER_TARGET_DEFAULT)

	render.enable_material("light_map")
	render.enable_texture(0, self.shadow_map_target, render.BUFFER_COLOR_BIT)

	local constants = render.constant_buffer()
	constants.light_pos = vmath.vector4(property.lightPos.x, property.lightPos.y, property.lightPos.z, 0)
	constants.size = vmath.vector4(property.size.x, property.size.y, property.size.z, 0)
	-- Color clamped to 0.0, 1.0
	constants.color = property.color
	constants.property = vmath.vector4(property.radial_Falloff, 0, 0, 0)
	constants.angle = vmath.vector4(property.angle.x, property.angle.y, property.angle.z, property.angle.w)
	
	-- Call blend_func before draw
	blend_func()
	render.draw(self.quad_pred, constants)

	render.disable_texture(0, self.shadow_map_target)
	render.disable_material()
end

--
--
--

function M.enable_light(property)
	local index = #M.lights + 1
	id = id + 1

	-- Copy property table
	M.lights[index] = {
		lightPos = property.lightPos,
		size = property.size,
		precision = property.precision,
		color = property.color,
		angle = property.angle,
		radial_Falloff = property.radial_Falloff,

		-- Defined in runtime
		id = id,
		size_half = property.size * 0.5,
		size_scaled = property.size * property.precision,
	}

	return M.lights[index]
end

function M.disable_light(light)
	-- Find index
	local index = 0
	for _index, value in ipairs(M.lights) do
		if value.id == light.id then
			index = _index
			break
		end
	end

	if index == 0 then
		error("Can't find active light with ID:" .. light.id)
	end

	for i = index, #M.lights do
		M.lights[i] = M.lights[i + 1]
	end
end

function M.set_light_size(light, size)
	light.size = size
	light.size_half = size * 0.5
	light.size_scaled = size * light.precision
end

return M