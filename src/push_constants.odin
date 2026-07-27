package rarity

import glm "core:math/linalg/glsl"

Model_Push_Constants :: struct #packed {
	mvp: glm.mat4,
}

Edge_Detect_Push_Constants :: struct #packed {
	projection: glm.mat4,
}

Edge_Overlay_Push_Constants :: struct #packed {
	colour: glm.vec4,
}
