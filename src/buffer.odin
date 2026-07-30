package rarity

import "core:log"
import "core:os"
import "core:slice"
import vk "vendor:vulkan"

Buffer :: struct {
	handle: vk.Buffer,
	memory: Device_Memory,
	size:   vk.DeviceSize,
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

	buffer.size = size

	return
}

destroy_buffer :: proc(device: Device, buffer: ^Buffer) {
	vk.DestroyBuffer(device.handle, buffer.handle, nil)
	vk.FreeMemory(device.handle, buffer.memory.handle, nil)
	buffer^ = {}
}

map_buffer_memory :: proc(
	$T: typeid,
	device: Device,
	buffer: Buffer,
	#any_int size: int,
	loc := #caller_location,
) -> []T {
	log.assert(size % size_of(T) == 0, loc = loc)
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
	cmd_copy_buffer(cmd, src, dst, size)
}

copy_and_transfer_buffer :: proc(
	device: Device,
	buffer: Buffer,
	staging: Buffer,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
) {
	{
		cmd := immediate_guard(device, immediate_pool, transfer_queue, immediate_fence)
		cmd_copy_buffer(cmd, staging, buffer, buffer.size)
		if transfer_queue.family != graphics_queue.family {
			cmd_buffer_barrier(
				cmd,
				buffer,
				{.TRANSFER_WRITE},
				{},
				{.TRANSFER},
				{},
				size = buffer.size,
				src_family = transfer_queue.family,
				dst_family = graphics_queue.family,
			)
		}
	}
	if transfer_queue.family != graphics_queue.family {
		cmd := immediate_guard(device, graphics_pool, graphics_queue, immediate_fence)
		cmd_buffer_barrier(
			cmd,
			buffer,
			{},
			{.VERTEX_ATTRIBUTE_READ},
			{},
			{.VERTEX_INPUT},
			size = buffer.size,
			src_family = transfer_queue.family,
			dst_family = graphics_queue.family,
		)
	}
}

cmd_copy_buffer :: proc(cmd: Command_Buffer, src, dst: Buffer, size: vk.DeviceSize) {
	debug_label_guard(cmd, "Transfer Copy", {0.5, 0.1, 1.0})

	region := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(cmd.handle, src.handle, dst.handle, 1, &region)
}

cmd_buffer_barrier :: proc(
	cmd: Command_Buffer,
	buffer: Buffer,
	src_access, dst_access: vk.AccessFlags2,
	src_stage, dst_stage: vk.PipelineStageFlags2,
	size: vk.DeviceSize,
	offset: vk.DeviceSize = 0,
	src_family := vk.QUEUE_FAMILY_IGNORED,
	dst_family := vk.QUEUE_FAMILY_IGNORED,
) {
	debug_label_guard(cmd, "Buffer Transition", {1.0, 0.5, 0.1})

	barrier := vk.BufferMemoryBarrier2 {
		sType               = .BUFFER_MEMORY_BARRIER_2,
		buffer              = buffer.handle,
		srcAccessMask       = src_access,
		dstAccessMask       = dst_access,
		srcStageMask        = src_stage,
		dstStageMask        = dst_stage,
		srcQueueFamilyIndex = src_family,
		dstQueueFamilyIndex = dst_family,
		offset              = offset,
		size                = size,
	}
	dependency := vk.DependencyInfo {
		sType                    = .DEPENDENCY_INFO,
		bufferMemoryBarrierCount = 1,
		pBufferMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(cmd.handle, &dependency)
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
