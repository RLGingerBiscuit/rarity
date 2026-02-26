package rarity

import "core:log"
import "core:strings"
import "vendor:glfw"

Window :: struct {
	handle: glfw.WindowHandle,
}

init_window :: proc(window: ^Window, title: string, width, height: int) {
	log.ensure(cast(bool)glfw.Init(), "Could not init GLFW")

	log.ensure(cast(bool)glfw.VulkanSupported(), "Vulkan is not supported")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	// glfw.WindowHint(glfw.RESIZABLE, false)

	window.handle = glfw.CreateWindow(
		cast(i32)width,
		cast(i32)height,
		strings.clone_to_cstring(title, context.temp_allocator),
		nil,
		nil,
	)
	log.info("Created GLFW window:", window.handle)
}

destroy_window :: proc(window: ^Window) {
	log.info("Destroying window")
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
	window^ = {}
}

window_should_close :: proc(window: Window) -> bool {
	return cast(bool)glfw.WindowShouldClose(window.handle)
}

update_window :: proc(window: ^Window) {
	glfw.PollEvents()
}

window_wait :: proc(window: Window) {
	glfw.WaitEvents()
}

get_window_size :: proc(window: Window) -> (width, height: i32) {
	return glfw.GetFramebufferSize(window.handle)
}
