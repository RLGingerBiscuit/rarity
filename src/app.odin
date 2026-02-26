package rarity

import "core:fmt"
import "core:log"
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
	graphics_buffers:      []Command_Buffer,
	image_available_semas: []Semaphore,
	render_finished_semas: []Semaphore,
	in_flight_fences:      []Fence,
	max_frames_in_flight:  int,
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

	app.max_frames_in_flight = len(app.swapchain.images)
	app.graphics_buffers = make([]Command_Buffer, app.max_frames_in_flight)
	app.image_available_semas = make([]Semaphore, app.max_frames_in_flight)
	app.render_finished_semas = make([]Semaphore, app.max_frames_in_flight)
	app.in_flight_fences = make([]Fence, app.max_frames_in_flight)

	for i in 0 ..< app.max_frames_in_flight {
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

destroy_app :: proc(app: ^App) {
	for i in 0 ..< app.max_frames_in_flight {
		destroy_fence(app.device, &app.in_flight_fences[i])
		destroy_semaphore(app.device, &app.render_finished_semas[i])
		destroy_semaphore(app.device, &app.image_available_semas[i])
		free_command_buffer(app.device, app.graphics_pool, &app.graphics_buffers[i])
	}
	delete(app.in_flight_fences)
	delete(app.render_finished_semas)
	delete(app.image_available_semas)
	delete(app.graphics_buffers)
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

		reset_command_buffer(buffer)
		record_commands(
			buffer,
			app.render_pass,
			app.swapchain,
			image_index,
			app.pipeline,
			app.vertex_buffer,
		)

		queue_submit(app.graphics_queue, &buffer, wait_sema, signal_sema, fence)

		// This one doesn't matter as it's at the end of the frame anyway
		_maybe_recreate_swapchain(
			app,
			queue_present(app.present_queue, app.swapchain, image_index, signal_sema),
			current_frame,
		)

		current_frame = (current_frame + 1) % app.max_frames_in_flight

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
