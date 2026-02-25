package rarity

import vk "vendor:vulkan"

Framebuffer :: struct {
	handle: vk.Framebuffer,
}

create_framebuffer :: proc(
	device: Device,
	swapchain: Swapchain,
	pass: Render_Pass,
	view: Image_View,
) -> (
	framebuffer: Framebuffer,
) {
	attachments := []vk.ImageView{view.handle}

	create_info := vk.FramebufferCreateInfo {
		sType           = .FRAMEBUFFER_CREATE_INFO,
		renderPass      = pass.handle,
		attachmentCount = cast(u32)len(attachments),
		pAttachments    = raw_data(attachments),
		width           = swapchain.extent.width,
		height          = swapchain.extent.height,
		layers          = 1,
	}

	CHECK(vk.CreateFramebuffer(device.handle, &create_info, nil, &framebuffer.handle))

	return
}

destroy_framebuffer :: proc(device: Device, framebuffer: ^Framebuffer) {
	vk.DestroyFramebuffer(device.handle, framebuffer.handle, nil)
	framebuffer^ = {}
}
