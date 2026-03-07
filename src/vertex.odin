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

// odinfmt:disable
@(rodata)
VERTICES := []Vertex{
	{ {-0.5, -0.5,  0},   {1, 0, 0, 1}, { 1.5, -0.5}, },
	{ { 0.5, -0.5,  0},   {0, 1, 0, 1}, {-0.5, -0.5}, },
	{ { 0.5,  0.5,  0},   {0, 0, 1, 1}, {-0.5,  1.5}, },
	{ {-0.5,  0.5,  0},   {1, 1, 1, 1}, { 1.5,  1.5}, },
	//
	{ {-0.5, -0.5, -0.5}, {1, 0, 0, 1}, { 1.5, -0.5}, },
	{ { 0.5, -0.5, -0.5}, {0, 1, 0, 1}, {-0.5, -0.5}, },
	{ { 0.5,  0.5, -0.5}, {0, 0, 1, 1}, {-0.5,  1.5}, },
	{ {-0.5,  0.5, -0.5}, {1, 1, 1, 1}, { 1.5,  1.5}, },
}
@(rodata)
INDICES := []u16{
	0, 1, 2, 2, 3, 0,
	4, 5, 6, 6, 7, 4,
}
// odinfmt:enable
