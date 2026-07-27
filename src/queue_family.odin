package rarity

import vk "vendor:vulkan"

Queue_Family_Indices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
	transfer: Maybe(u32),
}

find_queue_families :: proc(
	device: vk.PhysicalDevice,
	surface: Surface,
) -> (
	indices: Queue_Family_Indices,
) {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		device,
		&queue_family_count,
		raw_data(queue_families),
	)

	first_graphics: Maybe(u32)
	first_present: Maybe(u32)
	graphics_present: Maybe(u32)
	dedicated_transfer: Maybe(u32)

	for i in 0 ..< queue_family_count {
		queue_family := queue_families[i]

		has_graphics := .GRAPHICS in queue_family.queueFlags
		has_transfer := .TRANSFER in queue_family.queueFlags

		supports_present: b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, i, surface.handle, &supports_present)

		if has_graphics && first_graphics == nil {
			first_graphics = i
		}

		if supports_present && first_present == nil {
			first_present = i
		}

		if has_graphics && supports_present && graphics_present == nil {
			graphics_present = i
		}

		if has_transfer && !has_graphics && dedicated_transfer == nil {
			dedicated_transfer = i
		}
	}

	if graphics_present != nil {
		indices.graphics = graphics_present
		indices.present = graphics_present
	} else {
		indices.graphics = first_graphics
		indices.present = first_present
	}

	if dedicated_transfer != nil {
		indices.transfer = dedicated_transfer
	} else {
		indices.transfer = indices.graphics
	}

	return
}

queue_families_is_complete :: proc(indices: Queue_Family_Indices) -> bool {
	_, has_graphics := indices.graphics.?
	_, has_present := indices.present.?
	_, has_transfer := indices.transfer.?
	return has_graphics && has_present && has_transfer
}
