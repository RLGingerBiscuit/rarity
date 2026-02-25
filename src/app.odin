package rarity

APP_WIDTH :: 800
APP_HEIGHT :: 600

App :: struct {
	window: Window,
}

init_app :: proc(app: ^App) {
	init_window(&app.window, "Rarity", APP_WIDTH, APP_HEIGHT)
}

destroy_app :: proc(app: ^App) {
	destroy_window(&app.window)
}

app_run :: proc(app: ^App) {
	for !window_should_close(app.window) {
		update_window(&app.window)
	}
}
