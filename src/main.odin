package rarity

import "core:fmt"
import "core:mem"

when !ODIN_DEBUG {
	_ :: mem
}

main :: proc() {
	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			total_leaked := 0
			for _, alloc in tracking_allocator.allocation_map {
				fmt.eprintfln("{}: Leaked {} bytes", alloc.location, alloc.size)
				total_leaked += alloc.size
			}
			for bad_free in tracking_allocator.bad_free_array {
				fmt.eprintfln("{}: Bad free {} at {}", bad_free.memory, bad_free.location)
			}
			if total_leaked > 0 {
				fmt.eprintfln("In total leaked {} bytes", total_leaked)
			}
		}
	}

	fmt.println("Hellope!")
}
