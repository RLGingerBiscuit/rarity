package rarity

import ar "artery"
import "core:fmt"
import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:slice"
import "core:unicode/utf8"
import vk "vendor:vulkan"

FONT_PATH :: "assets/fonts/Miracode.arfont"
// FONT_PATH :: "assets/fonts/Inter-Regular.arfont"
// FONT_PATH :: "assets/fonts/Monocraft.arfont"

// TODO: Some way better data structure than having the colours/thresholds per-glyph (possibly per-run?)
Glyph_Vertex :: struct #packed {
	position:               glm.vec2,
	tex_coord:              glm.vec2,
	colour, outline_colour: glm.vec4,
	threshold_em:           f32,
	outline_em:             f32,
	roundness:              f32,
}

// TODO: kerning
Font :: struct {
	ar:                    ar.Font,
	default_variant_index: int,
	luts:                  []map[u32]int, // lut[variant_index][codepoint] == index
	vertices:              [dynamic]Glyph_Vertex,
	indices:               [dynamic]u16,
	vbo:                   Vertex_Buffer(Glyph_Vertex),
	ebo:                   Index_Buffer,
	atlas_image:           Image,
	atlas_view:            Image_View,
	atlas_sampler:         Sampler,
	pipeline:              Pipeline,
	font_sets:             []Descriptor_Set,
	frame_images:          []Image,
	frame_views:           []Image_View,
	frame_sampler:         Sampler,
	frame_sets:            []Descriptor_Set,
}

destroy_font :: proc(device: Device, font: ^Font) {
	ar.destroy_font(&font.ar)
	delete(font.frame_sets)
	destroy_sampler(device, &font.frame_sampler)
	for &view in font.frame_views {
		destroy_image_view(device, &view)
	}
	for &image in font.frame_images {
		destroy_image(device, &image)
	}
	delete(font.frame_views)
	delete(font.frame_images)
	delete(font.font_sets)
	destroy_pipeline(device, &font.pipeline)
	unmap_buffer_memory(device, font.ebo.buffer)
	destroy_index_buffer(device, &font.ebo)
	unmap_buffer_memory(device, font.vbo.buffer)
	destroy_vertex_buffer(device, &font.vbo)
	destroy_sampler(device, &font.atlas_sampler)
	destroy_image_view(device, &font.atlas_view)
	destroy_image(device, &font.atlas_image)
	for lut in font.luts {
		delete(lut)
	}
	delete(font.luts)

	font^ = {}
}

load_font_from_path :: proc(
	path: string,
	device: Device,
	physical_device: Physical_Device,
	swapchain: Swapchain,
	descriptor_pool: Descriptor_Pool,
	descriptor_layout: Descriptor_Set_Layout,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
	allocator := context.allocator,
) -> Font {
	file_data, err := os.read_entire_file(path, context.temp_allocator)
	log.ensuref(err == nil, "Could not open '{}': {}", path, err)
	return load_font_from_memory(
		file_data,
		device,
		physical_device,
		swapchain,
		immediate_pool,
		graphics_pool,
		immediate_fence,
		transfer_queue,
		graphics_queue,
		descriptor_pool,
		descriptor_layout,
		allocator,
	)
}

load_font_from_memory :: proc(
	data: []byte,
	device: Device,
	physical_device: Physical_Device,
	swapchain: Swapchain,
	immediate_pool: Command_Pool,
	graphics_pool: Command_Pool,
	immediate_fence: Fence,
	transfer_queue: Queue,
	graphics_queue: Queue,
	descriptor_pool: Descriptor_Pool,
	descriptor_layout: Descriptor_Set_Layout,
	allocator := context.allocator,
) -> (
	font: Font,
) {
	context.allocator = allocator

	err: ar.Error
	font.ar, err = ar.load_font_from_memory(data, allocator)
	log.ensuref(err == nil, "Could not load font: {}", err)

	DEFAULT_WEIGHT :: 400

	variant_index: int
	min_variant_weight := 1000
	for variant, i in font.ar.variants {
		if weight := math.abs(DEFAULT_WEIGHT - cast(int)variant.weight);
		   weight < min_variant_weight {
			variant_index = i
			min_variant_weight = weight
			if variant.weight == DEFAULT_WEIGHT {
				break
			}
		}
	}

	font.default_variant_index = variant_index

	font.luts = make([]map[u32]int, len(font.ar.variants))
	for i in 0 ..< len(font.luts) {
		variant := font.ar.variants[i]
		font.luts[i] = make(map[u32]int, len(variant.glyphs))
		for glyph, j in variant.glyphs {
			font.luts[i][glyph.codepoint] = j
		}
	}

	image := font.ar.images[0]
	vk_format: vk.Format
	switch image.channels {
	case 1:
		vk_format = .R8_UNORM
	case 3:
		vk_format = .R8G8B8_UNORM
	case 4:
		vk_format = .R8G8B8A8_UNORM
	case:
		log.panicf("Invalid channel count for font: {}", image.channels)
	}

	font.atlas_image = upload_image(
		image.data,
		cast(int)image.width,
		cast(int)image.height,
		cast(int)image.channels,
		device,
		physical_device,
		immediate_pool,
		graphics_pool,
		immediate_fence,
		transfer_queue,
		graphics_queue,
		vk_format,
	)
	font.atlas_view = image_to_view(device, font.atlas_image, {.COLOR})
	font.atlas_sampler = create_sampler(
		device,
		physical_device,
		.LINEAR,
		.LINEAR,
		.LINEAR,
		.CLAMP_TO_EDGE,
		.CLAMP_TO_EDGE,
	)
	set_debug_name(device, font.atlas_image, "font:atlas/image")
	set_debug_name(device, font.atlas_view, "font:atlas/view")
	set_debug_name(device, font.atlas_sampler, "font:atlas/sampler")

	font.vbo = create_vertex_buffer(
		device,
		physical_device,
		GLYPH_BUFFER_SIZE * 4,
		Glyph_Vertex,
		usage = {},
		props = {.HOST_VISIBLE, .HOST_COHERENT},
	)
	font.ebo = create_index_buffer(
		device,
		physical_device,
		GLYPH_BUFFER_SIZE * 6,
		u16,
		usage = {},
		props = {.HOST_VISIBLE, .HOST_COHERENT},
	)
	set_debug_name(device, font.atlas_view, "font:vbo")
	set_debug_name(device, font.atlas_sampler, "font:ebo")

	mapped_vertices := map_buffer_memory(
		Glyph_Vertex,
		device,
		font.vbo.buffer,
		size_of(Glyph_Vertex) * GLYPH_BUFFER_SIZE * 4,
	)
	mapped_indices := map_buffer_memory(
		u16,
		device,
		font.ebo.buffer,
		size_of(u16) * GLYPH_BUFFER_SIZE * 6,
	)

	font.vertices = slice.into_dynamic(mapped_vertices)
	font.vertices.allocator = mem.panic_allocator()
	clear(&font.vertices)
	font.indices = slice.into_dynamic(mapped_indices)
	font.indices.allocator = mem.panic_allocator()
	clear(&font.indices)

	font.font_sets = allocate_descriptor_sets(
		device,
		descriptor_pool,
		descriptor_layout,
		swapchain.max_frames_in_flight,
	)
	populate_descriptor_sets(device, font.font_sets, font.atlas_view, font.atlas_sampler)

	font.pipeline = create_font_pipeline(device, swapchain, descriptor_layout)

	font.frame_images = make([]Image, swapchain.max_frames_in_flight)
	font.frame_views = make([]Image_View, swapchain.max_frames_in_flight)
	for i in 0 ..< swapchain.max_frames_in_flight {
		font.frame_images[i] = create_render_target_image(
			device,
			physical_device,
			swapchain.extent.width,
			swapchain.extent.height,
			swapchain.format.format,
			{.COLOR_ATTACHMENT, .SAMPLED, .TRANSFER_DST},
		)
		set_debug_name(device, font.frame_images[i], fmt.tprintf("font:image/{}", i))
		font.frame_views[i] = image_to_view(device, font.frame_images[i], {.COLOR})
		set_debug_name(device, font.frame_views[i], fmt.tprintf("font:view/{}", i))
	}

	font.frame_sampler = create_sampler(
		device,
		physical_device,
		.NEAREST,
		.NEAREST,
		.NEAREST,
		.CLAMP_TO_EDGE,
		.CLAMP_TO_EDGE,
	)
	set_debug_name(device, font.frame_sampler, "font:frame/sampler")

	font.frame_sets = allocate_descriptor_sets(
		device,
		descriptor_pool,
		descriptor_layout,
		swapchain.max_frames_in_flight,
	)
	for i in 0 ..< len(font.frame_sets) {
		populate_descriptor_sets(
			device,
			font.frame_sets[i:i + 1],
			font.frame_views[i],
			font.frame_sampler,
		)
	}

	return
}

load_font :: proc {
	load_font_from_path,
	load_font_from_memory,
}

recreate_font_data :: proc(
	device: Device,
	font: ^Font,
	physical_device: Physical_Device,
	swapchain: Swapchain,
	descriptor_pool: Descriptor_Pool,
	descriptor_layout: Descriptor_Set_Layout,
) {
	for &view in font.frame_views {
		destroy_image_view(device, &view)
	}
	for &image in font.frame_images {
		destroy_image(device, &image)
	}
	delete(font.frame_views)
	delete(font.frame_images)
	delete(font.frame_sets)
	delete(font.font_sets)
	destroy_pipeline(device, &font.pipeline)

	font.font_sets = allocate_descriptor_sets(
		device,
		descriptor_pool,
		descriptor_layout,
		swapchain.max_frames_in_flight,
	)
	populate_descriptor_sets(device, font.font_sets, font.atlas_view, font.atlas_sampler)

	font.pipeline = create_font_pipeline(device, swapchain, descriptor_layout)

	font.frame_images = make([]Image, swapchain.max_frames_in_flight)
	font.frame_views = make([]Image_View, swapchain.max_frames_in_flight)
	for i in 0 ..< swapchain.max_frames_in_flight {
		font.frame_images[i] = create_render_target_image(
			device,
			physical_device,
			swapchain.extent.width,
			swapchain.extent.height,
			swapchain.format.format,
			{.COLOR_ATTACHMENT, .SAMPLED, .TRANSFER_DST},
		)
		set_debug_name(device, font.frame_images[i], fmt.tprintf("font:image/{}", i))
		font.frame_views[i] = image_to_view(device, font.frame_images[i], {.COLOR})
		set_debug_name(device, font.frame_views[i], fmt.tprintf("font:view/{}", i))
	}

	font.frame_sets = allocate_descriptor_sets(
		device,
		descriptor_pool,
		descriptor_layout,
		swapchain.max_frames_in_flight,
	)
	for i in 0 ..< len(font.frame_sets) {
		populate_descriptor_sets(
			device,
			font.frame_sets[i:i + 1],
			font.frame_views[i],
			font.frame_sampler,
		)
	}
}

font_measure_text :: proc(
	font: Font,
	text: string,
	font_size: f32 = -1,
	variant_index := -1,
) -> (
	size: [2]f32,
) {
	variant_index := variant_index
	font_size := font_size

	variant_valid := variant_index >= 0 && variant_index < len(font.ar.variants)

	if font_size < 0 {
		if variant_valid {
			font_size = font.ar.variants[variant_index].metrics.font_size
		} else {
			variant_index = font.default_variant_index
			font_size = font.ar.variants[variant_index].metrics.font_size
		}
	} else if !variant_valid {
		closest_index := font.default_variant_index
		closest := max(f32)

		for variant, i in font.ar.variants {
			diff := math.abs(font_size - variant.metrics.font_size)
			if diff < closest {
				closest = diff
				closest_index = i
				if diff <= 1e-6 {
					break
				}
			}
		}

		variant_index = closest_index
	}

	str := text
	variant := font.ar.variants[variant_index]
	lut := font.luts[variant_index]

	rect := [4]f32{math.inf_f32(+1), math.inf_f32(+1), math.inf_f32(-1), math.inf_f32(-1)}
	pen: [2]f32

	for str != "" {
		ch, w := utf8.decode_rune(str)
		defer str = str[w:]

		metrics: ^ar.Metrics
		glyph: ar.Glyph
		glyph_idx, ok := lut[u32(ch)]
		if ok {
			glyph = variant.glyphs[glyph_idx]
			metrics = &variant.metrics
		} else if variant.fallback_glyph < cast(u32)len(variant.glyphs) {
			glyph = variant.glyphs[variant.fallback_glyph]
			metrics = &variant.metrics
			ok = true
		} else {
			fallback_variant := font.ar.variants[variant.fallback_variant]
			fallback_lut := font.luts[variant.fallback_variant]

			glyph_idx, ok = fallback_lut[u32(ch)]
			if ok {
				glyph = fallback_variant.glyphs[glyph_idx]
				metrics = &fallback_variant.metrics
			} else if fallback_variant.fallback_glyph < cast(u32)len(fallback_variant.glyphs) {
				glyph = fallback_variant.glyphs[fallback_variant.fallback_glyph]
				metrics = &fallback_variant.metrics
				ok = true
			}
		}

		if !ok {
			// Wow we literally didn't find anything. Fine then. Skip!
			continue
		}

		// TODO: kerning
		scale := font_size / metrics.em_size
		pb := glyph.plane_bounds
		rect.x = math.min(rect.x, pen.x + scale * pb.left)
		rect.y = math.min(rect.y, pen.y + scale * pb.bottom)
		rect.z = math.max(rect.z, pen.x + scale * pb.right)
		rect.w = math.max(rect.w, pen.y + scale * pb.top)

		pen.x += scale * glyph.advance.h
		pen.y += scale * glyph.advance.v
	}

	size = {rect.z - rect.x, rect.w - rect.y}

	return
}

render_text :: proc(
	cmd: Command_Buffer,
	font: ^Font,
	window: Window,
	swapchain: Swapchain,
	frame_index: u32,
	text: string,
	pos: glm.vec2,
	colour := glm.vec4{1, 1, 1, 1},
	threshold_em: f32 = 0,
	outline_colour := glm.vec4{0, 0, 0, 0},
	outline_em: f32 = 0,
	font_size: f32 = -1,
	variant_index := -1,
) {
	variant_index := variant_index
	font_size := font_size

	variant_valid := variant_index >= 0 && variant_index < len(font.ar.variants)

	if font_size < 0 {
		if variant_valid {
			font_size = font.ar.variants[variant_index].metrics.font_size
		} else {
			variant_index = font.default_variant_index
			font_size = font.ar.variants[variant_index].metrics.font_size
		}
	} else if !variant_valid {
		closest_index := font.default_variant_index
		closest := max(f32)

		for variant, i in font.ar.variants {
			diff := math.abs(font_size - variant.metrics.font_size)
			if diff < closest {
				closest = diff
				closest_index = i
				if diff <= 1e-6 {
					break
				}
			}
		}

		variant_index = closest_index
	}

	str := text
	variant := font.ar.variants[variant_index]
	lut := font.luts[variant_index]

	pen := pos

	for str != "" {
		ch, w := utf8.decode_rune(str)
		defer str = str[w:]

		metrics: ^ar.Metrics
		glyph: ar.Glyph
		glyph_idx, ok := lut[u32(ch)]
		if ok {
			glyph = variant.glyphs[glyph_idx]
			metrics = &variant.metrics
		} else if variant.fallback_glyph < cast(u32)len(variant.glyphs) {
			glyph = variant.glyphs[variant.fallback_glyph]
			metrics = &variant.metrics
			ok = true
		} else {
			fallback_variant := font.ar.variants[variant.fallback_variant]
			fallback_lut := font.luts[variant.fallback_variant]

			glyph_idx, ok = fallback_lut[u32(ch)]
			if ok {
				glyph = fallback_variant.glyphs[glyph_idx]
				metrics = &fallback_variant.metrics
			} else if fallback_variant.fallback_glyph < cast(u32)len(fallback_variant.glyphs) {
				glyph = fallback_variant.glyphs[fallback_variant.fallback_glyph]
				metrics = &fallback_variant.metrics
				ok = true
			}
		}

		if !ok {
			// Wow we literally didn't find anything. Fine then. Skip!
			continue
		}

		// TODO: kerning
		scale := font_size / metrics.em_size
		pb := glyph.plane_bounds
		ib := glyph.image_bounds
		img := font.ar.images[glyph.image]
		frame_size := cast(glm.vec2)font.frame_images[0].size

		x0 := 2 * (pen.x + pb.left * scale) / frame_size.x - 1
		x1 := 2 * (pen.x + pb.right * scale) / frame_size.x - 1
		y0 := 2 * (pen.y + pb.bottom * scale) / frame_size.y - 1
		y1 := 2 * (pen.y + pb.top * scale) / frame_size.y - 1

		u0 := ib.left / cast(f32)img.width
		u1 := ib.right / cast(f32)img.width
		v0 := 1 - ib.bottom / cast(f32)img.height
		v1 := 1 - ib.top / cast(f32)img.height

		base := cast(u16)len(font.vertices)
		vert := Glyph_Vertex {
			position       = glm.vec2{x0, y0},
			tex_coord      = glm.vec2{u0, v0},
			colour         = colour,
			outline_colour = outline_colour,
			threshold_em   = threshold_em,
			outline_em     = outline_em,
			roundness      = 0,
		}
		append(&font.vertices, vert)
		vert.position = glm.vec2{x1, y0}
		vert.tex_coord = glm.vec2{u1, v0}
		append(&font.vertices, vert)
		vert.position = glm.vec2{x1, y1}
		vert.tex_coord = glm.vec2{u1, v1}
		append(&font.vertices, vert)
		vert.position = glm.vec2{x0, y1}
		vert.tex_coord = glm.vec2{u0, v1}
		append(&font.vertices, vert)

		append(&font.indices, base + 0, base + 1, base + 2, base + 0, base + 2, base + 3)

		pen.x += scale * glyph.advance.h
		pen.y += scale * glyph.advance.v
	}
}

begin_text :: proc(cmd: Command_Buffer, font: ^Font, swapchain: Swapchain, frame_index: u32) {
	debug_label_begin(cmd, "Font", {0.0, 0.0, 1.0})

	clear(&font.vertices)
	clear(&font.indices)

	cmd_image_barrier(
		cmd,
		font.frame_images[frame_index],
		.UNDEFINED,
		.ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)

	font_clear := vk.ClearValue {
		color = {float32 = {0, 0, 0, 0}},
	}
	font_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = font.frame_views[frame_index].handle,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = font_clear,
	}
	font_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &font_attachment,
		renderArea = {offset = {0, 0}, extent = swapchain.extent},
	}

	vk.CmdBeginRendering(cmd.handle, &font_info)
	vk.CmdBindPipeline(cmd.handle, .GRAPHICS, font.pipeline.handle)
	font_set := font.font_sets[frame_index]
	vk.CmdBindDescriptorSets(
		cmd.handle,
		.GRAPHICS,
		font.pipeline.layout.handle,
		0,
		1,
		&font_set.handle,
		0,
		nil,
	)
	vertex_buffers := []vk.Buffer{font.vbo.handle}
	offsets := []vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(
		cmd.handle,
		0,
		cast(u32)len(vertex_buffers),
		raw_data(vertex_buffers),
		raw_data(offsets),
	)
	vk.CmdBindIndexBuffer(cmd.handle, font.ebo.handle, 0, .UINT16)
}

end_text :: proc(cmd: Command_Buffer, font: ^Font, window: Window, frame_index: u32) {
	default_variant := font.ar.variants[font.default_variant_index]
	metrics := default_variant.metrics

	aemrange: glm.vec2
	{
		min := (metrics.distance_range_middle - metrics.distance_range / 2) / metrics.font_size
		max := (metrics.distance_range_middle + metrics.distance_range / 2) / metrics.font_size
		aemrange = {min, max}
	}

	// screen_px_scale: f32
	// {
	// 	variant := font.ar.variants[font.default_variant_index]
	// 	lut := font.luts[font.default_variant_index]
	// 	glyph := variant.glyphs[lut['A']]
	// 	scale := font_size / variant.metrics.em_size
	// 	input_size_px := glyph.image_bounds.right - glyph.image_bounds.left
	// 	output_size_px := (glyph.plane_bounds.right - glyph.plane_bounds.left) * scale
	// 	screen_px_scale = output_size_px / input_size_px
	// }

	antialias_em: f32 = 1
	{
		w_w, _ := get_window_size(window)
		fb_w, _ := window_get_framebuffer_size(window)
		cs_x, _ := window_get_content_scale(window)
		fb_to_screen := cast(f32)fb_w / (cs_x * cast(f32)w_w)
		aa_fb_px := antialias_em * fb_to_screen
		antialias_em = metrics.font_size / aa_fb_px
	}

	FLAG_MSDF :: 0x01
	FLAG_MTSDF :: 0x02
	flags: u32

	#partial switch font.ar.variants[font.default_variant_index].image_type {
	case .Mtsdf:
		flags |= FLAG_MTSDF
		fallthrough
	case .Msdf:
		flags |= FLAG_MSDF
	}

	pc := Font_Push_Constants {
		aemrange     = aemrange,
		antialias_em = antialias_em,
		flags        = flags,
	}
	vk.CmdPushConstants(
		cmd.handle,
		font.pipeline.layout.handle,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(Font_Push_Constants),
		&pc,
	)
	vk.CmdDrawIndexed(cmd.handle, cast(u32)len(font.indices), 1, 0, 0, 0)
	vk.CmdEndRendering(cmd.handle)
	cmd_image_barrier(
		cmd,
		font.frame_images[frame_index],
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR},
	)
	debug_label_end(cmd)
}

@(private = "file")
GLYPH_BUFFER_SIZE :: 1 << 16

@(rodata)
FONT_BINDING_DESCRIPTION := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Glyph_Vertex),
	inputRate = .VERTEX,
}

@(rodata)
FONT_ATTRIBUTE_DESCRIPTIONS := []vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, position),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, tex_coord),
	},
	{
		binding = 0,
		location = 2,
		format = .R32G32B32A32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, colour),
	},
	{
		binding = 0,
		location = 3,
		format = .R32G32B32A32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, outline_colour),
	},
	{
		binding = 0,
		location = 4,
		format = .R32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, threshold_em),
	},
	{
		binding = 0,
		location = 5,
		format = .R32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, outline_em),
	},
	{
		binding = 0,
		location = 6,
		format = .R32_SFLOAT,
		offset = cast(u32)offset_of(Glyph_Vertex, roundness),
	},
}
