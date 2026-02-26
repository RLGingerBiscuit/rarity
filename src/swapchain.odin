package rarity

import "core:math"
import "vendor:glfw"
import vk "vendor:vulkan"

Swapchain :: struct {
	handle:       vk.SwapchainKHR,
	format:       vk.SurfaceFormatKHR,
	extent:       vk.Extent2D,
	images:       []Image,
	views:        []Image_View,
	framebuffers: []Framebuffer,
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

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface.handle,
		minImageCount    = image_count,
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

	queue_family_indices := make([dynamic]u32, 0, 3, context.temp_allocator)
	append(&queue_family_indices, device.indices.graphics.?, device.indices.present.?)
	if device.indices.transfer != device.indices.graphics {
		append(&queue_family_indices, device.indices.transfer.?)
	}

	create_info.imageSharingMode = .CONCURRENT
	create_info.queueFamilyIndexCount = cast(u32)len(queue_family_indices)
	create_info.pQueueFamilyIndices = raw_data(queue_family_indices)

	CHECK(vk.CreateSwapchainKHR(device.handle, &create_info, nil, &swapchain.handle))
	swapchain.format = format
	swapchain.extent = extent

	vk.GetSwapchainImagesKHR(device.handle, swapchain.handle, &image_count, nil)
	images := make([]vk.Image, image_count, context.temp_allocator)
	vk.GetSwapchainImagesKHR(device.handle, swapchain.handle, &image_count, raw_data(images))
	swapchain.images = make([]Image, len(images))
	for i in 0 ..< image_count {
		swapchain.images[i] = Image {
			handle = images[i],
			format = format.format,
		}
	}

	swapchain.views = make([]Image_View, image_count)
	for i in 0 ..< image_count {
		swapchain.views[i] = image_to_view(device, swapchain.images[i])
	}

	return
}

create_framebuffers :: proc(device: Device, swapchain: ^Swapchain, pass: Render_Pass) {
	swapchain.framebuffers = make([]Framebuffer, len(swapchain.views))
	for view, i in swapchain.views {
		swapchain.framebuffers[i] = create_framebuffer(device, swapchain^, pass, view)
	}
}

destroy_swapchain :: proc(device: Device, swapchain: ^Swapchain) {
	for &framebuffer in swapchain.framebuffers {
		destroy_framebuffer(device, &framebuffer)
	}
	delete(swapchain.framebuffers)
	for &view in swapchain.views {
		destroy_image_view(device, &view)
	}
	delete(swapchain.views)
	delete(swapchain.images)
	vk.DestroySwapchainKHR(device.handle, swapchain.handle, nil)
	swapchain^ = {}
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
			return present_mode
		}
	}
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
	pass: Render_Pass,
	physical_device: Physical_Device,
	surface: Surface,
	window: Window,
) {
	width, height := get_window_size(window)
	for width == 0 || height == 0 {
		window_wait(window)
		width, height = get_window_size(window)
	}

	device_wait_idle(device)
	destroy_swapchain(device, swapchain)

	swapchain^ = create_swapchain(device, physical_device, surface, window)
	create_framebuffers(device, swapchain, pass)
}
