package rarity

import vk "vendor:vulkan"

Queue_Family_Indices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
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

	for i in 0 ..< queue_family_count {
		queue_family := queue_families[i]
		if .GRAPHICS in queue_family.queueFlags {
			indices.graphics = i
		}

		supports_present: b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, i, surface.handle, &supports_present)
		if supports_present {
			indices.present = i
		}
	}

	return
}

queue_families_is_complete :: proc(indices: Queue_Family_Indices) -> bool {
	_, has_graphics := indices.graphics.?
	_, has_present := indices.present.?
	return has_graphics && has_present
}
