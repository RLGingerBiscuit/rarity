package rarity

import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:os"
import stbi "vendor:stb/image"
import vk "vendor:vulkan"

Image :: struct {
	handle:    vk.Image,
	memory:    Device_Memory, // May not exist (e.g. from swapchain)
	size:      [2]u32,
	format:    vk.Format,
	mip_count: u32,
}

Image_View :: struct {
	handle: vk.ImageView,
}

create_image :: proc(
	device: Device,
	physical_device: Physical_Device,
	width, height: u32,
	format: vk.Format,
	mip_count: u32,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	mem_props: vk.MemoryPropertyFlags,
) -> (
	image: Image,
) {
	create_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = {width = width, height = height, depth = 1},
		mipLevels = mip_count,
		arrayLayers = 1,
		samples = {._1},
		tiling = tiling,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	CHECK(vk.CreateImage(device.handle, &create_info, nil, &image.handle))
	image.size = {width, height}
	image.format = format
	image.mip_count = mip_count

	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device.handle, image.handle, &requirements)

	allocate_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = requirements.size,
		memoryTypeIndex = _find_memory_type(
			physical_device.handle,
			requirements.memoryTypeBits,
			mem_props,
		),
	}

	CHECK(vk.AllocateMemory(device.handle, &allocate_info, nil, &image.memory.handle))

	CHECK(vk.BindImageMemory(device.handle, image.handle, image.memory.handle, 0))

	return
}

load_image_from_path :: proc(
	path: string,
	device: Device,
	physical_device: Physical_Device,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	mem_props: vk.MemoryPropertyFlags,
) -> (
	image: Image,
) {
	file_data, err := os.read_entire_file(path, context.temp_allocator)
	log.ensuref(err == nil, "Could not open '{}': {}", path, err)
	return load_image_from_memory(
		file_data,
		device,
		physical_device,
		immediate_pool,
		graphics_pool,
		immediate_fence,
		transfer_queue,
		graphics_queue,
		format,
		tiling,
		usage,
		mem_props,
	)
}

load_image_from_memory :: proc(
	data: []byte,
	device: Device,
	physical_device: Physical_Device,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	mem_props: vk.MemoryPropertyFlags,
) -> (
	image: Image,
) {
	DESIRED_CHANNELS :: 4

	width, height: i32
	image_pixels := stbi.load_from_memory(
		raw_data(data),
		cast(i32)len(data),
		&width,
		&height,
		nil,
		DESIRED_CHANNELS,
	)
	log.ensuref(image_pixels != nil, "Could not load image: {}", stbi.failure_reason())
	defer stbi.image_free(image_pixels)

	mip_count := 1 + cast(u32)glm.floor(math.log2(cast(f32)glm.max(width, height)))

	image_size := cast(vk.DeviceSize)(width * height * DESIRED_CHANNELS)

	staging := create_buffer(
		device,
		physical_device,
		image_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	defer destroy_buffer(device, &staging)

	pixels := map_buffer_memory(u8, device, staging, cast(int)image_size)
	defer unmap_buffer_memory(device, staging)
	copy(pixels, image_pixels[:image_size])

	image = create_image(
		device,
		physical_device,
		cast(u32)width,
		cast(u32)height,
		.R8G8B8A8_SRGB,
		mip_count,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
	)

	transition_image_layout_short(
		device,
		immediate_pool,
		immediate_fence,
		transfer_queue,
		image,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.COLOR},
	)
	copy_buffer_to_image(device, immediate_pool, immediate_fence, transfer_queue, staging, image)

	generate_mipmaps(
		device,
		physical_device,
		image,
		graphics_pool,
		immediate_fence,
		graphics_queue,
	)

	return
}

load_image :: proc {
	load_image_from_memory,
	load_image_from_path,
}

destroy_image :: proc(device: Device, image: ^Image) {
	vk.DestroyImage(device.handle, image.handle, nil)
	if image.memory.handle != 0 {
		vk.FreeMemory(device.handle, image.memory.handle, nil)
	}
	image^ = {}
}

generate_mipmaps :: proc(
	device: Device,
	physical_device: Physical_Device,
	image: Image,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	graphics_queue: Queue,
) {
	cmd := immediate_guard(device, graphics_pool, graphics_queue, immediate_fence)
	debug_label_guard(cmd, "Image Mips", {0.1, 0.5, 1.0})

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.TRANSFER_WRITE},
		dstAccessMask = {.TRANSFER_READ},
		oldLayout = .TRANSFER_DST_OPTIMAL,
		newLayout = .TRANSFER_SRC_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image.handle,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			levelCount = 1,
		},
	}

	if image.mip_count > 1 {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device.handle, image.format, &props)
		log.assertf(
			.SAMPLED_IMAGE_FILTER_LINEAR in props.linearTilingFeatures,
			"Image format does not support linear blitting",
		)

		mip_size := [2]i32{cast(i32)image.size.x, cast(i32)image.size.y}

		for i in 1 ..< image.mip_count {
			barrier.subresourceRange.baseMipLevel = i - 1
			barrier.srcAccessMask = {.TRANSFER_WRITE}
			barrier.dstAccessMask = {.TRANSFER_READ}
			barrier.oldLayout = .TRANSFER_DST_OPTIMAL
			barrier.newLayout = .TRANSFER_SRC_OPTIMAL

			vk.CmdPipelineBarrier(
				cmd.handle,
				{.TRANSFER},
				{.TRANSFER},
				{},
				0,
				nil,
				0,
				nil,
				1,
				&barrier,
			)

			src := [2]vk.Offset3D{{0, 0, 0}, {mip_size.x, mip_size.y, 1}}
			dst := [2]vk.Offset3D {
				{0, 0, 0},
				{mip_size.x > 1 ? mip_size.x / 2 : 1, mip_size.y > 1 ? mip_size.y / 2 : 1, 1},
			}
			blit := vk.ImageBlit {
				srcOffsets = src,
				dstOffsets = dst,
				srcSubresource = {
					aspectMask = {.COLOR},
					mipLevel = i - 1,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				dstSubresource = {
					aspectMask = {.COLOR},
					mipLevel = i,
					baseArrayLayer = 0,
					layerCount = 1,
				},
			}

			vk.CmdBlitImage(
				cmd.handle,
				image.handle,
				.TRANSFER_SRC_OPTIMAL,
				image.handle,
				.TRANSFER_DST_OPTIMAL,
				1,
				&blit,
				.LINEAR,
			)

			barrier.srcAccessMask = {.TRANSFER_READ}
			barrier.dstAccessMask = {.SHADER_READ}
			barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
			barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL

			vk.CmdPipelineBarrier(
				cmd.handle,
				{.TRANSFER},
				{.FRAGMENT_SHADER},
				{},
				0,
				nil,
				0,
				nil,
				1,
				&barrier,
			)

			mip_size = glm.max([2]i32{1, 1}, mip_size / 2)
		}
	}

	barrier.subresourceRange.baseMipLevel = image.mip_count - 1
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL

	vk.CmdPipelineBarrier(
		cmd.handle,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
}

image_to_view :: proc(
	device: Device,
	image: Image,
	aspect_mask: vk.ImageAspectFlags,
) -> (
	view: Image_View,
) {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image.handle,
		format = image.format,
		viewType = .D2,
		components = {}, // IDENTITY
		subresourceRange = {
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = image.mip_count,
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

copy_buffer_to_image :: proc(
	device: Device,
	pool: Command_Pool,
	fence: Fence,
	queue: Queue,
	src: Buffer,
	dst: Image,
) {
	cmd := immediate_guard(device, pool, queue, fence)
	debug_label_guard(cmd, "Image Copy", {0.5, 0.1, 1.0})

	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageOffset = {},
		imageExtent = {width = dst.size.x, height = dst.size.y, depth = 1},
		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}
	vk.CmdCopyBufferToImage(cmd.handle, src.handle, dst.handle, .TRANSFER_DST_OPTIMAL, 1, &region)
}

transition_image_layout_short :: proc(
	device: Device,
	pool: Command_Pool,
	fence: Fence,
	queue: Queue,
	image: Image,
	old, new: vk.ImageLayout,
	aspect_mask: vk.ImageAspectFlags,
) {
	cmd := immediate_guard(device, pool, queue, fence)

	src_stage, dst_stage: vk.PipelineStageFlags2
	src_access, dst_access: vk.AccessFlags2

	if old == .UNDEFINED && new == .TRANSFER_DST_OPTIMAL {
		dst_access = {.TRANSFER_WRITE}
		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.TRANSFER}
	} else if old == .TRANSFER_DST_OPTIMAL && new == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {.TRANSFER_WRITE}
		dst_access = {.SHADER_READ}
		src_stage = {.TRANSFER}
		dst_stage = {.FRAGMENT_SHADER}
	} else {
		log.panicf("Unsupported layout transition: {} -> {}", old, new)
	}

	transition_image_layout_explicit(
		cmd,
		image,
		old,
		new,
		src_access,
		dst_access,
		src_stage,
		dst_stage,
		aspect_mask,
	)
}

transition_image_layout_explicit :: proc(
	cmd: Command_Buffer,
	image: Image,
	old, new: vk.ImageLayout,
	src_access, dst_access: vk.AccessFlags2,
	src_stage, dst_stage: vk.PipelineStageFlags2,
	aspect_mask: vk.ImageAspectFlags,
) {
	debug_label_guard(cmd, "Image Transition", {0.5, 1.0, 0.1})

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
			aspectMask = aspect_mask,
			baseMipLevel = 0,
			levelCount = image.mip_count,
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

transition_image_layout :: proc {
	transition_image_layout_short,
	transition_image_layout_explicit,
}

find_supported_format :: proc(
	physical_device: Physical_Device,
	formats: []vk.Format,
	tiling: vk.ImageTiling,
	features: vk.FormatFeatureFlags,
) -> vk.Format {
	for format in formats {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device.handle, format, &props)

		switch tiling {
		case .LINEAR:
			if props.linearTilingFeatures & features == features {
				return format
			}

		case .OPTIMAL:
			if props.optimalTilingFeatures & features == features {
				return format
			}

		case .DRM_FORMAT_MODIFIER_EXT:
			unreachable()
		}
	}

	log.panic(
		"Failed to find a supported format (tiling {}, features {}, candidates {})",
		tiling,
		features,
		formats,
	)
}
