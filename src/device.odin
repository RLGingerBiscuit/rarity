package rarity

import "core:slice"
import vk "vendor:vulkan"

@(rodata)
required_device_extensions := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME,
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

	queue_family_indices: [dynamic; 3]u32
	append(&queue_family_indices, device.indices.graphics.?)
	if !slice.contains(queue_family_indices[:], device.indices.present.?) {
		append(&queue_family_indices, device.indices.present.?)
	}
	if !slice.contains(queue_family_indices[:], device.indices.transfer.?) {
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

	// Checks have already been done when choosing the device
	v12_features := vk.PhysicalDeviceVulkan12Features {
		sType                       = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		separateDepthStencilLayouts = true,
	}
	v13_features := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		pNext            = &v12_features,
		dynamicRendering = true,
		synchronization2 = true,
	}
	features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &v13_features,
		features = {samplerAnisotropy = true},
	}

	device_exts := make(
		[dynamic]cstring,
		0,
		len(required_device_extensions) + 1,
		context.temp_allocator,
	)
	append(&device_exts, ..required_device_extensions)
	when ODIN_OS == .Darwin {
		append(&device_exts, vk.KHR_PORTABILITY_SUBSET_EXTENSION_NAME)
	}

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &features2,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = cast(u32)len(queue_create_infos),
		ppEnabledExtensionNames = raw_data(device_exts),
		enabledExtensionCount   = cast(u32)len(device_exts),
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
	CHECK(vk.DeviceWaitIdle(device.handle))
}
