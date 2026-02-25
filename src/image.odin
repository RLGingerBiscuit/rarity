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
