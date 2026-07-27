package rarity

import glm "core:math/linalg/glsl"

Model_Push_Constants :: struct {
	mvp: glm.mat4,
}

Edge_Detect_Push_Constants :: struct {
	projection: glm.mat4,
}

Edge_Overlay_Push_Constants :: struct {
	colour: glm.vec4,
}
