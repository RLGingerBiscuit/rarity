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
	render_pass:           Render_Pass,
	pipeline:              Pipeline,
	graphics_pool:         Command_Pool,
	transfer_pool:         Command_Pool,
	vertex_buffer:         Vertex_Buffer,
	index_buffer:          Index_Buffer,
	descriptor_pool:       Descriptor_Pool,
	uniform_sets:          []Descriptor_Set,
	uniform_buffers:       []Uniform_Buffer(Uniforms),
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
		api_version = vk.API_VERSION_1_3, // Min version for slang
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
	app.render_pass = create_render_pass(app.device, app.swapchain)
	set_debug_name(app.device, app.render_pass, "render_pass")
	app.pipeline = create_pipeline(app.device, app.swapchain, app.render_pass)
	set_debug_name(app.device, app.pipeline, "pipeline")
	set_debug_name(app.device, app.pipeline.layout, "pipeline:layout")
	set_debug_name(
		app.device,
		app.pipeline.descriptor_set_layout,
		"pipeline:descriptor_set_layout",
	)

	create_framebuffers(app.device, &app.swapchain, app.render_pass)

	app.graphics_pool = create_command_pool(
		app.device,
		{.RESET_COMMAND_BUFFER},
		app.device.indices.graphics.?,
	)
	set_debug_name(app.device, app.graphics_pool, "command_pool:graphics")

	app.transfer_pool = create_command_pool(
		app.device,
		{.TRANSIENT},
		app.device.indices.transfer.?,
	)
	set_debug_name(app.device, app.transfer_pool, "command_pool:transfer")

	app.vertex_buffer = create_vertex_buffer(
		app.device,
		app.physical_device,
		app.transfer_pool,
		app.transfer_queue,
	)
	set_debug_name(app.device, app.vertex_buffer, "buffer:vertex")
	set_debug_name(app.device, app.vertex_buffer.memory, "buffer:vertex/memory")

	app.index_buffer = create_index_buffer(
		app.device,
		app.physical_device,
		app.transfer_pool,
		app.transfer_queue,
	)
	set_debug_name(app.device, app.index_buffer, "buffer:index")
	set_debug_name(app.device, app.index_buffer.memory, "buffer:index/memory")

	app.descriptor_pool = create_descriptor_pool(app.device, app.swapchain)
	set_debug_name(app.device, app.descriptor_pool, "descriptor_pool")
	app.uniform_sets = allocate_descriptor_sets(
		app.device,
		app.descriptor_pool,
		app.pipeline.descriptor_set_layout,
		app.swapchain.max_frames_in_flight,
	)
	for i in 0 ..< len(app.uniform_sets) {
		set_debug_name(
			app.device,
			app.uniform_sets[i],
			fmt.tprintf("descriptor_set:uniforms/{}", i),
		)
	}

	app.uniform_buffers = make([]Uniform_Buffer(Uniforms), app.swapchain.max_frames_in_flight)
	app.graphics_buffers = make([]Command_Buffer, app.swapchain.max_frames_in_flight)
	app.image_available_semas = make([]Semaphore, app.swapchain.max_frames_in_flight)
	app.render_finished_semas = make([]Semaphore, app.swapchain.max_frames_in_flight)
	app.in_flight_fences = make([]Fence, app.swapchain.max_frames_in_flight)

	for i in 0 ..< app.swapchain.max_frames_in_flight {
		app.uniform_buffers[i] = create_uniform_buffer(Uniforms, app.device, app.physical_device)
		set_debug_name(app.device, app.uniform_buffers[i], fmt.tprintf("buffer:uniforms/{}", i))
		set_debug_name(
			app.device,
			app.uniform_buffers[i].memory,
			fmt.tprintf("buffer:uniforms/memory/{}", i),
		)

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

	populate_uniform_sets(app.device, app.uniform_sets, app.uniform_buffers)
}

destroy_app :: proc(app: ^App) {
	for i in 0 ..< app.swapchain.max_frames_in_flight {
		destroy_fence(app.device, &app.in_flight_fences[i])
		destroy_semaphore(app.device, &app.render_finished_semas[i])
		destroy_semaphore(app.device, &app.image_available_semas[i])
		free_command_buffer(app.device, app.graphics_pool, &app.graphics_buffers[i])
		destroy_uniform_buffer(app.device, &app.uniform_buffers[i])
	}
	delete(app.in_flight_fences)
	delete(app.render_finished_semas)
	delete(app.image_available_semas)
	delete(app.graphics_buffers)
	delete(app.uniform_buffers)
	delete(app.uniform_sets)
	destroy_descriptor_pool(app.device, &app.descriptor_pool)
	destroy_index_buffer(app.device, &app.index_buffer)
	destroy_vertex_buffer(app.device, &app.vertex_buffer)
	destroy_command_pool(app.device, &app.transfer_pool)
	destroy_command_pool(app.device, &app.graphics_pool)
	destroy_pipeline(app.device, &app.pipeline)
	destroy_render_pass(app.device, &app.render_pass)
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

	for !window_should_close(app.window) {
		update_window(&app.window)

		uniforms := &app.uniform_buffers[current_frame]
		uniform_set := app.uniform_sets[current_frame]
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

		reset_fence(app.device, &fence)

		signal_sema := app.render_finished_semas[image_index]

		// FIXME: The first couple frames are blank in RenderDoc due to mvp being all 0's. Why?
		update_uniforms(app.device, app.window, app.swapchain, uniforms)

		reset_command_buffer(buffer)
		record_commands(
			buffer,
			app.render_pass,
			app.swapchain,
			image_index,
			app.pipeline,
			app.vertex_buffer,
			app.index_buffer,
			uniform_set,
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

update_uniforms :: proc(
	device: Device,
	window: Window,
	swapchain: Swapchain,
	uniforms: ^Uniform_Buffer(Uniforms),
) {
	u: Uniforms

	time := cast(f32)window.time

	model := glm.mat4Rotate(glm.vec3{0, 0, 1}, time * glm.radians_f32(90))
	view := glm.mat4LookAt(glm.vec3{2, 2, 2}, 0, glm.vec3{0, 0, 1})
	projection := glm.mat4Perspective(
		glm.radians_f32(45),
		swapchain_extent_aspect_ratio(swapchain),
		0.1,
		10,
	)
	// TODO: We prolly want to do this at the end instead...
	projection[1, 1] *= -1 // Flip because we're not using GL
	u.mvp = projection * view * model

	uniforms.mapped^ = u
}

record_commands :: proc(
	cmd: Command_Buffer,
	pass: Render_Pass,
	swapchain: Swapchain,
	index: u32,
	pipeline: Pipeline,
	vertex_buffer: Vertex_Buffer,
	index_buffer: Index_Buffer,
	uniform_set: Descriptor_Set,
) {
	uniform_set := uniform_set

	command_buffer_begin(cmd, {})
	defer command_buffer_end(cmd)
	debug_label(cmd, "NOT TRIANGLE!", {1.0, 0.1, 0.5})

	clear_colour := vk.ClearValue {
		color = {float32 = {0, 0, 0, 1}},
	}

	pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = pass.handle,
		framebuffer = swapchain.framebuffers[index].handle,
		renderArea = {offset = {0, 0}, extent = swapchain.extent},
		clearValueCount = 1,
		pClearValues = &clear_colour,
	}

	vk.CmdBeginRenderPass(cmd.handle, &pass_info, .INLINE)

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

	vertex_buffers := []vk.Buffer{vertex_buffer.handle}
	offsets := []vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(
		cmd.handle,
		0,
		cast(u32)len(vertex_buffers),
		raw_data(vertex_buffers),
		raw_data(offsets),
	)

	vk.CmdBindIndexBuffer(cmd.handle, index_buffer.handle, 0, .UINT16)

	vk.CmdBindDescriptorSets(
		cmd.handle,
		.GRAPHICS,
		pipeline.layout.handle,
		0,
		1,
		&uniform_set.handle,
		0,
		nil,
	)
	vk.CmdDrawIndexed(cmd.handle, cast(u32)len(INDICES), 1, 0, 0, 0)

	vk.CmdEndRenderPass(cmd.handle)
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
		destroy_semaphore(app.device, &app.image_available_semas[current_frame])
		app.image_available_semas[current_frame] = create_semaphore(app.device)
		// Sema *then* swapchain is important
		recreate_swapchain(
			app.device,
			&app.swapchain,
			app.render_pass,
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
