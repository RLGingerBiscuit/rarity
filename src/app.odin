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
	model_pipeline:        Pipeline,
	edge_detect_pipeline:  Pipeline,
	edge_overlay_pipeline: Pipeline,
	sampled_image_layout:  Descriptor_Set_Layout,
	depth_sampler:         Sampler,
	edge_sampler:          Sampler,
	depth_sets:            []Descriptor_Set,
	edge_sets:             []Descriptor_Set,
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
	current_frame:         int,
}

init_app :: proc(app: ^App) {
	init_window(&app.window, APP_TITLE, APP_WIDTH, APP_HEIGHT)

	app.instance = create_instance(
		name = APP_TITLE,
		version = vk.MAKE_VERSION(0, 0, 1),
		engine_name = APP_TITLE,
		engine_version = vk.MAKE_VERSION(0, 0, 1),
		api_version = vk.API_VERSION_1_3,
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
	app.sampled_image_layout = create_sampled_image_set_layout(app.device)
	set_debug_name(app.device, app.sampled_image_layout, "descriptor_set_layout:sampled_image")
	create_app_pipelines(app)

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
	create_frame_descriptors(app)

	create_sync_and_command_resources(app)

	app.model = load_model(
		MODEL_PATH,
		app.device,
		app.physical_device,
		app.descriptor_pool,
		app.sampled_image_layout,
		app.swapchain,
		app.immediate_pool,
		app.graphics_pool,
		app.immediate_fence,
		app.transfer_queue,
		app.graphics_queue,
	)
}

destroy_app :: proc(app: ^App) {
	destroy_model(app.device, &app.model)
	destroy_sync_and_command_resources(app)
	destroy_frame_descriptors(app)
	destroy_descriptor_pool(app.device, &app.descriptor_pool)
	destroy_fence(app.device, &app.immediate_fence)
	destroy_command_pool(app.device, &app.immediate_pool)
	destroy_command_pool(app.device, &app.graphics_pool)
	destroy_app_pipelines(app)
	destroy_descriptor_set_layout(app.device, &app.sampled_image_layout)
	destroy_swapchain(app.device, &app.swapchain)
	destroy_logical_device(&app.device)
	destroy_physical_device(&app.physical_device)
	destroy_surface(app.instance, &app.surface)
	destroy_instance(&app.instance)
	destroy_window(&app.window)
	app^ = {}
}

create_sync_and_command_resources :: proc(app: ^App) {
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
}

destroy_sync_and_command_resources :: proc(app: ^App) {
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
}

create_app_pipelines :: proc(app: ^App) {
	app.model_pipeline = create_model_pipeline(app.device, app.swapchain, app.sampled_image_layout)
	set_debug_name(app.device, app.model_pipeline, "pipeline:model")
	set_debug_name(app.device, app.model_pipeline.layout, "pipeline:model/layout")

	app.edge_detect_pipeline = create_edge_detect_pipeline(
		app.device,
		app.swapchain,
		app.sampled_image_layout,
	)
	set_debug_name(app.device, app.edge_detect_pipeline, "pipeline:edge_detect")
	set_debug_name(app.device, app.edge_detect_pipeline.layout, "pipeline:edge_detect/layout")

	app.edge_overlay_pipeline = create_edge_overlay_pipeline(
		app.device,
		app.swapchain,
		app.sampled_image_layout,
	)
	set_debug_name(app.device, app.edge_overlay_pipeline, "pipeline:edge_overlay")
	set_debug_name(app.device, app.edge_overlay_pipeline.layout, "pipeline:edge_overlay/layout")
}

destroy_app_pipelines :: proc(app: ^App) {
	destroy_pipeline(app.device, &app.edge_overlay_pipeline)
	destroy_pipeline(app.device, &app.edge_detect_pipeline)
	destroy_pipeline(app.device, &app.model_pipeline)
}

create_frame_descriptors :: proc(app: ^App) {
	app.depth_sampler = create_sampler(
		app.device,
		app.physical_device,
		.NEAREST,
		.NEAREST,
		.NEAREST,
		.CLAMP_TO_EDGE,
		.CLAMP_TO_EDGE,
	)
	set_debug_name(app.device, app.depth_sampler, "sampler:depth")

	app.edge_sampler = create_sampler(
		app.device,
		app.physical_device,
		.NEAREST,
		.NEAREST,
		.NEAREST,
		.CLAMP_TO_EDGE,
		.CLAMP_TO_EDGE,
	)
	set_debug_name(app.device, app.edge_sampler, "sampler:edge")

	count := len(app.swapchain.images)
	app.depth_sets = allocate_descriptor_sets(
		app.device,
		app.descriptor_pool,
		app.sampled_image_layout,
		count,
	)
	for i in 0 ..< count {
		populate_descriptor_sets(
			app.device,
			app.depth_sets[i:i + 1],
			app.swapchain.depth_views[i],
			app.depth_sampler,
		)
	}

	app.edge_sets = allocate_descriptor_sets(
		app.device,
		app.descriptor_pool,
		app.sampled_image_layout,
		count,
	)
	for i in 0 ..< count {
		populate_descriptor_sets(
			app.device,
			app.edge_sets[i:i + 1],
			app.swapchain.edge_views[i],
			app.edge_sampler,
		)
	}
}

destroy_frame_descriptors :: proc(app: ^App) {
	delete(app.edge_sets)
	delete(app.depth_sets)
	destroy_sampler(app.device, &app.edge_sampler)
	destroy_sampler(app.device, &app.depth_sampler)
}

reload_render_resources :: proc(app: ^App) {
	device_wait_idle(app.device)

	destroy_model(app.device, &app.model)
	destroy_frame_descriptors(app)
	destroy_descriptor_pool(app.device, &app.descriptor_pool)
	destroy_app_pipelines(app)

	max_frames_in_flight := app.swapchain.max_frames_in_flight
	recreate_swapchain(app.device, &app.swapchain, app.physical_device, app.surface, app.window)
	if app.swapchain.max_frames_in_flight != max_frames_in_flight {
		destroy_sync_and_command_resources(app)
		create_sync_and_command_resources(app)
		app.current_frame = 0
	} else {
		// Recreate the *current* semaphore so it's not signalled
		current_frame := (app.current_frame) % app.swapchain.max_frames_in_flight
		destroy_semaphore(app.device, &app.image_available_semas[current_frame])
		app.image_available_semas[current_frame] = create_semaphore(app.device)
	}
	create_app_pipelines(app)
	app.descriptor_pool = create_descriptor_pool(app.device, app.swapchain)
	set_debug_name(app.device, app.descriptor_pool, "descriptor_pool")
	create_frame_descriptors(app)
	app.model = load_model(
		MODEL_PATH,
		app.device,
		app.physical_device,
		app.descriptor_pool,
		app.sampled_image_layout,
		app.swapchain,
		app.immediate_pool,
		app.graphics_pool,
		app.immediate_fence,
		app.transfer_queue,
		app.graphics_queue,
	)
}

app_run :: proc(app: ^App) {
	//  < 0 : use monitor refresh rate
	// == 0 : unlimited(?) (idk man mailbox/fifo don't do what I expect)
	//  > 0 : use that refresh rate
	app.window.desired_fps = -1

	for !window_should_close(app.window) {
		update_window(&app.window)

		// log.debugf("FPS: {:.0f}", 1 / window_get_delta(app.window))

		model_pc: Model_Push_Constants
		edge_detect_pc: Edge_Detect_Push_Constants
		edge_overlay_pc: Edge_Overlay_Push_Constants
		update_push_constants(
			app.window,
			app.device,
			app.swapchain,
			&model_pc,
			&edge_detect_pc,
			&edge_overlay_pc,
		)

		current_frame := (app.current_frame) % app.swapchain.max_frames_in_flight

		buffer := app.graphics_buffers[current_frame]
		wait_sema := app.image_available_semas[current_frame]
		fence := app.in_flight_fences[current_frame]

		wait_for_fence(app.device, &fence)

		image_index, acquire_result := acquire_next_image(app.device, app.swapchain, wait_sema)
		if _maybe_recreate_swapchain(app, acquire_result) {
			continue
		}

		image := app.swapchain.images[image_index]
		image_view := app.swapchain.views[image_index]
		depth_image := app.swapchain.depth_images[image_index]
		depth_view := app.swapchain.depth_views[image_index]

		reset_fence(app.device, &fence)

		signal_sema := app.render_finished_semas[image_index]

		reset_command_buffer(buffer)
		record_commands(
			buffer,
			{
				swapchain = app.swapchain,
				image_index = image_index,
				swapchain_image = image,
				swapchain_view = image_view,
				depth_image = depth_image,
				depth_view = depth_view,
				model_pipeline = app.model_pipeline,
				edge_detect_pipeline = app.edge_detect_pipeline,
				edge_overlay_pipeline = app.edge_overlay_pipeline,
				depth_set = app.depth_sets[image_index],
				edge_set = app.edge_sets[image_index],
				model_pc = model_pc,
				edge_detect_pc = edge_detect_pc,
				edge_overlay_pc = edge_overlay_pc,
				models = {app.model},
			},
		)

		queue_submit(app.graphics_queue, &buffer, wait_sema, signal_sema, fence)

		present_result := queue_present(app.present_queue, app.swapchain, image_index, signal_sema)
		if _maybe_recreate_swapchain(app, present_result) {
			continue
		}

		app.current_frame += 1

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

Frame_Render_Info :: struct {
	swapchain:             Swapchain,
	image_index:           u32,
	swapchain_image:       Image,
	swapchain_view:        Image_View,
	depth_image:           Image,
	depth_view:            Image_View,
	model_pipeline:        Pipeline,
	edge_detect_pipeline:  Pipeline,
	edge_overlay_pipeline: Pipeline,
	depth_set:             Descriptor_Set,
	edge_set:              Descriptor_Set,
	model_pc:              Model_Push_Constants,
	edge_detect_pc:        Edge_Detect_Push_Constants,
	edge_overlay_pc:       Edge_Overlay_Push_Constants,
	models:                []Model,
}

record_commands :: proc(cmd: Command_Buffer, frame: Frame_Render_Info) {
	command_buffer_begin(cmd, {})
	defer command_buffer_end(cmd)

	debug_label_guard(cmd, "Record commands", {0.5, 0.1, 1.0})

	cmd_image_barrier(
		cmd,
		frame.swapchain_image,
		.UNDEFINED,
		.ATTACHMENT_OPTIMAL,
		{},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)
	cmd_image_barrier(
		cmd,
		frame.depth_image,
		.UNDEFINED,
		.DEPTH_ATTACHMENT_OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.DEPTH},
	)

	clear_colour := vk.ClearValue {
		color = {float32 = {16 / f32(255), 16 / f32(255), 16 / f32(255), 1}},
	}
	clear_depth := vk.ClearValue {
		depthStencil = {1, 0},
	}

	attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = frame.swapchain_view.handle,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_colour,
	}
	depth_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = frame.depth_view.handle,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_depth,
	}

	info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &attachment,
		pDepthAttachment = &depth_attachment,
		renderArea = {offset = {0, 0}, extent = frame.swapchain.extent},
	}

	vk.CmdBeginRendering(cmd.handle, &info)

	vk.CmdBindPipeline(cmd.handle, .GRAPHICS, frame.model_pipeline.handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)frame.swapchain.extent.width,
		height   = cast(f32)frame.swapchain.extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(cmd.handle, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = frame.swapchain.extent,
	}
	vk.CmdSetScissor(cmd.handle, 0, 1, &scissor)

	{
		debug_label_guard(cmd, "Render models", {1.0, 0.1, 0.5})
		for model in frame.models {
			debug_label_guard(cmd, fmt.tprintf("Render model '{}'", model.name), {0.1, 0.5, 1.0})
			record_model(cmd, frame.model_pipeline, model, frame.model_pc, frame.image_index)
		}
	}

	vk.CmdEndRendering(cmd.handle)

	cmd_image_barrier(
		cmd,
		frame.depth_image,
		.DEPTH_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		{.SHADER_READ},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{.FRAGMENT_SHADER},
		{.DEPTH},
	)
	cmd_image_barrier(
		cmd,
		frame.swapchain.edge_images[frame.image_index],
		.UNDEFINED,
		.ATTACHMENT_OPTIMAL,
		{},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)

	edge_clear := vk.ClearValue {
		color = {float32 = {0, 0, 0, 0}},
	}
	edge_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = frame.swapchain.edge_views[frame.image_index].handle,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = edge_clear,
	}
	edge_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &edge_attachment,
		renderArea = {offset = {0, 0}, extent = frame.swapchain.extent},
	}

	{
		debug_label_guard(cmd, "Edge detect", {1.0, 0.0, 0.0})
		vk.CmdBeginRendering(cmd.handle, &edge_info)
		vk.CmdBindPipeline(cmd.handle, .GRAPHICS, frame.edge_detect_pipeline.handle)
		depth_set := frame.depth_set
		vk.CmdBindDescriptorSets(
			cmd.handle,
			.GRAPHICS,
			frame.edge_detect_pipeline.layout.handle,
			0,
			1,
			&depth_set.handle,
			0,
			nil,
		)
		edge_pc := frame.edge_detect_pc
		vk.CmdPushConstants(
			cmd.handle,
			frame.edge_detect_pipeline.layout.handle,
			{.FRAGMENT},
			0,
			size_of(Edge_Detect_Push_Constants),
			&edge_pc,
		)
		vk.CmdDraw(cmd.handle, 3, 1, 0, 0)
		vk.CmdEndRendering(cmd.handle)
	}

	cmd_image_barrier(
		cmd,
		frame.swapchain.edge_images[frame.image_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR},
	)

	overlay_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = frame.swapchain_view.handle,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}
	overlay_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &overlay_attachment,
		renderArea = {offset = {0, 0}, extent = frame.swapchain.extent},
	}

	{
		debug_label_guard(cmd, "Edge overlay", {1.0, 0.5, 0.1})
		vk.CmdBeginRendering(cmd.handle, &overlay_info)
		vk.CmdBindPipeline(cmd.handle, .GRAPHICS, frame.edge_overlay_pipeline.handle)
		edge_set := frame.edge_set
		vk.CmdBindDescriptorSets(
			cmd.handle,
			.GRAPHICS,
			frame.edge_overlay_pipeline.layout.handle,
			0,
			1,
			&edge_set.handle,
			0,
			nil,
		)
		overlay_pc := frame.edge_overlay_pc
		vk.CmdPushConstants(
			cmd.handle,
			frame.edge_overlay_pipeline.layout.handle,
			{.VERTEX},
			0,
			size_of(Edge_Overlay_Push_Constants),
			&overlay_pc,
		)
		vk.CmdDraw(cmd.handle, 3, 1, 0, 0)
		vk.CmdEndRendering(cmd.handle)
	}

	cmd_image_barrier(
		cmd,
		frame.swapchain_image,
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
	window: Window,
	device: Device,
	swapchain: Swapchain,
	model_pc: ^Model_Push_Constants,
	edge_detect_pc: ^Edge_Detect_Push_Constants,
	edge_overlay_pc: ^Edge_Overlay_Push_Constants,
) {
	@(static) time: f32 = 0
	if !window_is_key_down(window, .P) {
		time += window_get_delta(window)
	}

	qx := glm.quatAxisAngle({1, 0, 0}, glm.radians_f32(90))
	qz := glm.quatAxisAngle({0, 0, 1}, time * glm.radians_f32(90))
	q := qz * qx
	model := glm.mat4FromQuat(q)

	view := glm.mat4LookAt({2.5, 0, 1.5}, {0, 0, 1}, {0, 0, 1})

	projection := glm.mat4Perspective(
		glm.radians_f32(45),
		swapchain_extent_aspect_ratio(swapchain),
		0.1,
		100,
	)
	projection[1, 1] *= -1 // Flip because we're not using GL

	model_pc.mvp = projection * view * model
	edge_detect_pc.projection = projection
	edge_overlay_pc.colour = {0, 0, 0, 1}
}


_maybe_recreate_swapchain :: proc(
	app: ^App,
	result: vk.Result,
	message := #caller_expression(result),
) -> (
	recreated: bool,
) {
	defer if recreated {
		// Sema *then* swapchain-dependent resources is important
		reload_render_resources(app)
	}

	if app.window._resized {
		app.window._resized = false
		return true
	}

	#partial switch result {
	case .SUCCESS: // These are fine

	case .ERROR_OUT_OF_DATE_KHR, .SUBOPTIMAL_KHR:
		return true

	case:
		CHECK(result)
	}

	return false
}
