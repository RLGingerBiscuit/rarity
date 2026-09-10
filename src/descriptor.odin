package rarity

import "core:log"
import "core:slice"
import vk "vendor:vulkan"
_ :: log

Descriptor_Pool :: struct {
	handle: vk.DescriptorPool,
}

Descriptor_Set :: struct {
	handle: vk.DescriptorSet,
}

Descriptor_Set_Layout :: struct {
	handle: vk.DescriptorSetLayout,
}

Descriptor_Binding_Info :: struct {
	binding: u32,
	type:    vk.DescriptorType,
	count:   u32,
	stages:  vk.ShaderStageFlags,
}

Descriptor_Set_Layout_Info :: struct {
	bindings: []Descriptor_Binding_Info,
}

create_descriptor_pool :: proc(device: Device, swapchain: Swapchain) -> (pool: Descriptor_Pool) {
	sizes := []vk.DescriptorPoolSize {
		{
			type = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 64 * MAX_FRAMES_IN_FLIGHT,
		},
	}

	create_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = cast(u32)len(sizes),
		pPoolSizes    = raw_data(sizes),
		maxSets       = 64 * MAX_FRAMES_IN_FLIGHT,
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
	loc := #caller_location,
) -> (
	sets: []Descriptor_Set,
) {
	sets = make([]Descriptor_Set, count, loc = loc)

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

populate_descriptor_sets :: proc(
	device: Device,
	sets: []Descriptor_Set,
	image_view: Image_View,
	sampler: Sampler,
	image_layout := vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL,
) {
	infos := make([]vk.DescriptorImageInfo, len(sets), context.temp_allocator)
	writes := make([]vk.WriteDescriptorSet, len(sets), context.temp_allocator)

	for i in 0 ..< len(sets) {
		infos[i] = vk.DescriptorImageInfo {
			imageLayout = image_layout,
			imageView   = image_view.handle,
			sampler     = sampler.handle,
		}
		writes[i] = vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = sets[i].handle,
			dstBinding      = 0,
			dstArrayElement = 0,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			pImageInfo      = &infos[i],
		}
	}

	vk.UpdateDescriptorSets(device.handle, cast(u32)len(writes), raw_data(writes), 0, nil)
}

create_descriptor_set_layout :: proc(
	device: Device,
	info: Descriptor_Set_Layout_Info,
) -> (
	layout: Descriptor_Set_Layout,
) {
	bindings := make([]vk.DescriptorSetLayoutBinding, len(info.bindings), context.temp_allocator)
	for binding, i in info.bindings {
		bindings[i] = {
			binding         = binding.binding,
			descriptorCount = binding.count,
			descriptorType  = binding.type,
			stageFlags      = binding.stages,
		}
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = cast(u32)len(bindings),
		pBindings    = raw_data(bindings),
	}

	CHECK(vk.CreateDescriptorSetLayout(device.handle, &create_info, nil, &layout.handle))

	return
}

create_sampled_image_set_layout :: proc(
	device: Device,
	stages := vk.ShaderStageFlags{.FRAGMENT},
) -> (
	layout: Descriptor_Set_Layout,
) {
	bindings := []Descriptor_Binding_Info {
		{binding = 0, type = .COMBINED_IMAGE_SAMPLER, count = 1, stages = stages},
	}
	return create_descriptor_set_layout(device, {bindings = bindings})
}

destroy_descriptor_set_layout :: proc(device: Device, layout: ^Descriptor_Set_Layout) {
	vk.DestroyDescriptorSetLayout(device.handle, layout.handle, nil)
	layout^ = {}
}
