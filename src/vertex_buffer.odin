package rarity

import vk "vendor:vulkan"

Vertex_Buffer :: struct($V: typeid) {
	using buffer: Buffer,
}

create_vertex_buffer_with_length :: proc(
	device: Device,
	physical_device: Physical_Device,
	length: vk.DeviceSize,
	$V: typeid,
	usage := vk.BufferUsageFlags{.TRANSFER_DST},
	props := vk.MemoryPropertyFlags{.DEVICE_LOCAL},
) -> (
	buffer: Vertex_Buffer(V),
) {
	size := cast(vk.DeviceSize)(size_of(V) * length)

	buffer.buffer = create_buffer(device, physical_device, size, usage | {.VERTEX_BUFFER}, props)

	return
}

create_vertex_buffer_with_init :: proc(
	device: Device,
	physical_device: Physical_Device,
	vertices: []$V,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
	usage := vk.BufferUsageFlags{.TRANSFER_DST},
	props := vk.MemoryPropertyFlags{.DEVICE_LOCAL},
) -> (
	buffer: Vertex_Buffer(V),
) {
	size := cast(vk.DeviceSize)(size_of(V) * len(vertices))

	buffer = create_vertex_buffer_with_length(
		device,
		physical_device,
		cast(vk.DeviceSize)len(vertices),
		V,
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

	mapped_vertices := map_buffer_memory(V, device, staging, size)
	defer unmap_buffer_memory(device, staging)
	copy(mapped_vertices, vertices)

	copy_and_transfer_buffer(
		device,
		buffer,
		staging,
		immediate_pool,
		graphics_pool,
		immediate_fence,
		transfer_queue,
		graphics_queue,
		{.VERTEX_ATTRIBUTE_READ},
		{.VERTEX_INPUT},
	)

	return
}

create_vertex_buffer :: proc {
	create_vertex_buffer_with_length,
	create_vertex_buffer_with_init,
}

destroy_vertex_buffer :: proc(device: Device, buffer: ^Vertex_Buffer($V)) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
