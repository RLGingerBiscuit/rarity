package rarity

import "core:log"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"

Vertex_Buffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
}

create_vertex_buffer :: proc(
	device: Device,
	physical_device: Physical_Device,
) -> (
	buffer: Vertex_Buffer,
) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = cast(vk.DeviceSize)(size_of(VERTICES[0]) * len(VERTICES)),
		usage       = {.VERTEX_BUFFER},
		sharingMode = .EXCLUSIVE,
	}

	CHECK(vk.CreateBuffer(device.handle, &create_info, nil, &buffer.handle))

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device.handle, buffer.handle, &requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = _find_memory_type(
			physical_device.handle,
			requirements.memoryTypeBits,
			{.HOST_VISIBLE, .HOST_COHERENT},
		),
	}

	CHECK(vk.AllocateMemory(device.handle, &alloc_info, nil, &buffer.memory))

	vk.BindBufferMemory(device.handle, buffer.handle, buffer.memory, 0)

	raw: [^]Vertex
	vk.MapMemory(device.handle, buffer.memory, 0, create_info.size, {}, cast(^rawptr)&raw)
	vertices := slice.from_ptr(raw, len(VERTICES))
	copy(vertices, VERTICES)
	vk.UnmapMemory(device.handle, buffer.memory)

	return
}

destroy_vertex_buffer :: proc(device: Device, buffer: ^Vertex_Buffer) {
	vk.DestroyBuffer(device.handle, buffer.handle, nil)
	vk.FreeMemory(device.handle, buffer.memory, nil)
	buffer^ = {}
}

_find_memory_type :: proc(
	physical_device: vk.PhysicalDevice,
	type: u32,
	flags: vk.MemoryPropertyFlags,
) -> u32 {
	props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &props)

	for i in 0 ..< props.memoryTypeCount {
		if type & (1 << i) > 0 && props.memoryTypes[i].propertyFlags & flags == flags {
			return i
		}
	}

	log.fatal("Could not find a suitable memory type")
	os.exit(1)
}
