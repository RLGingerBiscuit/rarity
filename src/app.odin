package rarity

import vk "vendor:vulkan"

APP_TITLE :: "Rarity"
APP_WIDTH :: 800
APP_HEIGHT :: 600

App :: struct {
	window:          Window,
	instance:        Instance,
	surface:         Surface,
	physical_device: Physical_Device,
	device:          Device,
	graphics_queue:  Queue,
	present_queue:   Queue,
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
}

destroy_app :: proc(app: ^App) {
	destroy_surface(app.instance, &app.surface)
	destroy_logical_device(&app.device)
	destroy_instance(&app.instance)
	destroy_window(&app.window)
	app^ = {}
}

app_run :: proc(app: ^App) {
	for !window_should_close(app.window) {
		update_window(&app.window)
	}
}
