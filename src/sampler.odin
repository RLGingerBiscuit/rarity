package rarity

import vk "vendor:vulkan"

Sampler :: struct {
	handle:   vk.Sampler,
	min, mag: vk.Filter,
	mip:      vk.SamplerMipmapMode,
	u, v:     vk.SamplerAddressMode,
}

create_sampler :: proc(
	device: Device,
	physical_device: Physical_Device,
	min, mag: vk.Filter,
	mip := vk.SamplerMipmapMode.LINEAR,
	u := vk.SamplerAddressMode.REPEAT,
	v := vk.SamplerAddressMode.REPEAT,
) -> (
	sampler: Sampler,
) {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device.handle, &props)

	create_info := vk.SamplerCreateInfo {
		sType            = .SAMPLER_CREATE_INFO,
		minFilter        = min,
		magFilter        = mag,
		mipmapMode       = mip,
		addressModeU     = u,
		addressModeV     = v,
		anisotropyEnable = true,
		maxAnisotropy    = props.limits.maxSamplerAnisotropy,
		compareEnable    = false,
		compareOp        = .ALWAYS,
		borderColor      = .INT_OPAQUE_BLACK,
		mipLodBias       = 0,
		minLod           = 0,
		maxLod           = vk.LOD_CLAMP_NONE,
	}

	CHECK(vk.CreateSampler(device.handle, &create_info, nil, &sampler.handle))

	sampler.min = min
	sampler.mag = mag
	sampler.mip = mip
	sampler.u = u
	sampler.v = v
	return
}

destroy_sampler :: proc(device: Device, sampler: ^Sampler) {
	vk.DestroySampler(device.handle, sampler.handle, nil)
	sampler^ = {}
}
