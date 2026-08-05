package rarity

import "core:fmt"
import "core:math"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 2

Swapchain :: struct {
	handle:               vk.SwapchainKHR,
	format:               vk.SurfaceFormatKHR,
	extent:               vk.Extent2D,
	images:               []Image,
	views:                []Image_View,
	depth_format:         vk.Format,
	depth_images:         []Image,
	depth_views:          []Image_View,
	edge_format:          vk.Format,
	edge_images:          []Image,
	edge_views:           []Image_View,
	max_frames_in_flight: int,
}

create_swapchain :: proc(
	device: Device,
	physical_device: Physical_Device,
	surface: Surface,
	window: Window,
) -> (
	swapchain: Swapchain,
) {
	support := _query_swapchain_support(physical_device.handle, surface)

	format := choose_swap_surface_format(support)
	present_mode := choose_swap_present_mode(support)
	extent := choose_swap_extent(support, window)

	desired_image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 &&
	   desired_image_count > support.capabilities.maxImageCount {
		desired_image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface.handle,
		minImageCount    = desired_image_count,
		imageFormat      = format.format,
		imageColorSpace  = format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = support.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
	}

	queue_family_indices: [dynamic; 3]u32
	append(&queue_family_indices, device.indices.graphics.?)
	if !slice.contains(queue_family_indices[:], device.indices.present.?) {
		append(&queue_family_indices, device.indices.present.?)
	}
	if !slice.contains(queue_family_indices[:], device.indices.transfer.?) {
		append(&queue_family_indices, device.indices.transfer.?)
	}

	if device.indices.graphics.? == device.indices.present.? &&
	   device.indices.graphics.? == device.indices.transfer.? {
		create_info.imageSharingMode = .EXCLUSIVE
		create_info.queueFamilyIndexCount = 0
		create_info.pQueueFamilyIndices = nil
	} else {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = cast(u32)len(queue_family_indices)
		create_info.pQueueFamilyIndices = raw_data(queue_family_indices[:])
	}

	CHECK(vk.CreateSwapchainKHR(device.handle, &create_info, nil, &swapchain.handle))
	swapchain.format = format
	swapchain.extent = extent

	image_count: u32
	vk.GetSwapchainImagesKHR(device.handle, swapchain.handle, &image_count, nil)
	images := make([]vk.Image, image_count, context.temp_allocator)
	vk.GetSwapchainImagesKHR(device.handle, swapchain.handle, &image_count, raw_data(images))
	swapchain.images = make([]Image, len(images))
	swapchain.views = make([]Image_View, image_count)
	for i in 0 ..< image_count {
		swapchain.images[i] = Image {
			handle    = images[i],
			size      = {swapchain.extent.width, swapchain.extent.height},
			format    = format.format,
			mip_count = 1,
		}
		set_debug_name(device, swapchain.images[i], fmt.tprintf("swapchain:image/{}", i))
		swapchain.views[i] = image_to_view(device, swapchain.images[i], {.COLOR})
		set_debug_name(device, swapchain.views[i], fmt.tprintf("swapchain:image_view/{}", i))
	}

	swapchain.max_frames_in_flight = min(MAX_FRAMES_IN_FLIGHT, cast(int)image_count)

	swapchain.depth_format = find_supported_format(
		physical_device,
		{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED_IMAGE},
	)
	swapchain.depth_images = make([]Image, image_count)
	swapchain.depth_views = make([]Image_View, image_count)
	for i in 0 ..< image_count {
		swapchain.depth_images[i] = create_render_target_image(
			device,
			physical_device,
			swapchain.extent.width,
			swapchain.extent.height,
			swapchain.depth_format,
			{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		)
		set_debug_name(
			device,
			swapchain.depth_images[i],
			fmt.tprintf("swapchain:depth/image/{}", i),
		)
		swapchain.depth_views[i] = image_to_view(device, swapchain.depth_images[i], {.DEPTH})
		set_debug_name(device, swapchain.depth_views[i], fmt.tprintf("swapchain:depth/view/{}", i))
	}

	swapchain.edge_format = find_supported_format(
		physical_device,
		{.R8_UNORM, .R8G8_UNORM, .R8G8B8A8_UNORM},
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED_IMAGE},
	)
	swapchain.edge_images = make([]Image, image_count)
	swapchain.edge_views = make([]Image_View, image_count)
	for i in 0 ..< image_count {
		swapchain.edge_images[i] = create_render_target_image(
			device,
			physical_device,
			swapchain.extent.width,
			swapchain.extent.height,
			swapchain.edge_format,
			{.COLOR_ATTACHMENT, .SAMPLED},
		)
		set_debug_name(device, swapchain.edge_images[i], fmt.tprintf("swapchain:edge/image/{}", i))
		swapchain.edge_views[i] = image_to_view(device, swapchain.edge_images[i], {.COLOR})
		set_debug_name(device, swapchain.edge_views[i], fmt.tprintf("swapchain:edge/view/{}", i))
	}

	return
}

destroy_swapchain :: proc(device: Device, swapchain: ^Swapchain) {
	for &view in swapchain.edge_views {
		destroy_image_view(device, &view)
	}
	for &image in swapchain.edge_images {
		destroy_image(device, &image)
	}
	delete(swapchain.edge_views)
	delete(swapchain.edge_images)
	for &view in swapchain.depth_views {
		destroy_image_view(device, &view)
	}
	for &image in swapchain.depth_images {
		destroy_image(device, &image)
	}
	delete(swapchain.depth_views)
	delete(swapchain.depth_images)
	for &view in swapchain.views {
		destroy_image_view(device, &view)
	}
	delete(swapchain.views)
	delete(swapchain.images)
	vk.DestroySwapchainKHR(device.handle, swapchain.handle, nil)
	swapchain^ = {}
}

swapchain_extent_aspect_ratio :: proc(swapchain: Swapchain) -> f32 {
	return cast(f32)swapchain.extent.width / cast(f32)swapchain.extent.height
}

Swapchain_Support :: struct {
	capabilities:  vk.SurfaceCapabilitiesKHR,
	formats:       []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

_query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
	surface: Surface,
) -> (
	support: Swapchain_Support,
) {
	CHECK(
		vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface.handle, &support.capabilities),
	)

	format_count: u32
	CHECK(vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface.handle, &format_count, nil))
	if format_count > 0 {
		support.formats = make([]vk.SurfaceFormatKHR, format_count, context.temp_allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			device,
			surface.handle,
			&format_count,
			raw_data(support.formats),
		)
	}

	present_mode_count: u32
	CHECK(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			surface.handle,
			&present_mode_count,
			nil,
		),
	)
	if present_mode_count > 0 {
		support.present_modes = make(
			[]vk.PresentModeKHR,
			present_mode_count,
			context.temp_allocator,
		)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			surface.handle,
			&present_mode_count,
			raw_data(support.present_modes),
		)
	}

	return
}

choose_swap_surface_format :: proc(support: Swapchain_Support) -> vk.SurfaceFormatKHR {
	assert(len(support.formats) > 0)
	for format in support.formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}
	return support.formats[0]
}

choose_swap_present_mode :: proc(support: Swapchain_Support) -> vk.PresentModeKHR {
	assert(len(support.present_modes) > 0)
	for present_mode in support.present_modes {
		if present_mode == .MAILBOX {
			// preferred
			return present_mode
		}
	}
	// always present
	return .FIFO
}

choose_swap_extent :: proc(support: Swapchain_Support, window: Window) -> vk.Extent2D {
	if support.capabilities.currentExtent.width != max(u32) {
		return support.capabilities.currentExtent
	}
	width, height := glfw.GetFramebufferSize(window.handle)

	extent := vk.Extent2D {
		width  = math.clamp(
			cast(u32)width,
			support.capabilities.minImageExtent.width,
			support.capabilities.maxImageExtent.width,
		),
		height = math.clamp(
			cast(u32)height,
			support.capabilities.minImageExtent.height,
			support.capabilities.maxImageExtent.height,
		),
	}
	return extent
}

acquire_next_image :: proc(
	device: Device,
	swapchain: Swapchain,
	sema: Semaphore,
) -> (
	index: u32,
	result: vk.Result,
) {
	result = vk.AcquireNextImageKHR(
		device.handle,
		swapchain.handle,
		max(u64),
		sema.handle,
		0,
		&index,
	)
	return
}

recreate_swapchain :: proc(
	device: Device,
	swapchain: ^Swapchain,
	physical_device: Physical_Device,
	surface: Surface,
	window: Window,
) {
	width, height := window_get_framebuffer_size(window)
	for width == 0 || height == 0 {
		window_wait(window)
		width, height = window_get_framebuffer_size(window)
	}

	device_wait_idle(device)
	destroy_swapchain(device, swapchain)

	swapchain^ = create_swapchain(device, physical_device, surface, window)
}
