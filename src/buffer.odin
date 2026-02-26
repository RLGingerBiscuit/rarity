package rarity

import "core:log"
import "core:os"
import vk "vendor:vulkan"

Buffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
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

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = _find_memory_type(
			physical_device.handle,
			requirements.memoryTypeBits,
			props,
		),
	}

	CHECK(vk.AllocateMemory(device.handle, &alloc_info, nil, &buffer.memory))

	vk.BindBufferMemory(device.handle, buffer.handle, buffer.memory, 0)

	return
}

destroy_buffer :: proc(device: Device, buffer: ^Buffer) {
	vk.DestroyBuffer(device.handle, buffer.handle, nil)
	vk.FreeMemory(device.handle, buffer.memory, nil)
	buffer^ = {}
}

copy_buffer :: proc(
	device: Device,
	transfer_pool: Command_Pool,
	transfer_queue: Queue,
	src, dst: Buffer,
	size: vk.DeviceSize,
) {
	cmd := allocate_command_buffer(device, transfer_pool)
	defer free_command_buffer(device, transfer_pool, &cmd)

	command_buffer_begin(cmd, {.ONE_TIME_SUBMIT})
	region := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(cmd.handle, src.handle, dst.handle, 1, &region)
	command_buffer_end(cmd)

	queue_submit_simple(transfer_queue, &cmd)
	queue_wait_idle(transfer_queue)
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
