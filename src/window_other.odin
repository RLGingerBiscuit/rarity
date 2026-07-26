#+build !windows
package rarity

import "core:time"

_accurate_sleep :: proc "contextless" (d: time.Duration) {
	time.accurate_sleep(d)
}
