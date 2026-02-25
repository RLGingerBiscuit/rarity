package rarity

import vk "vendor:vulkan"

Queue :: struct {
	handle: vk.Queue,
}

get_queue :: proc(device: Device, family, index: u32) -> (queue: Queue) {
	vk.GetDeviceQueue(device.handle, family, index, &queue.handle)
	return
}
