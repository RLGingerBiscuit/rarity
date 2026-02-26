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

	queue_families := []u32 {
		device.indices.graphics.?,
		device.indices.present.?,
		device.indices.transfer.?,
	}
	queue_create_infos := make(
		[dynamic]vk.DeviceQueueCreateInfo,
		0,
		len(queue_families),
		context.temp_allocator,
	)

	queue_priority: f32 = 1

	for queue_family in queue_families {
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

	features := vk.PhysicalDeviceFeatures{}

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = cast(u32)len(queue_create_infos),
		pEnabledFeatures        = &features,
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
