package rarity

import "core:log"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"

Buffer :: struct {
	handle: vk.Buffer,
	memory: Device_Memory,
}

create_buffer :: proc(
	device: Device,
	physical_device: Physical_Device,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	props: vk.MemoryPropertyFlags,
) -> (
	buffer: Buffer,
) {
	create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	CHECK(vk.CreateBuffer(device.handle, &create_info, nil, &buffer.handle))

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device.handle, buffer.handle, &requirements)

	allocate_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = _find_memory_type(
			physical_device.handle,
			requirements.memoryTypeBits,
			props,
		),
	}

	CHECK(vk.AllocateMemory(device.handle, &allocate_info, nil, &buffer.memory.handle))

	CHECK(vk.BindBufferMemory(device.handle, buffer.handle, buffer.memory.handle, 0))

	return
}

destroy_buffer :: proc(device: Device, buffer: ^Buffer) {
	vk.DestroyBuffer(device.handle, buffer.handle, nil)
	vk.FreeMemory(device.handle, buffer.memory.handle, nil)
	buffer^ = {}
}

map_buffer_memory :: proc($T: typeid, device: Device, buffer: Buffer, #any_int size: int) -> []T {
	log.assert(size % size_of(T) == 0)
	raw: [^]T
	len := size / size_of(T)
	CHECK(
		vk.MapMemory(
			device.handle,
			buffer.memory.handle,
			0,
			cast(vk.DeviceSize)size,
			{},
			cast(^rawptr)&raw,
		),
	)
	sliced := slice.from_ptr(raw, len)
	return sliced
}

unmap_buffer_memory :: proc(device: Device, buffer: Buffer) {
	vk.UnmapMemory(device.handle, buffer.memory.handle)
}

copy_buffer :: proc(
	device: Device,
	pool: Command_Pool,
	fence: Fence,
	queue: Queue,
	src, dst: Buffer,
	size: vk.DeviceSize,
) {
	cmd := immediate_guard(device, pool, queue, fence)
	debug_label_guard(cmd, "Transfer Copy", {0.5, 0.1, 1.0})

	region := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(cmd.handle, src.handle, dst.handle, 1, &region)
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
