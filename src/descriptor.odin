package rarity

import "core:slice"
import vk "vendor:vulkan"

Descriptor_Pool :: struct {
	handle: vk.DescriptorPool,
}

Descriptor_Set :: struct {
	handle: vk.DescriptorSet,
}

Descriptor_Set_Layout :: struct {
	handle: vk.DescriptorSetLayout,
}

create_descriptor_pool :: proc(device: Device, swapchain: Swapchain) -> (pool: Descriptor_Pool) {
	size := vk.DescriptorPoolSize {
		type            = .UNIFORM_BUFFER,
		descriptorCount = cast(u32)swapchain.max_frames_in_flight,
	}

	create_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = 1,
		pPoolSizes    = &size,
		maxSets       = cast(u32)swapchain.max_frames_in_flight,
	}

	CHECK(vk.CreateDescriptorPool(device.handle, &create_info, nil, &pool.handle))

	return
}

destroy_descriptor_pool :: proc(device: Device, pool: ^Descriptor_Pool) {
	vk.DestroyDescriptorPool(device.handle, pool.handle, nil)
	pool^ = {}
}

allocate_descriptor_sets :: proc(
	device: Device,
	pool: Descriptor_Pool,
	layout: Descriptor_Set_Layout,
	count: int,
) -> (
	sets: []Descriptor_Set,
) {
	sets = make([]Descriptor_Set, count)

	layouts := make([]vk.DescriptorSetLayout, count, context.temp_allocator)
	slice.fill(layouts, layout.handle)

	vsets := make([]vk.DescriptorSet, count, context.temp_allocator)

	allocate_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool.handle,
		descriptorSetCount = cast(u32)len(layouts),
		pSetLayouts        = raw_data(layouts),
	}

	CHECK(vk.AllocateDescriptorSets(device.handle, &allocate_info, raw_data(vsets)))

	for i in 0 ..< count {
		sets[i] = Descriptor_Set {
			handle = vsets[i],
		}
	}

	return
}

create_descriptor_set_layout :: proc(device: Device) -> (layout: Descriptor_Set_Layout) {
	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorCount = 1,
		descriptorType  = .UNIFORM_BUFFER,
		stageFlags      = {.VERTEX},
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
	}

	CHECK(vk.CreateDescriptorSetLayout(device.handle, &create_info, nil, &layout.handle))

	return
}

destroy_descriptor_set_layout :: proc(device: Device, layout: ^Descriptor_Set_Layout) {
	vk.DestroyDescriptorSetLayout(device.handle, layout.handle, nil)
	layout^ = {}
}
