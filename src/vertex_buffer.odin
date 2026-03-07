package rarity

import vk "vendor:vulkan"

Vertex_Buffer :: struct {
	using buffer: Buffer,
}

create_vertex_buffer :: proc(
	device: Device,
	physical_device: Physical_Device,
	immediate_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
) -> (
	buffer: Vertex_Buffer,
) {
	size := cast(vk.DeviceSize)(size_of(VERTICES[0]) * len(VERTICES))

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

	vertices := map_buffer_memory(Vertex, device, staging, size)
	defer unmap_buffer_memory(device, staging)
	copy(vertices, VERTICES)

	buffer.buffer = create_buffer(
		device,
		physical_device,
		size,
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)

	copy_buffer(device, immediate_pool, immediate_fence, transfer_queue, staging, buffer, size)

	return
}

destroy_vertex_buffer :: proc(device: Device, buffer: ^Vertex_Buffer) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
