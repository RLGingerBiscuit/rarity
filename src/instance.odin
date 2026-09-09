package rarity

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

ENABLE_VALIDATION :: #config(VALIDATION, ODIN_DEBUG)

Instance :: struct {
	handle:       vk.Instance,
	debug:        vk.DebugUtilsMessengerEXT,
	debug_logger: ^log.Logger,
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

	when ENABLE_VALIDATION {
		append(&required_exts, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	avail_ext_count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &avail_ext_count, nil)
	avail_exts := make([]vk.ExtensionProperties, avail_ext_count, context.temp_allocator)
	vk.EnumerateInstanceExtensionProperties(nil, &avail_ext_count, raw_data(avail_exts))

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

	required_layers := make([dynamic]cstring, context.temp_allocator)
	when ENABLE_VALIDATION {
		append(&required_layers, "VK_LAYER_KHRONOS_validation")
	}

	avail_layer_count: u32
	vk.EnumerateInstanceLayerProperties(&avail_layer_count, nil)
	avail_layers := make([]vk.LayerProperties, avail_layer_count, context.temp_allocator)
	vk.EnumerateInstanceLayerProperties(&avail_layer_count, raw_data(avail_layers))

	layers := make([dynamic]cstring, 0, len(required_layers), context.temp_allocator)
	for layer in required_layers {
		context.user_ptr = cast(rawptr)layer
		_, found := slice.linear_search_proc(
			avail_layers,
			proc(layer: vk.LayerProperties) -> bool {
				layer_name := layer.layerName
				name := cstring(&layer_name[0])
				required_layer := cstring(context.user_ptr)
				return name == required_layer
			},
		)
		if found {
			log.debugf("Found required layer: '{}'", layer)
			append(&layers, layer)
		} else {
			when ENABLE_VALIDATION {
				log.warnf("Could not find validation layer '{}', continuing without", layer)
			} else {
				log.fatalf("Could not find required layer: '{}'", layer)
				os.exit(1)
			}
		}
	}

	exts := make([dynamic]cstring, 0, len(required_exts), context.temp_allocator)
	append(&exts, ..required_exts[:])

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = app_name,
		applicationVersion = version,
		pEngineName        = engine_name,
		engineVersion      = engine_version,
		apiVersion         = api_version,
	}

	instance_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = cast(u32)len(exts),
		ppEnabledExtensionNames = raw_data(exts),
		enabledLayerCount       = cast(u32)len(layers),
		ppEnabledLayerNames     = raw_data(layers),
	}

	when ODIN_OS == .Darwin {
		instance_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
	}

	// Technically don't need this out here 'cause when isn't actually scoped but it soothes the mind
	debug_info: vk.DebugUtilsMessengerCreateInfoEXT
	_ = debug_info
	when ENABLE_VALIDATION {
		instance.debug_logger = new(log.Logger)
		instance.debug_logger^ = log.create_console_logger(
			.Debug,
			opt = log.Default_Console_Logger_Opts ~ {.Short_File_Path, .Line, .Procedure},
			ident = "vulkan",
		)

		debug_info = vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .WARNING, .ERROR},
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = _debug_callback,
			pUserData       = cast(rawptr)instance.debug_logger,
		}
		instance_info.pNext = &debug_info
	}

	CHECK(vk.CreateInstance(&instance_info, nil, &instance.handle))
	log.info("Created Vulkan instance:", instance.handle)

	vk.load_proc_addresses_instance(instance.handle)

	when ENABLE_VALIDATION {
		CHECK(vk.CreateDebugUtilsMessengerEXT(instance.handle, &debug_info, nil, &instance.debug))
	}

	return
}

destroy_instance :: proc(instance: ^Instance) {
	log.info("Destroying Vulkan instance")
	when ENABLE_VALIDATION {
		vk.DestroyDebugUtilsMessengerEXT(instance.handle, instance.debug, nil)
	}
	vk.DestroyInstance(instance.handle, nil)
	when ENABLE_VALIDATION {
		log.destroy_console_logger(instance.debug_logger^)
		free(instance.debug_logger)
	}
	instance^ = {}
}

CHECK :: proc(result: vk.Result, message := #caller_expression(result), loc := #caller_location) {
	log.ensuref(result == .SUCCESS, "{}: {}", message, result, loc = loc)
}

@(private = "file")
_debug_callback :: proc "system" (
	severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	types: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = default_context()
	context.logger = (cast(^log.Logger)user_data)^

	level: log.Level
	if .VERBOSE in severity {
		level = .Debug
	} else if .INFO in severity {
		level = .Info
	} else if .WARNING in severity {
		level = .Warning
	} else if .ERROR in severity {
		level = .Error
	}

	type: string
	if .GENERAL in types {
		type = "general"
	} else if .VALIDATION in types {
		type = "validation"
	} else if .PERFORMANCE in types {
		type = "performance"
	} else if .DEVICE_ADDRESS_BINDING in types {
		type = "binding"
	}

	log.logf(level, "[{}]: {}", type, callback_data.pMessage)

	return false
}
