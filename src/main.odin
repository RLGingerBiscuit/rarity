package rarity

import "base:runtime"
import "core:log"
import "core:mem"

_ :: mem

when ODIN_DEBUG {
	MIN_LOG_LEVEL :: log.Level.Debug
} else {
	MIN_LOG_LEVEL :: log.Level.Warning
}

logger: log.Logger
tracking_allocator: mem.Tracking_Allocator

init_logger :: proc() -> log.Logger {
	logger = log.create_console_logger(
		MIN_LOG_LEVEL,
		ident = "rarity",
		opt = log.Default_Console_Logger_Opts ~ {.Terminal_Color},
	)
	return logger
}

default_context :: proc() -> runtime.Context {
	ctx := runtime.default_context()
	when ODIN_DEBUG {
		ensure(tracking_allocator.backing.procedure != nil)
		ensure(logger.data != nil)
		ctx.allocator = mem.tracking_allocator(&tracking_allocator)
		ctx.logger = init_logger()
	}
	return ctx
}

main :: proc() {
	context.logger = init_logger()
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			total_leaked := 0
			for _, alloc in tracking_allocator.allocation_map {
				log.errorf("{}: Leaked {} bytes", alloc.location, alloc.size)
				total_leaked += alloc.size
			}
			for bad_free in tracking_allocator.bad_free_array {
				log.errorf("{}: Bad free {} at {}", bad_free.memory, bad_free.location)
			}
			if total_leaked > 0 {
				log.errorf("In total leaked {} bytes", total_leaked)
			}
		}
	}

	log.info("Hellope!")

	app: App
	init_app(&app)
	defer destroy_app(&app)
	app_run(&app)
}
