package rarity

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"


Instance :: struct {
	handle: vk.Instance,
}

create_instance :: proc(
	name: string,
	version: u32,
	engine_name: string,
	engine_version: u32,
	api_version: u32,
) -> (
	instance: Instance,
) {
	vk.load_proc_addresses(cast(rawptr)glfw.GetInstanceProcAddress)

	app_name := strings.clone_to_cstring(name, context.temp_allocator)
	engine_name := strings.clone_to_cstring(engine_name, context.temp_allocator)

	glfw_exts := glfw.GetRequiredInstanceExtensions()
	required_exts := make([dynamic]cstring, 0, len(glfw_exts) + 1, context.temp_allocator)
	append(&required_exts, ..glfw_exts)

	when ODIN_OS == .Darwin {
		append(&required_exts, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	avail_ext_count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &avail_ext_count, nil)
	avail_exts := make([]vk.ExtensionProperties, avail_ext_count, context.temp_allocator)
	vk.EnumerateInstanceExtensionProperties(nil, &avail_ext_count, raw_data(avail_exts))

	found_all := true
	needed_exts := make([dynamic]cstring, len(required_exts), context.temp_allocator)
	copy(needed_exts[:], required_exts[:])
	for ext in needed_exts {
		context.user_ptr = cast(rawptr)ext
		_, found := slice.linear_search_proc(
			avail_exts,
			proc(ext: vk.ExtensionProperties) -> bool {
				ext_name := ext.extensionName
				name := cstring(&ext_name[0])
				required_ext := cstring(context.user_ptr)
				return name == required_ext
			},
		)
		if found {
			log.debugf("Found required extension: '{}'", ext)
		} else {
			log.debugf("Could not find required extension: '{}'", ext)
			found_all = false
		}
	}

	if !found_all {
		log.fatal("Could not find required extensions")
		os.exit(1)
	}


	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = app_name,
		applicationVersion = api_version,
		pEngineName        = engine_name,
		engineVersion      = engine_version,
		apiVersion         = api_version,
	}

	instance_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = cast(u32)len(required_exts),
		ppEnabledExtensionNames = raw_data(required_exts),
		enabledLayerCount       = 0,
		ppEnabledLayerNames     = nil,
	}

	when ODIN_OS == .Darwin {
		instance_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
	}


	CHECK(vk.CreateInstance(&instance_info, nil, &instance.handle))
	log.info("Created Vulkan instance:", instance.handle)

	vk.load_proc_addresses_instance(instance.handle)

	return
}

destroy_instance :: proc(instance: ^Instance) {
	log.info("Destroying Vulkan instance")
	vk.DestroyInstance(instance.handle, nil)
	instance^ = {}
}

CHECK :: proc(result: vk.Result, message := #caller_expression(result)) {
	log.assert(result == .SUCCESS, message)
}
