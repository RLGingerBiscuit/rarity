package rarity

import vk "vendor:vulkan"

Image :: struct {
	handle: vk.Image,
	format: vk.Format,
}

Image_View :: struct {
	handle: vk.ImageView,
}

image_to_view :: proc(device: Device, image: Image) -> (view: Image_View) {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image.handle,
		format = image.format,
		viewType = .D2,
		components = {}, // IDENTITY
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	CHECK(vk.CreateImageView(device.handle, &create_info, nil, &view.handle))

	return
}

destroy_image_view :: proc(device: Device, view: ^Image_View) {
	vk.DestroyImageView(device.handle, view.handle, nil)
	view^ = {}
}

transition_image_layout :: proc(
	cmd: Command_Buffer,
	image: Image,
	old, new: vk.ImageLayout,
	src_access, dst_access: vk.AccessFlags2,
	src_stage, dst_stage: vk.PipelineStageFlags2,
) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		image = image.handle,
		oldLayout = old,
		newLayout = new,
		srcAccessMask = src_access,
		dstAccessMask = dst_access,
		srcStageMask = src_stage,
		dstStageMask = dst_stage,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}
	dependency := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(cmd.handle, &dependency)
}
