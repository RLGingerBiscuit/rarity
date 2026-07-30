package rarity

import glm "core:math/linalg/glsl"

MAX_PUSH_CONSTANT_SIZE :: 128

Model_Push_Constants :: struct {
	mvp: glm.mat4,
}
#assert(size_of(Model_Push_Constants) <= MAX_PUSH_CONSTANT_SIZE)

Edge_Detect_Push_Constants :: struct {
	projection: glm.mat4,
}
#assert(size_of(Edge_Detect_Push_Constants) <= MAX_PUSH_CONSTANT_SIZE)

Edge_Overlay_Push_Constants :: struct {
	colour: glm.vec4,
}
#assert(size_of(Edge_Overlay_Push_Constants) <= MAX_PUSH_CONSTANT_SIZE)

Font_Push_Constants :: struct {
	aemrange:        glm.vec2,
	antialias_em:    f32,
	flags:           u32,
}
#assert(size_of(Font_Push_Constants) <= MAX_PUSH_CONSTANT_SIZE)

Screen_Push_Constants :: struct {
	flip: b32,
}
#assert(size_of(Screen_Push_Constants) <= MAX_PUSH_CONSTANT_SIZE)
