package rarity

import vk "vendor:vulkan"

Device :: struct {
	handle:  vk.Device,
	indices: Queue_Family_Indices,
}

create_logical_device :: proc(physical_device: Physical_Device) -> (device: Device) {
	device.indices = find_queue_families(physical_device.handle)

	queue_priority: f32 = 1
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = device.indices.graphics.?,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	features := vk.PhysicalDeviceFeatures{}

	create_info := vk.DeviceCreateInfo {
		sType                = .DEVICE_CREATE_INFO,
		pQueueCreateInfos    = &queue_create_info,
		queueCreateInfoCount = 1,
		pEnabledFeatures     = &features,
	}

	CHECK(vk.CreateDevice(physical_device.handle, &create_info, nil, &device.handle))

	vk.load_proc_addresses(device.handle)

	return
}

destroy_logical_device :: proc(device: ^Device) {
	vk.DestroyDevice(device.handle, nil)
	device^ = {}
}
