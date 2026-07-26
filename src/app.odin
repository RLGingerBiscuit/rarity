package rarity

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:os"
import vk "vendor:vulkan"

_ :: log
_ :: os

APP_TITLE :: "Rarity"
APP_WIDTH :: 800
APP_HEIGHT :: 600

App :: struct {
	window:                Window,
	instance:              Instance,
	surface:               Surface,
	physical_device:       Physical_Device,
	device:                Device,
	graphics_queue:        Queue,
	present_queue:         Queue,
	transfer_queue:        Queue,
	swapchain:             Swapchain,
	pipeline:              Pipeline,
	immediate_pool:        Command_Pool,
	immediate_buffer:      Command_Buffer,
	immediate_fence:       Fence,
	graphics_pool:         Command_Pool,
	model:                 Model,
	descriptor_pool:       Descriptor_Pool,
	graphics_buffers:      []Command_Buffer,
	image_available_semas: []Semaphore,
	render_finished_semas: []Semaphore,
	in_flight_fences:      []Fence,
}

init_app :: proc(app: ^App) {
	init_window(&app.window, APP_TITLE, APP_WIDTH, APP_HEIGHT)

	app.instance = create_instance(
		name = APP_TITLE,
		version = vk.MAKE_VERSION(0, 0, 1),
		engine_name = APP_TITLE,
		engine_version = vk.MAKE_VERSION(0, 0, 1),
		api_version = vk.API_VERSION_1_4,
	)

	app.surface = create_surface(app.instance, app.window)

	app.physical_device = choose_physical_device(app.instance, app.surface)

	app.device = create_logical_device(app.physical_device)
	set_debug_name(app.device, app.instance, "instance")
	set_debug_name(app.device, app.surface, "surface")
	set_debug_name(app.device, app.physical_device, "physical_device")
	set_debug_name(app.device, app.device, "device")

	app.graphics_queue = get_queue(app.device, app.device.indices.graphics.?, 0)
	set_debug_name(app.device, app.graphics_queue, "queue:graphics")
	app.present_queue = get_queue(app.device, app.device.indices.present.?, 0)
	set_debug_name(app.device, app.present_queue, "queue:present")
	app.transfer_queue = get_queue(app.device, app.device.indices.transfer.?, 0)
	set_debug_name(app.device, app.transfer_queue, "queue:transfer")

	app.swapchain = create_swapchain(app.device, app.physical_device, app.surface, app.window)
	set_debug_name(app.device, app.swapchain, "swapchain")
	app.pipeline = create_pipeline(app.device, app.swapchain)
	set_debug_name(app.device, app.pipeline, "pipeline")
	set_debug_name(app.device, app.pipeline.layout, "pipeline:layout")
	set_debug_name(
		app.device,
		app.pipeline.descriptor_set_layout,
		"pipeline:descriptor_set_layout",
	)

	app.immediate_pool = create_command_pool(
		app.device,
		{.TRANSIENT},
		app.device.indices.transfer.?,
	)
	set_debug_name(app.device, app.immediate_pool, "command_pool:immediate")
	app.immediate_buffer = allocate_command_buffer(app.device, app.immediate_pool)
	app.immediate_fence = create_fence(app.device)
	set_debug_name(app.device, app.immediate_fence, "fence:immediate")

	app.graphics_pool = create_command_pool(
		app.device,
		{.RESET_COMMAND_BUFFER},
		app.device.indices.graphics.?,
	)
	set_debug_name(app.device, app.graphics_pool, "command_pool:graphics")

	app.descriptor_pool = create_descriptor_pool(app.device, app.swapchain)
	set_debug_name(app.device, app.descriptor_pool, "descriptor_pool")

	app.graphics_buffers = make([]Command_Buffer, app.swapchain.max_frames_in_flight)
	app.image_available_semas = make([]Semaphore, app.swapchain.max_frames_in_flight)
	app.render_finished_semas = make([]Semaphore, app.swapchain.max_frames_in_flight)
	app.in_flight_fences = make([]Fence, app.swapchain.max_frames_in_flight)

	for i in 0 ..< app.swapchain.max_frames_in_flight {
		app.graphics_buffers[i] = allocate_command_buffer(app.device, app.graphics_pool)
		set_debug_name(
			app.device,
			app.graphics_buffers[i],
			fmt.tprintf("command_buffer/graphics:{}", i),
		)

		app.image_available_semas[i] = create_semaphore(app.device)
		set_debug_name(
			app.device,
			app.image_available_semas[i],
			fmt.tprintf("sema:image_available/{}", i),
		)

		app.render_finished_semas[i] = create_semaphore(app.device)
		set_debug_name(
			app.device,
			app.render_finished_semas[i],
			fmt.tprintf("sema:render_finished/{}", i),
		)

		app.in_flight_fences[i] = create_fence(app.device)
		set_debug_name(app.device, app.in_flight_fences[i], fmt.tprintf("fence:in_flight/{}", i))
	}

	app.model = load_model(
		MODEL_PATH,
		app.device,
		app.physical_device,
		app.descriptor_pool,
		app.pipeline.descriptor_set_layout,
		app.swapchain,
		app.immediate_pool,
		app.graphics_pool,
		app.immediate_fence,
		app.transfer_queue,
		app.graphics_queue,
	)
}

destroy_app :: proc(app: ^App) {
	for i in 0 ..< app.swapchain.max_frames_in_flight {
		destroy_fence(app.device, &app.in_flight_fences[i])
		destroy_semaphore(app.device, &app.render_finished_semas[i])
		destroy_semaphore(app.device, &app.image_available_semas[i])
		free_command_buffer(app.device, app.graphics_pool, &app.graphics_buffers[i])
	}
	delete(app.in_flight_fences)
	delete(app.render_finished_semas)
	delete(app.image_available_semas)
	delete(app.graphics_buffers)
	destroy_descriptor_pool(app.device, &app.descriptor_pool)
	destroy_model(app.device, &app.model)
	destroy_fence(app.device, &app.immediate_fence)
	destroy_command_pool(app.device, &app.immediate_pool)
	destroy_command_pool(app.device, &app.graphics_pool)
	destroy_pipeline(app.device, &app.pipeline)
	destroy_swapchain(app.device, &app.swapchain)
	destroy_logical_device(&app.device)
	destroy_physical_device(&app.physical_device)
	destroy_surface(app.instance, &app.surface)
	destroy_instance(&app.instance)
	destroy_window(&app.window)
	app^ = {}
}

app_run :: proc(app: ^App) {
	current_frame := 0

	//  < 0 : use monitor refresh rate
	// == 0 : unlimited(?) (idk man mailbox/fifo don't do what I expect)
	//  > 0 : use that refresh rate
	app.window.desired_fps = -1

	for !window_should_close(app.window) {
		update_window(&app.window)

		// log.debugf("FPS: {:.0f}", 1 / window_get_delta(app.window))

		pc: Push_Constants
		update_push_constants(app.device, app.window, app.swapchain, &pc)

		buffer := app.graphics_buffers[current_frame]
		wait_sema := app.image_available_semas[current_frame]
		fence := app.in_flight_fences[current_frame]

		wait_for_fence(app.device, &fence)

		image_index, acquire_result := acquire_next_image(app.device, app.swapchain, wait_sema)

		if _maybe_recreate_swapchain(app, acquire_result, current_frame) {
			// Wait sema has been recreated, get the new one
			wait_sema = app.image_available_semas[current_frame]
			// Image index is from previous swapchain, get a new one
			image_index, acquire_result = acquire_next_image(app.device, app.swapchain, wait_sema)
		}

		image := app.swapchain.images[image_index]
		image_view := app.swapchain.views[image_index]

		reset_fence(app.device, &fence)

		signal_sema := app.render_finished_semas[image_index]

		reset_command_buffer(buffer)
		record_commands(
			buffer,
			image,
			image_view,
			app.swapchain,
			image_index,
			app.pipeline,
			pc,
			{app.model},
		)

		queue_submit(app.graphics_queue, &buffer, wait_sema, signal_sema, fence)

		// This one doesn't matter as it's at the end of the frame anyway
		_maybe_recreate_swapchain(
			app,
			queue_present(app.present_queue, app.swapchain, image_index, signal_sema),
			current_frame,
		)

		current_frame = (current_frame + 1) % app.swapchain.max_frames_in_flight

		when ODIN_DEBUG {
			for bad_free in tracking_allocator.bad_free_array {
				log.errorf("Bad free {} at {}\n", bad_free.memory, bad_free.location)
			}
			if len(tracking_allocator.bad_free_array) > 0 {
				os.exit(1)
			}
			clear(&tracking_allocator.bad_free_array)
		}
		free_all(context.temp_allocator)
	}

	device_wait_idle(app.device)
}

record_commands :: proc(
	cmd: Command_Buffer,
	image: Image,
	image_view: Image_View,
	swapchain: Swapchain,
	index: u32,
	pipeline: Pipeline,
	pc: Push_Constants,
	models: []Model,
) {
	command_buffer_begin(cmd, {})
	defer command_buffer_end(cmd)

	debug_label_guard(cmd, "Record commands", {0.5, 0.1, 1.0})

	transition_image_layout(
		cmd,
		image,
		.UNDEFINED,
		.ATTACHMENT_OPTIMAL,
		{},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)
	transition_image_layout_explicit(
		cmd,
		swapchain.depth_image,
		.UNDEFINED,
		.DEPTH_ATTACHMENT_OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.DEPTH},
	)

	clear_colour := vk.ClearValue {
		color = {float32 = {2 / f32(255), 2 / f32(255), 2 / f32(255), 1}},
	}
	clear_depth := vk.ClearValue {
		depthStencil = {1, 0},
	}

	attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = image_view.handle,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_colour,
	}
	depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = swapchain.depth_view.handle,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .DONT_CARE,
		clearValue  = clear_depth,
	}

	info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &attachment,
		pDepthAttachment = &depth_attachment,
		renderArea = {offset = {0, 0}, extent = swapchain.extent},
	}

	vk.CmdBeginRendering(cmd.handle, &info)

	vk.CmdBindPipeline(cmd.handle, .GRAPHICS, pipeline.handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)swapchain.extent.width,
		height   = cast(f32)swapchain.extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(cmd.handle, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = swapchain.extent,
	}
	vk.CmdSetScissor(cmd.handle, 0, 1, &scissor)

	{
		debug_label_guard(cmd, "Render models", {1.0, 0.1, 0.5})
		for model in models {
			debug_label_guard(cmd, fmt.tprintf("Render model '{}'", model.name), {0.1, 0.5, 1.0})
			record_model(cmd, pipeline, model, pc, index)
		}
	}

	vk.CmdEndRendering(cmd.handle)

	transition_image_layout(
		cmd,
		image,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_WRITE},
		{},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{.COLOR},
	)
}

update_push_constants :: proc(
	device: Device,
	window: Window,
	swapchain: Swapchain,
	pc: ^Push_Constants,
) {
	@(static) time: f32 = 0
	if !window_is_key_down(window, .P) {
		time += window_get_delta(window)
	}

	qx := glm.quatAxisAngle({1, 0, 0}, glm.radians_f32(90))
	qz := glm.quatAxisAngle({0, 0, 1}, time * glm.radians_f32(90))
	q := qz * qx
	pc.model = glm.mat4FromQuat(q)

	pc.view = glm.mat4LookAt({2.5, 0, 1.5}, {0, 0, 1}, {0, 0, 1})

	pc.projection = glm.mat4Perspective(
		glm.radians_f32(45),
		swapchain_extent_aspect_ratio(swapchain),
		0.1,
		100,
	)
	pc.projection[1, 1] *= -1 // Flip because we're not using GL
}


_maybe_recreate_swapchain :: proc(
	app: ^App,
	result: vk.Result,
	current_frame: int,
	message := #caller_expression(result),
) -> (
	recreated: bool,
) {
	defer if recreated {
		device_wait_idle(app.device)
		destroy_semaphore(app.device, &app.image_available_semas[current_frame])
		app.image_available_semas[current_frame] = create_semaphore(app.device)
		// Sema *then* swapchain is important
		recreate_swapchain(
			app.device,
			&app.swapchain,
			app.physical_device,
			app.surface,
			app.window,
		)
	}

	if app.window._resized {
		app.window._resized = false
		return true
	}

	#partial switch result {
	case .SUCCESS: // These are fine

	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		return true
	}

	return false
}
