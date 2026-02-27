package rarity

import "core:log"
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

	vk.MapMemory(device.handle, buffer.memory.handle, 0, size, {}, cast(^rawptr)&buffer.mapped)

	return
}

populate_uniform_sets :: proc(
	device: Device,
	sets: []Descriptor_Set,
	uniforms: []Uniform_Buffer($T),
) {
	log.assert(len(sets) == len(uniforms))

	size :: size_of(T)

	writes := make([]vk.WriteDescriptorSet, len(uniforms), context.temp_allocator)

	for i in 0 ..< len(sets) {
		info := vk.DescriptorBufferInfo {
			buffer = uniforms[i].handle,
			offset = 0,
			range  = cast(vk.DeviceSize)size,
		}
		write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = sets[i].handle,
			dstBinding      = 0,
			dstArrayElement = 0,
			descriptorType  = .UNIFORM_BUFFER,
			descriptorCount = 1,
			pBufferInfo     = &info,
		}
		writes[i] = write
	}

	vk.UpdateDescriptorSets(device.handle, cast(u32)len(writes), raw_data(writes), 0, nil)
}

destroy_uniform_buffer :: proc(device: Device, buffer: ^Uniform_Buffer($T)) {
	destroy_buffer(device, &buffer.buffer)
	buffer^ = {}
}
