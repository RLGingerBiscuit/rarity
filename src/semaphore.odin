package rarity

import vk "vendor:vulkan"

Semaphore :: struct {
	handle: vk.Semaphore,
}

create_semaphore :: proc(device: Device) -> (sema: Semaphore) {
	create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	CHECK(vk.CreateSemaphore(device.handle, &create_info, nil, &sema.handle))

	return
}

destroy_semaphore :: proc(device: Device, sema: ^Semaphore) {
	vk.DestroySemaphore(device.handle, sema.handle, nil)
	sema^ = {}
}
