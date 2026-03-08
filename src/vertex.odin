package rarity

import glm "core:math/linalg/glsl"
import vk "vendor:vulkan"

Vertex :: struct #packed {
	position:  glm.vec3,
	colour:    glm.vec4,
	tex_coord: glm.vec2,
}

@(rodata)
BINDING_DESCRIPTION := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

@(rodata)
ATTRIBUTE_DESCRIPTIONS := []vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, position),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32A32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, colour),
	},
	{
		binding = 0,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, tex_coord),
	},
}
