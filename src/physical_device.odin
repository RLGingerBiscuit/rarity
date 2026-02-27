package rarity

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import vk "vendor:vulkan"

Physical_Device :: struct {
	handle:      vk.PhysicalDevice,
	name:        string,
	api_version: u32,
	indices:     Queue_Family_Indices,
}

choose_physical_device :: proc(instance: Instance, surface: Surface) -> (device: Physical_Device) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance.handle, &device_count, nil)
	devices := make([dynamic]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(instance.handle, &device_count, raw_data(devices))

	best_score: int = 0
	best_device: vk.PhysicalDevice

	for device in devices {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)
		log.debug("Device found:", cstring(&props.deviceName[0]))

		score := _rate_physical_device(device, surface)
		if score > best_score {
			best_score = score
			best_device = device
		}
	}

	if best_device == nil {
		log.fatal("Could not find a suitable device")
		os.exit(1)
	}

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(best_device, &props)

	device.handle = best_device
	device.name = strings.clone_from(cstring(&props.deviceName[0]))
	device.api_version = props.apiVersion
	device.indices = find_queue_families(device.handle, surface)

	log.infof("Device '{}' selected", device.name)

	return
}

destroy_physical_device :: proc(device: ^Physical_Device) {
	delete(device.name)
	device^ = {}
}

_rate_physical_device :: proc(device: vk.PhysicalDevice, surface: Surface) -> (score: int) {
	indices := find_queue_families(device, surface)
	if !queue_families_is_complete(indices) {
		return -1 // No bueno
	}

	required_exts := device_extensions

	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)
	avail_exts := make([]vk.ExtensionProperties, ext_count, context.temp_allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, raw_data(avail_exts))

	found_all := true
	needed_exts := make([dynamic]cstring, 0, len(required_exts), context.temp_allocator)
	append(&needed_exts, ..required_exts[:])
	for ext in needed_exts {
		context.user_ptr = cast(rawptr)ext
		_, found := slice.linear_search_proc(
			avail_exts,
			proc(ext: vk.ExtensionProperties) -> bool {
				ext := ext
				name := cstring(&ext.extensionName[0])
				required_ext := cstring(context.user_ptr)
				return name == required_ext
			},
		)
		if !found {
			found_all = false
			break
		}
	}

	if !found_all {
		return -1 // No bueno
	}

	support := _query_swapchain_support(device, surface)
	if len(support.formats) == 0 || len(support.present_modes) == 0 {
		return -1 // No bueno
	}

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &props)

	if props.deviceType == .DISCRETE_GPU {
		score += 100
	}

	score += cast(int)props.limits.maxImageDimension2D

	return
}
