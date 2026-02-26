package rarity

import "core:log"
import "core:strings"
import "vendor:glfw"

Window :: struct {
	handle:       glfw.WindowHandle,
	// Input
	cursor:       [2]f64,
	prev_cursor:  [2]f64,
	scroll:       [2]f64,
	prev_scroll:  [2]f64,
	buttons:      [Mouse_Button.Last]bool, // true==is down
	prev_buttons: [Mouse_Button.Last]bool,
	keys:         [Key.Last]bool,
	prev_keys:    [Key.Last]bool,
	_resized:     bool,
}

init_window :: proc(window: ^Window, title: string, width, height: int) {
	log.ensure(cast(bool)glfw.Init(), "Could not init GLFW")

	log.ensure(cast(bool)glfw.VulkanSupported(), "Vulkan is not supported")

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	// glfw.WindowHint(glfw.RESIZABLE, false)

	window.handle = glfw.CreateWindow(
		cast(i32)width,
		cast(i32)height,
		strings.clone_to_cstring(title, context.temp_allocator),
		nil,
		nil,
	)
	log.info("Created GLFW window:", window.handle)

	glfw.SetWindowUserPointer(window.handle, window)
	glfw.SetFramebufferSizeCallback(window.handle, _window_framebuffer_size_callback)
	glfw.SetCursorPosCallback(window.handle, _window_cursor_pos_callback)
	glfw.SetKeyCallback(window.handle, _window_key_callback)
	glfw.SetMouseButtonCallback(window.handle, _window_mouse_button_callback)
	glfw.SetScrollCallback(window.handle, _window_scroll_callback)
}

destroy_window :: proc(window: ^Window) {
	log.info("Destroying window")
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
	window^ = {}
}

window_should_close :: proc(window: Window) -> bool {
	return cast(bool)glfw.WindowShouldClose(window.handle)
}

set_window_should_close :: proc(wnd: ^Window, close: bool) {
	glfw.SetWindowShouldClose(wnd.handle, cast(b32)close)
}

update_window :: proc(window: ^Window) {
	glfw.PollEvents()

	if window_is_key_down(window^, .Escape) {
		set_window_should_close(window, true)
	}

	window.prev_cursor = window.cursor
	window.prev_scroll = window.scroll
	window.prev_keys = window.keys
	window.prev_buttons = window.buttons
	window.scroll = {}
}

window_wait :: proc(window: Window) {
	glfw.WaitEvents()
}

get_window_size :: proc(window: Window) -> (width, height: i32) {
	return glfw.GetFramebufferSize(window.handle)
}

// Raw input functions


window_get_key :: #force_inline proc(window: Window, key: Key) -> bool {
	return window.keys[key]
}
window_get_prev_key :: #force_inline proc(window: Window, key: Key) -> bool {
	return window.prev_keys[key]
}

window_get_button :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return window.buttons[button]
}
window_get_prev_button :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return window.prev_buttons[button]
}

window_get_scroll :: #force_inline proc(window: Window) -> [2]f64 {
	return window.scroll
}
window_get_prev_scroll :: #force_inline proc(window: Window) -> [2]f64 {
	return window.prev_scroll
}

// Input helper functions


window_is_key_up :: #force_inline proc(window: Window, key: Key) -> bool {
	return !window_get_key(window, key)
}
window_is_key_down :: #force_inline proc(window: Window, key: Key) -> bool {
	return !window_is_key_up(window, key)
}
window_was_key_up :: #force_inline proc(window: Window, key: Key) -> bool {
	return !window_get_prev_key(window, key)
}
window_was_key_down :: #force_inline proc(window: Window, key: Key) -> bool {
	return !window_was_key_up(window, key)
}
window_is_key_pressed :: #force_inline proc(window: Window, key: Key) -> bool {
	return window_is_key_down(window, key) && window_was_key_up(window, key)
}
window_is_key_released :: #force_inline proc(window: Window, key: Key) -> bool {
	return window_is_key_up(window, key) && window_was_key_down(window, key)
}

window_is_button_up :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return window_get_button(window, button)
}
window_is_button_down :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return !window_is_button_up(window, button)
}
window_was_button_up :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return window_get_prev_button(window, button)
}
window_was_button_down :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return !window_was_button_up(window, button)
}
window_is_button_pressed :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return window_is_button_down(window, button) && window_was_button_up(window, button)
}
window_is_button_released :: #force_inline proc(window: Window, button: Mouse_Button) -> bool {
	return window_is_button_up(window, button) && window_was_button_down(window, button)
}

// GLFW callbacks


_window_cursor_pos_callback :: proc "c" (handle: glfw.WindowHandle, x, y: f64) {
	ptr := glfw.GetWindowUserPointer(handle)
	window := cast(^Window)ptr
	window.cursor = {x, y}
}

_window_framebuffer_size_callback :: proc "c" (handle: glfw.WindowHandle, width, height: i32) {
	context = default_context()
	ptr := glfw.GetWindowUserPointer(handle)
	window := cast(^Window)ptr
	window._resized = true
}

_window_key_callback :: proc "c" (
	handle: glfw.WindowHandle,
	ikey, _scancode, iaction, _mods: i32,
) {
	if ikey == -1 {return}
	ptr := glfw.GetWindowUserPointer(handle)
	window := cast(^Window)ptr
	key := cast(Key)ikey
	action := iaction > 0
	window.keys[key] = action
}

_window_mouse_button_callback :: proc "c" (
	handle: glfw.WindowHandle,
	ibutton, iaction, _mods: i32,
) {
	ptr := glfw.GetWindowUserPointer(handle)
	window := cast(^Window)ptr
	button := cast(Mouse_Button)ibutton
	action := iaction > 0
	window.buttons[button] = action
}

_window_scroll_callback :: proc "c" (handle: glfw.WindowHandle, xoffset, yoffset: f64) {
	ptr := glfw.GetWindowUserPointer(handle)
	window := cast(^Window)ptr
	window.scroll = {xoffset, yoffset}
}


Key :: enum i32 {
	/* The unknown key */
	Unknown       = glfw.KEY_UNKNOWN,

	/** Printable keys **/

	/* Named printable keys */
	Space         = glfw.KEY_SPACE,
	Apostrophe    = glfw.KEY_APOSTROPHE, /* ' */
	Comma         = glfw.KEY_COMMA, /* , */
	Minus         = glfw.KEY_MINUS, /* - */
	Period        = glfw.KEY_PERIOD, /* . */
	Slash         = glfw.KEY_SLASH, /* / */
	Semicolon     = glfw.KEY_SEMICOLON, /* ; */
	Equal         = glfw.KEY_EQUAL, /*  */
	Left_Bracket  = glfw.KEY_LEFT_BRACKET, /* [ */
	Backslash     = glfw.KEY_BACKSLASH, /* \ */
	Right_Bracket = glfw.KEY_RIGHT_BRACKET, /* ] */
	Grave_Accent  = glfw.KEY_GRAVE_ACCENT, /* ` */
	World_1       = glfw.KEY_WORLD_1, /* non-US #1 */
	World_2       = glfw.KEY_WORLD_2, /* non-US #2 */

	/* Alphanumeric characters */
	D0            = glfw.KEY_0,
	D1            = glfw.KEY_1,
	D2            = glfw.KEY_2,
	D3            = glfw.KEY_3,
	D4            = glfw.KEY_4,
	D5            = glfw.KEY_5,
	D6            = glfw.KEY_6,
	D7            = glfw.KEY_7,
	D8            = glfw.KEY_8,
	D9            = glfw.KEY_9,
	A             = glfw.KEY_A,
	B             = glfw.KEY_B,
	C             = glfw.KEY_C,
	D             = glfw.KEY_D,
	E             = glfw.KEY_E,
	F             = glfw.KEY_F,
	G             = glfw.KEY_G,
	H             = glfw.KEY_H,
	I             = glfw.KEY_I,
	J             = glfw.KEY_J,
	K             = glfw.KEY_K,
	L             = glfw.KEY_L,
	M             = glfw.KEY_M,
	N             = glfw.KEY_N,
	O             = glfw.KEY_O,
	P             = glfw.KEY_P,
	Q             = glfw.KEY_Q,
	R             = glfw.KEY_R,
	S             = glfw.KEY_S,
	T             = glfw.KEY_T,
	U             = glfw.KEY_U,
	V             = glfw.KEY_V,
	W             = glfw.KEY_W,
	X             = glfw.KEY_X,
	Y             = glfw.KEY_Y,
	Z             = glfw.KEY_Z,


	/** Function keys **/

	/* Named non-printable keys */
	Escape        = glfw.KEY_ESCAPE,
	Enter         = glfw.KEY_ENTER,
	Tab           = glfw.KEY_TAB,
	Backspace     = glfw.KEY_BACKSPACE,
	Insert        = glfw.KEY_INSERT,
	Delete        = glfw.KEY_DELETE,
	Right         = glfw.KEY_RIGHT,
	Left          = glfw.KEY_LEFT,
	Down          = glfw.KEY_DOWN,
	Up            = glfw.KEY_UP,
	Page_Up       = glfw.KEY_PAGE_UP,
	Page_Down     = glfw.KEY_PAGE_DOWN,
	Home          = glfw.KEY_HOME,
	End           = glfw.KEY_END,
	Caps_Lock     = glfw.KEY_CAPS_LOCK,
	Scroll_Lock   = glfw.KEY_SCROLL_LOCK,
	Num_Lock      = glfw.KEY_NUM_LOCK,
	Print_Screen  = glfw.KEY_PRINT_SCREEN,
	Pause         = glfw.KEY_PAUSE,

	/* Function keys */
	F1            = glfw.KEY_F1,
	F2            = glfw.KEY_F2,
	F3            = glfw.KEY_F3,
	F4            = glfw.KEY_F4,
	F5            = glfw.KEY_F5,
	F6            = glfw.KEY_F6,
	F7            = glfw.KEY_F7,
	F8            = glfw.KEY_F8,
	F9            = glfw.KEY_F9,
	F10           = glfw.KEY_F10,
	F11           = glfw.KEY_F11,
	F12           = glfw.KEY_F12,
	F13           = glfw.KEY_F13,
	F14           = glfw.KEY_F14,
	F15           = glfw.KEY_F15,
	F16           = glfw.KEY_F16,
	F17           = glfw.KEY_F17,
	F18           = glfw.KEY_F18,
	F19           = glfw.KEY_F19,
	F20           = glfw.KEY_F20,
	F21           = glfw.KEY_F21,
	F22           = glfw.KEY_F22,
	F23           = glfw.KEY_F23,
	F24           = glfw.KEY_F24,
	F25           = glfw.KEY_F25,

	/* Keypad numbers */
	KP_0          = glfw.KEY_KP_0,
	KP_1          = glfw.KEY_KP_1,
	KP_2          = glfw.KEY_KP_2,
	KP_3          = glfw.KEY_KP_3,
	KP_4          = glfw.KEY_KP_4,
	KP_5          = glfw.KEY_KP_5,
	KP_6          = glfw.KEY_KP_6,
	KP_7          = glfw.KEY_KP_7,
	KP_8          = glfw.KEY_KP_8,
	KP_9          = glfw.KEY_KP_9,

	/* Keypad named function keys */
	KP_Decimal    = glfw.KEY_KP_DECIMAL,
	KP_Divide     = glfw.KEY_KP_DIVIDE,
	KP_Multiply   = glfw.KEY_KP_MULTIPLY,
	KP_Subtract   = glfw.KEY_KP_SUBTRACT,
	KP_Add        = glfw.KEY_KP_ADD,
	KP_Enter      = glfw.KEY_KP_ENTER,
	KP_Equal      = glfw.KEY_KP_EQUAL,

	/* Modifier keys */
	Left_Shift    = glfw.KEY_LEFT_SHIFT,
	Left_Control  = glfw.KEY_LEFT_CONTROL,
	Left_Alt      = glfw.KEY_LEFT_ALT,
	Left_Super    = glfw.KEY_LEFT_SUPER,
	Right_Shift   = glfw.KEY_RIGHT_SHIFT,
	Right_Control = glfw.KEY_RIGHT_CONTROL,
	Right_Alt     = glfw.KEY_RIGHT_ALT,
	Right_Super   = glfw.KEY_RIGHT_SUPER,
	Menu          = glfw.KEY_MENU,
	Last          = glfw.KEY_LAST,
}

Mouse_Button :: enum i32 {
	Left   = glfw.MOUSE_BUTTON_LEFT,
	Middle = glfw.MOUSE_BUTTON_MIDDLE,
	Right  = glfw.MOUSE_BUTTON_RIGHT,
	Last   = glfw.MOUSE_BUTTON_LAST,
}
