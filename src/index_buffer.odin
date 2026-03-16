package rarity

import vk "vendor:vulkan"

Index_Buffer :: struct {
	using buffer: Buffer,
}

create_index_buffer :: proc(
	device: Device,
	physical_device: Physical_Device,
	indices: $S/[]$T,
	immediate_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
) -> (
	buffer: Index_Buffer,
) {
	size := cast(vk.DeviceSize)(size_of(T) * len(indices))

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

	mapped_indices := map_buffer_memory(T, device, staging, size)
	copy(mapped_indices, indices)
	defer unmap_buffer_memory(device, staging)

	buffer.buffer = create_buffer(
		device,
		physical_device,
		size,
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)

	copy_buffer(device, immediate_pool, immediate_fence, transfer_queue, staging, buffer, size)

	return
}

destroy_index_buffer :: proc(device: Device, buffer: ^Index_Buffer) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
