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
	CHECK(vk.ResetCommandBuffer(buffer.handle, {}))
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

begin_immediate :: proc(
	device: Device,
	immediate_pool: Command_Pool,
	transfer_queue: Queue,
	fence: Fence,
) -> (
	cmd: Command_Buffer,
) {
	fence := fence
	cmd = allocate_command_buffer(device, immediate_pool)
	reset_fence(device, &fence)

	command_buffer_begin(cmd, {.ONE_TIME_SUBMIT})
	return
}

end_immediate :: proc(
	device: Device,
	immediate_pool: Command_Pool,
	transfer_queue: Queue,
	fence: Fence,
	cmd: Command_Buffer,
) {
	fence := fence
	cmd := cmd
	command_buffer_end(cmd)

	queue_submit_simple(transfer_queue, &cmd, fence)
	wait_for_fence(device, &fence)

	free_command_buffer(device, immediate_pool, &cmd)
}

@(deferred_in_out = _deferred_immediate_guard_end)
immediate_guard :: proc(
	device: Device,
	immediate_pool: Command_Pool,
	transfer_queue: Queue,
	fence: Fence,
) -> (
	cmd: Command_Buffer,
) {
	return begin_immediate(device, immediate_pool, transfer_queue, fence)
}

_deferred_immediate_guard_end :: proc(
	device: Device,
	immediate_pool: Command_Pool,
	transfer_queue: Queue,
	fence: Fence,
	cmd: Command_Buffer,
) {
	end_immediate(device, immediate_pool, transfer_queue, fence, cmd)
}
