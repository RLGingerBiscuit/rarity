package rarity

import glm "core:math/linalg/glsl"
import vk "vendor:vulkan"

Vertex :: struct #packed {
	position: glm.vec2,
	colour:   glm.vec3,
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
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, position),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, colour),
	},
}

// odinfmt:disable
@(rodata)
VERTICES := []Vertex{
	{ {-0.5, -0.5}, {1, 0, 0} },
	{ { 0.5, -0.5}, {0, 1, 0} },
	{ { 0.5,  0.5}, {0, 0, 1} },
	{ {-0.5,  0.5}, {1, 1, 1} },
}
@(rodata)
INDICES := []u16{0, 1, 2, 2, 3, 0}
// odinfmt:enable
