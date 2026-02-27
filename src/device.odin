package rarity

import vk "vendor:vulkan"

@(rodata)
device_extensions := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME, // required by slang
}

Device :: struct {
	handle:  vk.Device,
	indices: Queue_Family_Indices,
}

Device_Memory :: struct {
	handle: vk.DeviceMemory,
}

create_logical_device :: proc(physical_device: Physical_Device) -> (device: Device) {
	device.indices = physical_device.indices

	queue_family_indices := make([dynamic]u32, 0, 3, context.temp_allocator)
	append(&queue_family_indices, device.indices.graphics.?, device.indices.present.?)
	if device.indices.transfer != device.indices.graphics {
		append(&queue_family_indices, device.indices.transfer.?)
	}

	queue_create_infos := make(
		[dynamic]vk.DeviceQueueCreateInfo,
		0,
		len(queue_family_indices),
		context.temp_allocator,
	)

	queue_priority: f32 = 1

	for queue_family in queue_family_indices {
		append(
			&queue_create_infos,
			vk.DeviceQueueCreateInfo {
				sType = .DEVICE_QUEUE_CREATE_INFO,
				queueFamilyIndex = queue_family,
				queueCount = 1,
				pQueuePriorities = &queue_priority,
			},
		)

	}

	features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
	}
	vk.GetPhysicalDeviceFeatures2(physical_device.handle, &features2)

	v13_features := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType                = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		extendedDynamicState = true,
	}

	v13_features.pNext = &state_features
	features2.pNext = &v13_features

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features2,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = cast(u32)len(queue_create_infos),
		ppEnabledExtensionNames = raw_data(device_extensions),
		enabledExtensionCount   = cast(u32)len(device_extensions),
	}

	CHECK(vk.CreateDevice(physical_device.handle, &create_info, nil, &device.handle))

	vk.load_proc_addresses(device.handle)

	return
}

destroy_logical_device :: proc(device: ^Device) {
	vk.DestroyDevice(device.handle, nil)
	device^ = {}
}

device_wait_idle :: proc(device: Device) {
	vk.DeviceWaitIdle(device.handle)
}
