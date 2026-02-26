package rarity

import vk "vendor:vulkan"

Command_Pool :: struct {
	handle: vk.CommandPool,
}

create_command_pool :: proc(device: Device) -> (pool: Command_Pool) {
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = device.indices.graphics.?,
	}

	CHECK(vk.CreateCommandPool(device.handle, &create_info, nil, &pool.handle))

	return
}

destroy_command_pool :: proc(device: Device, pool: ^Command_Pool) {
	vk.DestroyCommandPool(device.handle, pool.handle, nil)
	pool^ = {}
}
