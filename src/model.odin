package rarity

import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:os"
import "core:path/filepath"
import "core:strings"
import gltf "vendor:cgltf"
import vk "vendor:vulkan"

// Model originally from https://www.deviantart.com/mythicspeed/art/DL-Equestria-Girls-Plus-1261841272
MODEL_PATH :: "assets/models/EqG_RR_v29.glb"

MODEL_DEFAULT_MIN_FILTER :: vk.Filter.LINEAR
MODEL_DEFAULT_MAG_FILTER :: vk.Filter.LINEAR
MODEL_DEFAULT_WRAP_S :: vk.SamplerAddressMode.REPEAT
MODEL_DEFAULT_WRAP_T :: vk.SamplerAddressMode.REPEAT

Model_Vertex :: struct #packed {
	position:  glm.vec3,
	colour:    glm.vec4,
	tex_coord: glm.vec2,
}

Mesh_Texture :: struct {
	image:   Image,
	view:    Image_View,
	sampler: Sampler,
}

Mesh_Material :: struct {
	texture: Mesh_Texture,
}

Mesh_Primitive :: struct {
	material:                 Mesh_Material,
	first_vertex, vert_count: u32,
	first_index, index_count: u32,
	set:                      Descriptor_Set,
}

Mesh :: struct {
	name:       string,
	primitives: []Mesh_Primitive,
	mat:        glm.mat4,
}

Model :: struct {
	name:   string,
	meshes: []Mesh,
	vbo:    Vertex_Buffer(Model_Vertex),
	ebo:    Index_Buffer,
}

load_model :: proc(
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
) -> (
	model: Model,
) {
	OPTIONS :: gltf.options{}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	model_data, result := gltf.parse_file(OPTIONS, cpath)
	log.ensuref(result == .success, "Could not load '{}': {}", path, result)
	result = gltf.validate(model_data)
	log.ensuref(result == .success, "'{}' did not pass validation: {}", path, result)
	defer gltf.free(model_data)
	result = gltf.load_buffers(OPTIONS, model_data, cpath)
	log.ensuref(result == .success, "Could not load '{}': {}", path, result)

	log.ensuref(model_data.scene != nil, "No scene?")

	meshes := make([dynamic]Mesh)
	vertices := make([dynamic]Model_Vertex, context.temp_allocator)
	indices := make([dynamic]u32, context.temp_allocator)

	nodes := make([dynamic]^gltf.node, len(model_data.scene.nodes), context.temp_allocator)
	copy(nodes[:], model_data.scene.nodes)

	for len(nodes) > 0 {
		node := pop(&nodes)
		append(&nodes, ..node.children)
		if node.mesh == nil {
			continue
		}

		mesh: Mesh
		mesh.name = strings.clone_from_cstring(node.mesh.name)

		gltf.node_transform_world(node, &mesh.mat[0, 0])

		primitives := make([dynamic]Mesh_Primitive, 0, len(node.mesh.primitives))

		for node_prim in node.mesh.primitives {
			log.ensure(
				node_prim.type == .triangles,
				"Only triangle model primitives are supported",
			)

			pos_attr_idx := -1
			col_attr_idx := -1
			uv_attr_idx := -1
			for attrib, i in node_prim.attributes {
				#partial switch attrib.type {
				case .position:
					pos_attr_idx = i
				case .color:
					col_attr_idx = i
				case .texcoord:
					uv_attr_idx = i
				}
			}
			log.ensure(pos_attr_idx >= 0, "Primitive does not have position attribute")

			material := node_prim.material

			image: Image
			sampler: Sampler
			if material == nil || !material.has_pbr_metallic_roughness {
				image = upload_image(
					{0xff},
					1,
					1,
					device,
					physical_device,
					immediate_pool,
					graphics_pool,
					immediate_fence,
					transfer_queue,
					graphics_queue,
					.R8_UNORM,
				)
				sampler = create_sampler(
					device,
					physical_device,
					.NEAREST,
					.NEAREST,
					.NEAREST,
					.REPEAT,
					.REPEAT,
				)
			} else {
				pbr := material.pbr_metallic_roughness

				tex_data: []byte
				tex := pbr.base_color_texture.texture
				if tex == nil {
					pixel := cast([4]byte)(pbr.base_color_factor * 255)
					image = upload_image(
						pixel[:],
						1,
						1,
						device,
						physical_device,
						immediate_pool,
						graphics_pool,
						immediate_fence,
						transfer_queue,
						graphics_queue,
						.R8G8B8A8_SRGB,
					)
					sampler = create_sampler(
						device,
						physical_device,
						.NEAREST,
						.NEAREST,
						.NEAREST,
						.REPEAT,
						.REPEAT,
					)
				} else {
					if tex.image_.buffer_view != nil {
						raw := gltf.buffer_view_data(tex.image_.buffer_view)
						tex_data = raw[:tex.image_.buffer_view.size]
					} else if tex.image_.uri != "" {
						tex_path, alloc_err := filepath.join(
							{filepath.dir(path), cast(string)tex.image_.uri},
							context.temp_allocator,
						)
						log.ensure(alloc_err == nil)
						log.ensuref(os.exists(tex_path), "Texture '{}' doesn't exist", tex_path)
						read_err: os.Error
						tex_data, read_err = os.read_entire_file(tex_path, context.temp_allocator)
						log.ensuref(
							read_err == nil,
							"Could not read from '{}': {}",
							tex_path,
							read_err,
						)
					} else {
						log.panic()
					}
					image = load_image(
						tex_data,
						device,
						physical_device,
						immediate_pool,
						graphics_pool,
						immediate_fence,
						transfer_queue,
						graphics_queue,
						.R8G8B8A8_SRGB,
					)
					min := MODEL_DEFAULT_MIN_FILTER
					mag := MODEL_DEFAULT_MAG_FILTER
					wrap_s := MODEL_DEFAULT_WRAP_S
					wrap_t := MODEL_DEFAULT_WRAP_T
					mip: vk.SamplerMipmapMode
					switch min {
					case .NEAREST:
						mip = .NEAREST
					case .LINEAR:
						mip = .LINEAR
					case .CUBIC_IMG:
						unreachable()
					}

					if sampler := tex.sampler; sampler != nil {
						min = gltf_filter_type_to_vk(tex.sampler.min_filter)
						mag = gltf_filter_type_to_vk(tex.sampler.mag_filter)
						wrap_s = gltf_wrap_mode_to_vk(tex.sampler.wrap_s)
						wrap_t = gltf_wrap_mode_to_vk(tex.sampler.wrap_t)
					}

					sampler = create_sampler(
						device,
						physical_device,
						min,
						mag,
						mip,
						wrap_s,
						wrap_t,
					)
				}

			}

			view := image_to_view(device, image, {.COLOR})

			primitive: Mesh_Primitive
			primitive.material.texture = Mesh_Texture {
				image   = image,
				view    = view,
				sampler = sampler,
			}

			if prim_indices := node_prim.indices; prim_indices != nil {
				first := len(indices)
				resize(&indices, first + cast(int)prim_indices.count)
				log.ensure(
					gltf.accessor_unpack_indices(
						prim_indices,
						&indices[first],
						size_of(u32),
						prim_indices.count,
					) ==
					prim_indices.count,
				)
				primitive.first_index = cast(u32)first
				primitive.index_count = cast(u32)prim_indices.count
			}

			pos_attr := node_prim.attributes[pos_attr_idx]
			positions := make([]glm.vec3, pos_attr.data.count, context.temp_allocator)
			log.ensure(
				gltf.accessor_unpack_floats(
					pos_attr.data,
					cast([^]f32)raw_data(positions),
					len(positions) * len(glm.vec3),
				) ==
				len(positions) * len(glm.vec3),
			)

			colours: []glm.vec4
			if col_attr_idx >= 0 {
				col_attr := node_prim.attributes[col_attr_idx]
				colours = make([]glm.vec4, col_attr.data.count, context.temp_allocator)
				log.ensure(
					gltf.accessor_unpack_floats(
						col_attr.data,
						cast([^]f32)raw_data(colours),
						len(colours) * len(glm.vec4),
					) ==
					len(colours) * len(glm.vec4),
				)
			}

			tex_coords: []glm.vec2
			if uv_attr_idx >= 0 {
				uv_attr := node_prim.attributes[uv_attr_idx]
				tex_coords = make([]glm.vec2, uv_attr.data.count, context.temp_allocator)
				log.ensure(
					gltf.accessor_unpack_floats(
						uv_attr.data,
						cast([^]f32)raw_data(tex_coords),
						len(tex_coords) * len(glm.vec2),
					) ==
					len(tex_coords) * len(glm.vec2),
				)
			}

			primitive.first_vertex = cast(u32)len(vertices)
			primitive.vert_count = cast(u32)len(positions)
			for position, i in positions {
				append(
					&vertices,
					Model_Vertex {
						position = position,
						colour = colours[i] if len(colours) > 0 else {1, 1, 1, 1},
						tex_coord = tex_coords[i] if len(tex_coords) > 0 else {0, 0},
					},
				)
			}

			sets := allocate_descriptor_sets(device, descriptor_pool, descriptor_layout, 1)
			defer delete(sets) // Delete the slice since we only need one
			populate_descriptor_sets(
				device,
				sets,
				primitive.material.texture.view,
				primitive.material.texture.sampler,
			)
			primitive.set = sets[0]

			append(&primitives, primitive)
		}

		mesh.primitives = primitives[:]
		append(&meshes, mesh)
	}

	model.name = strings.clone(filepath.base(path))
	model.meshes = meshes[:]

	model.vbo = create_vertex_buffer(
		device,
		physical_device,
		vertices[:],
		immediate_pool,
		graphics_pool,
		immediate_fence,
		transfer_queue,
		graphics_queue,
	)
	set_debug_name(device, model.vbo.buffer, fmt.tprintf("model:{}/vbo", model.name))

	if len(indices) > 0 {
		model.ebo = create_index_buffer(
			device,
			physical_device,
			indices[:],
			immediate_pool,
			graphics_pool,
			immediate_fence,
			transfer_queue,
			graphics_queue,
		)
		set_debug_name(device, model.ebo.buffer, fmt.tprintf("model:{}/ebo", model.name))
	}

	return
}

destroy_model :: proc(device: Device, model: ^Model) {
	destroy_vertex_buffer(device, &model.vbo)
	destroy_index_buffer(device, &model.ebo)

	for &mesh in model.meshes {
		for &prim in mesh.primitives {
			destroy_sampler(device, &prim.material.texture.sampler)
			destroy_image_view(device, &prim.material.texture.view)
			destroy_image(device, &prim.material.texture.image)
		}
		delete(mesh.primitives)
		delete(mesh.name)
	}
	delete(model.meshes)
	delete(model.name)
	model^ = {}
}

recreate_model_descriptor_sets :: proc(
	device: Device,
	model: ^Model,
	swapchain: Swapchain,
	descriptor_pool: Descriptor_Pool,
	descriptor_layout: Descriptor_Set_Layout,
) {
	for &mesh in model.meshes {
		for &prim in mesh.primitives {
			sets := allocate_descriptor_sets(device, descriptor_pool, descriptor_layout, 1)
			defer delete(sets) // Delete the slice since we only need one
			populate_descriptor_sets(
				device,
				sets,
				prim.material.texture.view,
				prim.material.texture.sampler,
			)
			prim.set = sets[0]
		}}
}

record_model :: proc(
	cmd: Command_Buffer,
	pipeline: Pipeline,
	model: Model,
	pc: Model_Push_Constants,
) {
	default_pc := pc
	pc := pc

	vertex_buffer := model.vbo.handle
	vertex_offset := vk.DeviceSize(0)
	vk.CmdBindVertexBuffers(cmd.handle, 0, 1, &vertex_buffer, &vertex_offset)
	if model.ebo.handle != 0 {
		vk.CmdBindIndexBuffer(cmd.handle, model.ebo.handle, 0, .UINT32)
	}

	for mesh in model.meshes {
		debug_label_guard(
			cmd,
			fmt.tprintf("Render mesh '{}::{}'", model.name, mesh.name),
			{0.5, 0.1, 1.0},
		)
		pc.mvp = default_pc.mvp * mesh.mat

		vk.CmdPushConstants(
			cmd.handle,
			pipeline.layout.handle,
			{.VERTEX},
			0,
			size_of(Model_Push_Constants),
			&pc,
		)

		for prim in mesh.primitives {
			set := prim.set
			vk.CmdBindDescriptorSets(
				cmd.handle,
				.GRAPHICS,
				pipeline.layout.handle,
				0,
				1,
				&set.handle,
				0,
				nil,
			)
			if prim.index_count == 0 {
				vk.CmdDraw(cmd.handle, prim.vert_count, 1, prim.first_vertex, 0)
			} else {
				vk.CmdDrawIndexed(
					cmd.handle,
					prim.index_count,
					1,
					prim.first_index,
					cast(i32)prim.first_vertex,
					0,
				)
			}
		}

	}
}

gltf_filter_type_to_vk :: proc(type: gltf.filter_type) -> vk.Filter {
	switch type {
	case .undefined, .linear, .linear_mipmap_linear, .linear_mipmap_nearest:
		return .LINEAR
	case .nearest, .nearest_mipmap_nearest, .nearest_mipmap_linear:
		return .NEAREST
	}
	unreachable()
}

gltf_wrap_mode_to_vk :: proc(mode: gltf.wrap_mode) -> vk.SamplerAddressMode {
	switch mode {
	case .repeat:
		return .REPEAT
	case .clamp_to_edge:
		return .CLAMP_TO_EDGE
	case .mirrored_repeat:
		return .MIRRORED_REPEAT
	}
	unreachable()
}

@(rodata)
MODEL_BINDING_DESCRIPTION := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Model_Vertex),
	inputRate = .VERTEX,
}

@(rodata)
MODEL_ATTRIBUTE_DESCRIPTIONS := []vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Model_Vertex, position),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32A32_SFLOAT,
		offset = cast(u32)offset_of(Model_Vertex, colour),
	},
	{
		binding = 0,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Model_Vertex, tex_coord),
	},
}
