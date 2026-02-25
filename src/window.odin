package rarity

import "core:log"
import "core:strings"
import "vendor:glfw"

Window :: struct {
	handle:        glfw.WindowHandle,
	title:         string,
	width, height: int,
}

init_window :: proc(window: ^Window, title: string, width, height: int) {
	log.ensure(cast(bool)glfw.Init())

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, false)

	window.handle = glfw.CreateWindow(
		cast(i32)width,
		cast(i32)height,
		strings.clone_to_cstring(title, context.temp_allocator),
		nil,
		nil,
	)
}

destroy_window :: proc(window: ^Window) {
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

window_should_close :: proc(window: Window) -> bool {
	return cast(bool)glfw.WindowShouldClose(window.handle)
}

update_window :: proc(window: ^Window) {
	glfw.PollEvents()
}
