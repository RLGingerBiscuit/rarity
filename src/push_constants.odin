package rarity

import glm "core:math/linalg/glsl"

Push_Constants :: struct #packed {
	model:      glm.mat4,
	view:       glm.mat4,
	projection: glm.mat4,
}
