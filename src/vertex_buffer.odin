package rarity

import "core:slice"
import vk "vendor:vulkan"

Vertex_Buffer :: struct {
	using buffer: Buffer,
}

create_vertex_buffer :: proc(
	device: Device,
	physical_device: Physical_Device,
	transfer_pool: Command_Pool,
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

	raw: [^]Vertex
	vk.MapMemory(device.handle, staging.memory.handle, 0, size, {}, cast(^rawptr)&raw)
	vertices := slice.from_ptr(raw, len(VERTICES))
	copy(vertices, VERTICES)
	vk.UnmapMemory(device.handle, staging.memory.handle)

	buffer.buffer = create_buffer(
		device,
		physical_device,
		size,
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)

	copy_buffer(device, transfer_pool, transfer_queue, staging, buffer, size)

	return
}

destroy_vertex_buffer :: proc(device: Device, buffer: ^Vertex_Buffer) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
