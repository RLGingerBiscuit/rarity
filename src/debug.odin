package rarity

import "base:intrinsics"
import "base:runtime"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"

_ :: intrinsics
_ :: runtime
_ :: log
_ :: mem
_ :: strings
_ :: vk

set_debug_name :: proc(
	device: Device,
	object: $T,
	name: string,
) where intrinsics.type_has_field(T, "handle") {
	when ENABLE_VALIDATION {
		type, ok := _type_map[T]
		log.assertf(ok, "You forgot to add {} to the debug type map", typeid_of(T))
		cname := strings.clone_to_cstring(name, context.temp_allocator)
		info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectType   = type,
			objectHandle = transmute(u64)object.handle,
			pObjectName  = cname,
		}
		CHECK(vk.SetDebugUtilsObjectNameEXT(device.handle, &info))
	}
}

debug_label_begin :: proc(cmd: Command_Buffer, label: string, colour: glm.vec3) {
	when ENABLE_VALIDATION {
		clabel := strings.clone_to_cstring(label, context.temp_allocator)
		col := colour.xyzz
		col.w = 1
		info := vk.DebugUtilsLabelEXT {
			sType      = .DEBUG_UTILS_LABEL_EXT,
			pLabelName = clabel,
			color      = col,
		}
		vk.CmdBeginDebugUtilsLabelEXT(cmd.handle, &info)
	}
}

debug_label_end :: proc(cmd: Command_Buffer) {
	when ENABLE_VALIDATION {
		vk.CmdEndDebugUtilsLabelEXT(cmd.handle)
	}
}


debug_label_insert :: proc(cmd: Command_Buffer, label: string, colour: glm.vec3) {
	when ENABLE_VALIDATION {
		clabel := strings.clone_to_cstring(label, context.temp_allocator)
		col := colour.xyzz
		col.w = 1
		info := vk.DebugUtilsLabelEXT {
			sType      = .DEBUG_UTILS_LABEL_EXT,
			pLabelName = clabel,
			color      = col,
		}
		vk.CmdBeginDebugUtilsLabelEXT(cmd.handle, &info)
	}
}

@(deferred_in = _deferred_debug_label_end)
debug_label :: proc(cmd: Command_Buffer, label: string, colour: glm.vec3) {
	debug_label_begin(cmd, label, colour)
}
_deferred_debug_label_end :: proc(cmd: Command_Buffer, _: string, _: glm.vec3) {
	debug_label_end(cmd)
}


when ENABLE_VALIDATION {
	@(private = "file")
	_type_map: map[typeid]vk.ObjectType
	@(private = "file")
	_arena: mem.Arena
	@(private = "file")
	_arena_data: [1 << 14]byte // If you add a type and it screams about it you many need to bump this

	@(private = "file", init)
	_init :: proc "contextless" () {
		context = runtime.default_context()
		mem.arena_init(&_arena, _arena_data[:])
		context.allocator = mem.arena_allocator(&_arena)
		_type_map = make(map[typeid]vk.ObjectType)
		_type_map[Instance] = .INSTANCE
		_type_map[Surface] = .SURFACE_KHR
		_type_map[Physical_Device] = .PHYSICAL_DEVICE
		_type_map[Device] = .DEVICE
		_type_map[Queue] = .QUEUE
		_type_map[Swapchain] = .SWAPCHAIN_KHR
		_type_map[Image] = .IMAGE
		_type_map[Image_View] = .IMAGE_VIEW
		_type_map[Pipeline] = .PIPELINE
		_type_map[Descriptor_Set_Layout] = .DESCRIPTOR_SET_LAYOUT
		_type_map[Pipeline_Layout] = .PIPELINE_LAYOUT
		_type_map[Shader_Module] = .SHADER_MODULE
		_type_map[Command_Pool] = .COMMAND_POOL
		_type_map[Buffer] = .BUFFER
		_type_map[Device_Memory] = .DEVICE_MEMORY
		_type_map[Vertex_Buffer] = .BUFFER
		_type_map[Index_Buffer] = .BUFFER
		_type_map[Descriptor_Pool] = .DESCRIPTOR_POOL
		_type_map[Descriptor_Set] = .DESCRIPTOR_SET
		_type_map[Uniform_Buffer(Uniforms)] = .BUFFER
		_type_map[Command_Buffer] = .COMMAND_BUFFER
		_type_map[Semaphore] = .SEMAPHORE
		_type_map[Fence] = .FENCE
	}

	@(private = "file", fini)
	_fini :: proc "contextless" () {
		context = runtime.default_context()
		context.allocator = mem.arena_allocator(&_arena)
		delete(_type_map)
	}
}
