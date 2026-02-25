package rarity

import vk "vendor:vulkan"

Render_Pass :: struct {
	handle: vk.RenderPass,
}

create_render_pass :: proc(device: Device, swapchain: Swapchain) -> (pass: Render_Pass) {
	colour := vk.AttachmentDescription {
		format         = swapchain.format.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	colour_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &colour_ref,
	}

	create_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &colour,
		subpassCount    = 1,
		pSubpasses      = &subpass,
	}

	CHECK(vk.CreateRenderPass(device.handle, &create_info, nil, &pass.handle))

	return
}

destroy_render_pass :: proc(device: Device, pass: ^Render_Pass) {
	vk.DestroyRenderPass(device.handle, pass.handle, nil)
	pass^ = {}
}
