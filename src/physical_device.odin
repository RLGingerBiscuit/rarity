package rarity

import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import vk "vendor:vulkan"

Physical_Device :: struct {
	handle:         vk.PhysicalDevice,
	name:           string,
	indices:        Queue_Family_Indices,
}

choose_physical_device :: proc(instance: Instance, surface: Surface) -> (device: Physical_Device) {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance.handle, &device_count, nil)
	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
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
	device.indices = find_queue_families(device.handle, surface)

	log.infof(
		"Device '{}' selected (vendor '{}'; api ver. {}; driver ver. {})",
		device.name,
		vendor_id_to_string(props.vendorID),
		version_to_string(props.apiVersion),
		driver_version_to_string(props.vendorID, props.driverVersion),
	)

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
	features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
	}
	vk.GetPhysicalDeviceFeatures2(device, &features2)

	if !features2.features.samplerAnisotropy {
		return -1 // No bueno
	}

	if props.deviceType == .DISCRETE_GPU {
		score += 100
	}

	score += cast(int)props.limits.maxImageDimension2D

	return
}

version_to_string :: proc(ver: u32, allocator := context.temp_allocator) -> string {
	return fmt.aprintf(
		"{}.{}.{}",
		vk.VERSION_MAJOR(ver),
		vk.VERSION_MINOR(ver),
		vk.VERSION_PATCH(ver),
		allocator = allocator,
	)
}

vendor_id_to_string :: proc(vendor_id: u32) -> string {
	// odinfmt:disable
	switch vendor_id {
	case 0x1002:  return "AMD"
	case 0x1010:  return "ImgTec"
	case 0x106b:  return "Apple"
	case 0x10de:  return "NVIDIA"
	case 0x13B5:  return "ARM"
	case 0x144d:  return "Samsung"
	case 0x19e5:  return "Huawei Technologies"
	case 0x5143:  return "Qualcomm"
	case 0x8086:  return "INTEL"
	case 0x10005: return "Mesa"
	case:         return "Unknown"
	}
	// odinfmt:enable
}

driver_version_to_string :: proc(
	vendor_id: u32,
	ver: u32,
	allocator := context.temp_allocator,
) -> string {
	if vendor_id == 0x10de {
		// Why, NVIDIA, Why?
		return fmt.aprintf(
			"{}.{}.{}.{}",
			(ver >> 22) & 0x3ff,
			(ver >> 14) & 0xff,
			(ver >> 6) & 0xff,
			(ver) & 0x3f,
			allocator = allocator,
		)
	} else {
		return fmt.aprintf(
			"{}.{}.{}",
			vk.VERSION_MAJOR(ver),
			vk.VERSION_MINOR(ver),
			vk.VERSION_PATCH(ver),
			allocator = allocator,
		)
	}
}
