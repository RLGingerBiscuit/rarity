package rarity

import "vendor:glfw"
import vk "vendor:vulkan"

Surface :: struct {
	handle: vk.SurfaceKHR,
}

create_surface :: proc(instance: Instance, window: Window) -> (surface: Surface) {
	CHECK(glfw.CreateWindowSurface(instance.handle, window.handle, nil, &surface.handle))
	return
}

destroy_surface :: proc(instance: Instance, surface: ^Surface) {
	vk.DestroySurfaceKHR(instance.handle, surface.handle, nil)
	surface^ = {}
}
