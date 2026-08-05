package rarity

import ar "artery"
import "core:fmt"
import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import vk "vendor:vulkan"

FONT_PATHS :: [?]string {
	"assets/fonts/Inter-Regular.arfont",
	"assets/fonts/Monocraft.arfont",
	"assets/fonts/Miracode.arfont",
}

Glyph_Vertex :: struct #packed {
	position:  glm.vec2,
	tex_coord: glm.vec2,
}

// TODO: kerning
Font :: struct {
	name:                  string,
	ar:                    ar.Font,
	default_variant_index: int,
	luts:                  []map[u32]int, // lut[variant_index][codepoint] == index
	// Mapped from one contiguous vbo/ebo; uses panic allocator
	vertices:              [][dynamic]Glyph_Vertex,
	indices:               [][dynamic]u16,
	vbo:                   Vertex_Buffer(Glyph_Vertex),
	ebo:                   Index_Buffer,
	atlas_image:           Image,
	atlas_view:            Image_View,
	atlas_sampler:         Sampler,
	atlas_set:             Descriptor_Set,
}

destroy_font :: proc(device: Device, font: ^Font) {
	ar.destroy_font(&font.ar)
	unmap_buffer_memory(device, font.ebo.buffer)
	destroy_index_buffer(device, &font.ebo)
	delete(font.indices)
	unmap_buffer_memory(device, font.vbo.buffer)
	destroy_vertex_buffer(device, &font.vbo)
	delete(font.vertices)
	destroy_sampler(device, &font.atlas_sampler)
	destroy_image_view(device, &font.atlas_view)
	destroy_image(device, &font.atlas_image)
	for lut in font.luts {
		delete(lut)
	}
	delete(font.luts)
	delete(font.name)

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
	name := "",
	allocator := context.allocator,
) -> Font {
	file_data, err := os.read_entire_file(path, context.temp_allocator)
	log.ensuref(err == nil, "Could not open '{}': {}", path, err)
	return load_font_from_memory(
		filepath.short_stem(filepath.base(path)) if name == "" else name,
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
	name: string,
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

	font.name = strings.clone(name)

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
	set_debug_name(device, font.atlas_image, fmt.tprintf("font:{}/atlas/image", font.name))
	set_debug_name(device, font.atlas_view, fmt.tprintf("font:{}/atlas/view", font.name))
	set_debug_name(device, font.atlas_sampler, fmt.tprintf("font:{}/atlas/sampler", font.name))

	total_vertex_count := FRAME_VERTEX_COUNT * cast(vk.DeviceSize)swapchain.max_frames_in_flight
	total_index_count := FRAME_INDEX_COUNT * cast(vk.DeviceSize)swapchain.max_frames_in_flight

	font.vbo = create_vertex_buffer(
		device,
		physical_device,
		total_vertex_count,
		Glyph_Vertex,
		usage = {},
		props = {.HOST_VISIBLE, .HOST_COHERENT},
	)
	font.ebo = create_index_buffer(
		device,
		physical_device,
		total_index_count,
		u16,
		usage = {},
		props = {.HOST_VISIBLE, .HOST_COHERENT},
	)
	set_debug_name(device, font.vbo.buffer, fmt.tprintf("font:{}/vbo", font.name))
	set_debug_name(device, font.ebo.buffer, fmt.tprintf("font:{}/ebo", font.name))

	mapped_vertices := map_buffer_memory(
		Glyph_Vertex,
		device,
		font.vbo.buffer,
		size_of(Glyph_Vertex) * total_vertex_count,
	)
	mapped_indices := map_buffer_memory(
		u16,
		device,
		font.ebo.buffer,
		size_of(u16) * total_index_count,
	)

	font.vertices = make([][dynamic]Glyph_Vertex, swapchain.max_frames_in_flight)
	font.indices = make([][dynamic]u16, swapchain.max_frames_in_flight)
	for i in 0 ..< cast(vk.DeviceSize)swapchain.max_frames_in_flight {
		font.vertices[i] = slice.into_dynamic(
			mapped_vertices[i * FRAME_VERTEX_COUNT:(i + 1) * FRAME_VERTEX_COUNT],
		)
		font.vertices[i].allocator = mem.panic_allocator()
		clear(&font.vertices[i])
		font.indices[i] = slice.into_dynamic(
			mapped_indices[i * FRAME_INDEX_COUNT:(i + 1) * FRAME_INDEX_COUNT],
		)
		font.indices[i].allocator = mem.panic_allocator()
		clear(&font.indices[i])
	}

	allocate_font_descriptor_set(device, &font, descriptor_pool, descriptor_layout)

	return
}

load_font :: proc {
	load_font_from_path,
	load_font_from_memory,
}

allocate_font_descriptor_set :: proc(
	device: Device,
	font: ^Font,
	descriptor_pool: Descriptor_Pool,
	descriptor_layout: Descriptor_Set_Layout,
) {
	sets := allocate_descriptor_sets(device, descriptor_pool, descriptor_layout, 1)
	defer delete(sets)
	populate_descriptor_sets(device, sets, font.atlas_view, font.atlas_sampler)
	font.atlas_set = sets[0]
	set_debug_name(device, font.atlas_set, fmt.tprintf("font:{}/atlas/set", font.name))
}

// Returns the font size and variant index best matching the inputs.
_font_get_best_match :: proc(
	font: Font,
	font_size: f32,
	variant_index: int,
) -> (
	out_size: f32,
	out_index: int,
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

	return font_size, variant_index
}

// Returns the glyph (and variant index) best matching the requested character.
_font_get_best_glyph :: proc(
	font: Font,
	ch: rune,
	variant_index: int,
) -> (
	glyph: ar.Glyph,
	out_variant_index: int,
	ok: bool,
) {
	out_variant_index = variant_index

	lut := font.luts[variant_index]
	variant := font.ar.variants[variant_index]

	glyph_idx: int
	glyph_idx, ok = lut[u32(ch)]
	if ok {
		glyph = variant.glyphs[glyph_idx]
		return glyph, out_variant_index, true
	} else if variant.fallback_glyph < cast(u32)len(variant.glyphs) {
		glyph = variant.glyphs[variant.fallback_glyph]
		return glyph, out_variant_index, true
	} else if len(font.ar.variants) > 1 {
		lut = font.luts[variant.fallback_variant]
		variant = font.ar.variants[variant.fallback_variant]
		out_variant_index = cast(int)variant.fallback_variant

		glyph_idx, ok = lut[u32(ch)]
		if ok {
			glyph = variant.glyphs[glyph_idx]
			return glyph, out_variant_index, true
		} else if variant.fallback_glyph < cast(u32)len(variant.glyphs) {
			glyph = variant.glyphs[variant.fallback_glyph]
			return glyph, out_variant_index, true
		}
	}

	return {}, 0, false
}

// Returns the line height (in px).
font_line_height :: proc(font: Font, font_size: f32 = -1, variant_index := -1) -> f32 {
	variant_index := variant_index
	font_size := font_size
	font_size, variant_index = _font_get_best_match(font, font_size, variant_index)

	variant := font.ar.variants[variant_index]
	metrics := variant.metrics
	scale := font_size / metrics.em_size

	return metrics.line_height * scale
}

// Returns the ascender and descender (in px).
font_vertical_metrics :: proc(font: Font, font_size: f32 = -1, variant_index := -1) -> [2]f32 {
	variant_index := variant_index
	font_size := font_size
	font_size, variant_index = _font_get_best_match(font, font_size, variant_index)

	variant := font.ar.variants[variant_index]
	metrics := variant.metrics
	scale := font_size / metrics.em_size

	return {metrics.ascender * scale, max(0, -metrics.descender * scale)}
}

// Returns the full size of a given length of text (in px).
//
// - **font_size**: font size (in px)
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
	font_size, variant_index = _font_get_best_match(font, font_size, variant_index)

	rect := [4]f32{math.inf_f32(+1), math.inf_f32(+1), math.inf_f32(-1), math.inf_f32(-1)}
	pen: [2]f32

	str := text
	for str != "" {
		ch, w := utf8.decode_rune(str)
		defer str = str[w:]

		glyph, out_index, ok := _font_get_best_glyph(font, ch, variant_index)
		if !ok {
			// Wow we literally didn't find anything. Fine then. Skip!
			continue
		}
		metrics := font.ar.variants[out_index].metrics

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

Text_Frame_Info :: struct {
	fonts:           []^Font,
	pipeline:        Pipeline,
	screen_pipeline: Pipeline,
	image:           Image,
	view:            Image_View,
	set:             Descriptor_Set,
	target:          Image,
	target_view:     Image_View,
	extent:          vk.Extent2D,
	window:          Window,
	frame_index:     int,
}

begin_text :: proc(cmd: Command_Buffer, info: Text_Frame_Info) {
	debug_label_begin(cmd, "Text", {0.0, 0.0, 1.0})

	for font in info.fonts {
		clear(&font.vertices[info.frame_index])
		clear(&font.indices[info.frame_index])
	}

	cmd_image_barrier(
		cmd,
		info.image,
		.UNDEFINED,
		.ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)

	text_clear := vk.ClearValue {
		color = {float32 = {0, 0, 0, 0}},
	}
	text_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = info.view.handle,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = text_clear,
	}
	text_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &text_attachment,
		renderArea = {offset = {0, 0}, extent = info.extent},
	}

	vk.CmdBeginRendering(cmd.handle, &text_info)
	vk.CmdBindPipeline(cmd.handle, .GRAPHICS, info.pipeline.handle)
}

end_text :: proc(cmd: Command_Buffer, info: Text_Frame_Info) {
	vk.CmdEndRendering(cmd.handle)

	cmd_image_barrier(
		cmd,
		info.target,
		.ATTACHMENT_OPTIMAL,
		.ATTACHMENT_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.COLOR_ATTACHMENT_WRITE, .COLOR_ATTACHMENT_READ},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)

	cmd_image_barrier(
		cmd,
		info.image,
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR},
	)

	{
		debug_label_guard(cmd, "Text composite", {1.0, 0.5, 0.1})

		screen_attachment := vk.RenderingAttachmentInfo {
			sType       = .RENDERING_ATTACHMENT_INFO,
			imageView   = info.target_view.handle,
			imageLayout = .ATTACHMENT_OPTIMAL,
			loadOp      = .LOAD,
			storeOp     = .STORE,
		}
		screen_info := vk.RenderingInfo {
			sType = .RENDERING_INFO,
			layerCount = 1,
			colorAttachmentCount = 1,
			pColorAttachments = &screen_attachment,
			renderArea = {offset = {0, 0}, extent = info.extent},
		}

		vk.CmdBeginRendering(cmd.handle, &screen_info)
		vk.CmdBindPipeline(cmd.handle, .GRAPHICS, info.screen_pipeline.handle)
		text_set := info.set
		vk.CmdBindDescriptorSets(
			cmd.handle,
			.GRAPHICS,
			info.screen_pipeline.layout.handle,
			0,
			1,
			&text_set.handle,
			0,
			nil,
		)
		pc := Screen_Push_Constants {
			flip = true,
		}
		vk.CmdPushConstants(
			cmd.handle,
			info.screen_pipeline.layout.handle,
			{.VERTEX},
			0,
			size_of(Screen_Push_Constants),
			&pc,
		)
		vk.CmdDraw(cmd.handle, 3, 1, 0, 0)
		vk.CmdEndRendering(cmd.handle)
	}

	debug_label_end(cmd)
}

render_text :: proc(
	cmd: Command_Buffer,
	font: ^Font,
	info: Text_Frame_Info,
	text: string,
	pos: glm.vec2,
	colour := glm.vec4{1, 1, 1, 1},
	threshold_em: f32 = 0,
	outline_colour := glm.vec4{0, 0, 0, 0},
	outline_em: f32 = 0,
	roundness: f32 = 0,
	font_size: f32 = -1,
	variant_index := -1,
) {
	debug_label_guard(cmd, fmt.tprintf("Draw font '{}'", font.name), {0.1, 0.5, 1.0})

	vertices := &font.vertices[info.frame_index]
	indices := &font.indices[info.frame_index]

	variant_index := variant_index
	font_size := font_size
	font_size, variant_index = _font_get_best_match(font^, font_size, variant_index)

	first_index := cast(u32)len(indices)

	pen := pos

	str := text
	for str != "" {
		ch, w := utf8.decode_rune(str)
		defer str = str[w:]

		glyph, out_index, ok := _font_get_best_glyph(font^, ch, variant_index)
		if !ok {
			// Wow we literally didn't find anything. Fine then. Skip!
			continue
		}
		metrics := font.ar.variants[out_index].metrics

		// TODO: kerning
		scale := font_size / metrics.em_size
		pb := glyph.plane_bounds
		ib := glyph.image_bounds
		img := font.ar.images[glyph.image]
		frame_size := cast(glm.vec2)info.image.size

		x0 := 2 * (pen.x + pb.left * scale) / frame_size.x - 1
		x1 := 2 * (pen.x + pb.right * scale) / frame_size.x - 1
		y0 := 2 * (pen.y + pb.bottom * scale) / frame_size.y - 1
		y1 := 2 * (pen.y + pb.top * scale) / frame_size.y - 1

		u0 := ib.left / cast(f32)img.width
		u1 := ib.right / cast(f32)img.width
		v0 := 1 - ib.bottom / cast(f32)img.height
		v1 := 1 - ib.top / cast(f32)img.height

		base := cast(u16)len(vertices)
		vert := Glyph_Vertex {
			position  = glm.vec2{x0, y0},
			tex_coord = glm.vec2{u0, v0},
		}
		append(vertices, vert)
		vert.position = glm.vec2{x1, y0}
		vert.tex_coord = glm.vec2{u1, v0}
		append(vertices, vert)
		vert.position = glm.vec2{x1, y1}
		vert.tex_coord = glm.vec2{u1, v1}
		append(vertices, vert)
		vert.position = glm.vec2{x0, y1}
		vert.tex_coord = glm.vec2{u0, v1}
		append(vertices, vert)

		append(indices, base + 0, base + 1, base + 2, base + 0, base + 2, base + 3)

		pen.x += scale * glyph.advance.h
		pen.y += scale * glyph.advance.v
	}

	index_count := cast(u32)len(indices) - first_index
	if index_count == 0 {
		return
	}

	metrics := font.ar.variants[variant_index].metrics

	aemrange: glm.vec2
	{
		min := (metrics.distance_range_middle - metrics.distance_range / 2) / metrics.font_size
		max := (metrics.distance_range_middle + metrics.distance_range / 2) / metrics.font_size
		aemrange = {min, max}
	}

	// screen_px_scale: f32
	// {
	// 	variant := font.ar.variants[variant_index]
	// 	lut := font.luts[variant_index]
	// 	glyph := variant.glyphs[lut['A']]
	// 	scale := font_size / variant.metrics.em_size
	// 	input_size_px := glyph.image_bounds.right - glyph.image_bounds.left
	// 	output_size_px := (glyph.plane_bounds.right - glyph.plane_bounds.left) * scale
	// 	screen_px_scale = output_size_px / input_size_px
	// }

	antialias_em: f32 = 1
	{
		w_w, _ := get_window_size(info.window)
		fb_w, _ := window_get_framebuffer_size(info.window)
		cs_x, _ := window_get_content_scale(info.window)
		fb_to_screen := cast(f32)fb_w / (cs_x * cast(f32)w_w)
		aa_fb_px := antialias_em * fb_to_screen
		antialias_em = metrics.font_size / aa_fb_px
	}

	FLAG_MSDF :: 0x01
	FLAG_MTSDF :: 0x02
	flags: u32

	#partial switch font.ar.variants[variant_index].image_type {
	case .Mtsdf:
		flags |= FLAG_MTSDF
		fallthrough
	case .Msdf:
		flags |= FLAG_MSDF
	}

	atlas_set := font.atlas_set
	vk.CmdBindDescriptorSets(
		cmd.handle,
		.GRAPHICS,
		info.pipeline.layout.handle,
		0,
		1,
		&atlas_set.handle,
		0,
		nil,
	)

	frame_vertex_offset := cast(vk.DeviceSize)(info.frame_index *
		FRAME_VERTEX_COUNT *
		size_of(Glyph_Vertex))
	frame_index_offset := cast(vk.DeviceSize)(info.frame_index * FRAME_INDEX_COUNT * size_of(u16))

	vertex_buffers := []vk.Buffer{font.vbo.handle}
	offsets := []vk.DeviceSize{frame_vertex_offset}
	vk.CmdBindVertexBuffers(
		cmd.handle,
		0,
		cast(u32)len(vertex_buffers),
		raw_data(vertex_buffers),
		raw_data(offsets),
	)
	vk.CmdBindIndexBuffer(cmd.handle, font.ebo.handle, frame_index_offset, .UINT16)

	pc := Font_Push_Constants {
		colour         = colour,
		outline_colour = outline_colour,
		aemrange       = aemrange,
		antialias_em   = antialias_em,
		threshold_em   = threshold_em,
		outline_em     = outline_em,
		roundness      = roundness,
		flags          = flags,
	}
	vk.CmdPushConstants(
		cmd.handle,
		info.pipeline.layout.handle,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(Font_Push_Constants),
		&pc,
	)
	vk.CmdDrawIndexed(cmd.handle, index_count, 1, first_index, 0, 0)
}

@(private = "file")
GLYPH_BUFFER_SIZE :: 1 << 16
@(private = "file")
FRAME_VERTEX_COUNT :: GLYPH_BUFFER_SIZE * 4
@(private = "file")
FRAME_INDEX_COUNT :: GLYPH_BUFFER_SIZE * 6

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
}
