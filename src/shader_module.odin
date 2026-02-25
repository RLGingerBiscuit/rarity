package rarity

import vk "vendor:vulkan"

Shader_Module :: struct {
	handle: vk.ShaderModule,
}

create_shader_module :: proc(device: Device, spirv_data: []byte) -> (module: Shader_Module) {
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(spirv_data),
		pCode    = cast(^u32)raw_data(spirv_data),
	}

	CHECK(vk.CreateShaderModule(device.handle, &create_info, nil, &module.handle))

	return
}

destroy_shader_module :: proc(device: Device, module: ^Shader_Module) {
	vk.DestroyShaderModule(device.handle, module.handle, nil)
	module^ = {}
}
