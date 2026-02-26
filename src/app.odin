package rarity

import vk "vendor:vulkan"

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
	swapchain:             Swapchain,
	render_pass:           Render_Pass,
	pipeline:              Pipeline,
	command_pool:          Command_Pool,
	command_buffers:       []Command_Buffer,
	image_available_semas: []Semaphore,
	render_finished_sema:  []Semaphore,
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
		api_version = vk.API_VERSION_1_0,
	)

	app.surface = create_surface(app.instance, app.window)

	app.physical_device = choose_physical_device(app.instance, app.surface)

	app.device = create_logical_device(app.physical_device)
	app.graphics_queue = get_queue(app.device, app.device.indices.graphics.?, 0)
	app.present_queue = get_queue(app.device, app.device.indices.present.?, 0)

	app.swapchain = create_swapchain(app.device, app.physical_device, app.window, app.surface)
	app.render_pass = create_render_pass(app.device, app.swapchain)
	app.pipeline = create_pipeline(app.device, app.swapchain, app.render_pass)

	create_framebuffers(app.device, &app.swapchain, app.render_pass)

	app.command_pool = create_command_pool(app.device)

	app.max_frames_in_flight = len(app.swapchain.images)

	app.command_buffers = make([]Command_Buffer, app.max_frames_in_flight)
	app.image_available_semas = make([]Semaphore, app.max_frames_in_flight)
	app.render_finished_sema = make([]Semaphore, app.max_frames_in_flight)
	app.in_flight_fences = make([]Fence, app.max_frames_in_flight)

	for i in 0 ..< app.max_frames_in_flight {
		app.command_buffers[i] = allocate_command_buffer(app.device, app.command_pool)
		app.image_available_semas[i] = create_semaphore(app.device)
		app.render_finished_sema[i] = create_semaphore(app.device)
		app.in_flight_fences[i] = create_fence(app.device)
	}
}

destroy_app :: proc(app: ^App) {
	for i in 0 ..< app.max_frames_in_flight {
		destroy_fence(app.device, &app.in_flight_fences[i])
		destroy_semaphore(app.device, &app.render_finished_sema[i])
		destroy_semaphore(app.device, &app.image_available_semas[i])
		free_command_buffer(app.device, app.command_pool, &app.command_buffers[i])
	}
	delete(app.in_flight_fences)
	delete(app.render_finished_sema)
	delete(app.image_available_semas)
	delete(app.command_buffers)
	destroy_command_pool(app.device, &app.command_pool)
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

		buffer := app.command_buffers[current_frame]
		wait_sema := app.image_available_semas[current_frame]
		fence := app.in_flight_fences[current_frame]

		wait_for_fence(app.device, &fence)
		reset_fence(app.device, &fence)

		image_index := acquire_next_image(app.device, app.swapchain, wait_sema)

		signal_sema := app.render_finished_sema[image_index]

		reset_command_buffer(buffer)
		record_commands(buffer, app.render_pass, app.swapchain, app.pipeline, image_index)

		queue_submit(app.graphics_queue, &buffer, wait_sema, signal_sema, fence)

		queue_present(app.present_queue, app.swapchain, image_index, signal_sema)

		current_frame = (current_frame + 1) % app.max_frames_in_flight
	}

	device_wait_idle(app.device)
}
