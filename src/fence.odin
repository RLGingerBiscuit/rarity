package rarity

import vk "vendor:vulkan"

Fence :: struct {
	handle: vk.Fence,
}

create_fence :: proc(device: Device) -> (fence: Fence) {
	create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	CHECK(vk.CreateFence(device.handle, &create_info, nil, &fence.handle))

	return
}

destroy_fence :: proc(device: Device, fence: ^Fence) {
	vk.DestroyFence(device.handle, fence.handle, nil)
	fence^ = {}
}

wait_for_fence :: proc(device: Device, fence: ^Fence) {
	vk.WaitForFences(device.handle, 1, &fence.handle, true, max(u64))
}

reset_fence :: proc(device: Device, fence: ^Fence) {
	vk.ResetFences(device.handle, 1, &fence.handle)
}
