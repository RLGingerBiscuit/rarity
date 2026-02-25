package rarity

import "core:log"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"

Physical_Device :: struct {
	handle:      vk.PhysicalDevice,
	name:        string,
	api_version: u32,
}

choose_physical_device :: proc(instance: Instance) -> (device: Physical_Device) {
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

		score := _rate_physical_device(device)
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

	log.infof("Device '{}' selected", device.name)

	return
}

destroy_physical_device :: proc(device: ^Physical_Device) {
	delete(device.name)
	device^ = {}
}

_rate_physical_device :: proc(device: vk.PhysicalDevice) -> (score: int) {
	queue_families := find_queue_families(device)
	if !queue_families_is_complete(queue_families) {
		return -1 // No bueno
	}

	props: vk.PhysicalDeviceProperties
	features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceProperties(device, &props)
	vk.GetPhysicalDeviceFeatures(device, &features)

	if props.deviceType == .DISCRETE_GPU {
		score += 100
	}

	score += cast(int)props.limits.maxImageDimension2D

	return
}
