package rarity

import "core:slice"
import vk "vendor:vulkan"

Index_Buffer :: struct {
	using buffer: Buffer,
}

create_index_buffer :: proc(
	device: Device,
	physical_device: Physical_Device,
	transfer_pool: Command_Pool,
	transfer_queue: Queue,
) -> (
	buffer: Index_Buffer,
) {
	size := cast(vk.DeviceSize)(size_of(INDICES[0]) * len(INDICES))

	staging := create_buffer(
		device,
		physical_device,
		size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	defer destroy_buffer(device, &staging)
	set_debug_name(device, staging, "buffer:transfer")
	set_debug_name(device, staging.memory, "buffer:transfer/memory")

	raw: [^]u16
	vk.MapMemory(device.handle, staging.memory.handle, 0, size, {}, cast(^rawptr)&raw)
	indices := slice.from_ptr(raw, len(INDICES))
	copy(indices, INDICES)
	vk.UnmapMemory(device.handle, staging.memory.handle)

	buffer.buffer = create_buffer(
		device,
		physical_device,
		size,
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)

	copy_buffer(device, transfer_pool, transfer_queue, staging, buffer, size)

	return
}

destroy_index_buffer :: proc(device: Device, buffer: ^Index_Buffer) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
