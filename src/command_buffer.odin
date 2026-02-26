package rarity

import vk "vendor:vulkan"

Command_Buffer :: struct {
	handle: vk.CommandBuffer,
}

allocate_command_buffer :: proc(device: Device, pool: Command_Pool) -> (buffer: Command_Buffer) {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool.handle,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}

	CHECK(vk.AllocateCommandBuffers(device.handle, &allocate_info, &buffer.handle))

	return
}

free_command_buffer :: proc(device: Device, pool: Command_Pool, buffer: ^Command_Buffer) {
	vk.FreeCommandBuffers(device.handle, pool.handle, 1, &buffer.handle)
	buffer^ = {}
}

reset_command_buffer :: proc(buffer: Command_Buffer) {
	vk.ResetCommandBuffer(buffer.handle, {})
}

command_buffer_begin :: proc(buffer: Command_Buffer, flags: vk.CommandBufferUsageFlags) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags,
	}

	CHECK(vk.BeginCommandBuffer(buffer.handle, &begin_info))
}

command_buffer_end :: proc(buffer: Command_Buffer) {
	CHECK(vk.EndCommandBuffer(buffer.handle))
}
