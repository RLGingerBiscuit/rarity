package rarity

import vk "vendor:vulkan"

Index_Buffer :: struct {
	using buffer: Buffer,
}

create_index_buffer_with_length :: proc(
	device: Device,
	physical_device: Physical_Device,
	length: vk.DeviceSize,
	$I: typeid,
	usage := vk.BufferUsageFlags{.TRANSFER_DST},
	props := vk.MemoryPropertyFlags{.DEVICE_LOCAL},
) -> (
	buffer: Index_Buffer,
) {
	size := cast(vk.DeviceSize)(size_of(I) * length)

	buffer.buffer = create_buffer(device, physical_device, size, usage | {.INDEX_BUFFER}, props)

	return
}

create_index_buffer_with_init :: proc(
	device: Device,
	physical_device: Physical_Device,
	indices: []$I,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
	usage := vk.BufferUsageFlags{.TRANSFER_DST},
	props := vk.MemoryPropertyFlags{.DEVICE_LOCAL},
) -> (
	buffer: Index_Buffer,
) {
	size := cast(vk.DeviceSize)(size_of(I) * len(indices))

	buffer = create_index_buffer_with_length(
		device,
		physical_device,
		cast(vk.DeviceSize)len(indices),
		I,
		usage = usage,
		props = props,
	)

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

	mapped_indices := map_buffer_memory(I, device, staging, size)
	defer unmap_buffer_memory(device, staging)
	copy(mapped_indices, indices)

	copy_and_transfer_buffer(
		device,
		buffer,
		staging,
		immediate_pool,
		graphics_pool,
		immediate_fence,
		transfer_queue,
		graphics_queue,
	)

	return
}

create_index_buffer :: proc {
	create_index_buffer_with_length,
	create_index_buffer_with_init,
}

destroy_index_buffer :: proc(device: Device, buffer: ^Index_Buffer) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
