package rarity

import vk "vendor:vulkan"

Uniform_Buffer :: struct($T: typeid) {
	using buffer: Buffer,
	mapped:       ^T,
}

create_uniform_buffer :: proc(
	$T: typeid,
	device: Device,
	physical_device: Physical_Device,
) -> (
	buffer: Uniform_Buffer(T),
) {
	size :: cast(vk.DeviceSize)size_of(T)

	buffer.buffer = create_buffer(
		device,
		physical_device,
		size,
		{.UNIFORM_BUFFER},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	sliced := map_buffer_memory(T, device, buffer, size)
	buffer.mapped = &sliced[0]

	return
}

destroy_uniform_buffer :: proc(device: Device, buffer: ^Uniform_Buffer($T)) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
