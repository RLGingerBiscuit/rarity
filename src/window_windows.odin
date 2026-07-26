#+build windows
package rarity

import "core:sys/windows"
import "core:time"

_accurate_sleep :: proc "contextless" (d: time.Duration) {
	windows.timeBeginPeriod(1)
	defer windows.timeEndPeriod(1)
	time.accurate_sleep(d)
}
