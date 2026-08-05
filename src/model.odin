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
	vbo:                     Vertex_Buffer(Model_Vertex),
	ebo:                     Index_Buffer,
	material:                Mesh_Material,
	vert_count, index_count: uint,
	index_type:              vk.IndexType,
	set:                     Descriptor_Set,
}

Mesh :: struct {
	name:       string,
	primitives: []Mesh_Primitive,
	mat:        glm.mat4,
}

Model :: struct {
	name:   string,
	meshes: []Mesh,
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
					min := gltf_filter_type_to_vk(tex.sampler.min_filter)
					mag := gltf_filter_type_to_vk(tex.sampler.mag_filter)
					mip: vk.SamplerMipmapMode
					switch min {
					case .NEAREST:
						mip = .NEAREST
					case .LINEAR:
						mip = .LINEAR
					case .CUBIC_IMG:
						unreachable()
					}
					wrap_s := gltf_wrap_mode_to_vk(tex.sampler.wrap_s)
					wrap_t := gltf_wrap_mode_to_vk(tex.sampler.wrap_t)

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

			upload_indices :: proc(
				$T: typeid,
				prim: gltf.primitive,
				device: Device,
				physical_device: Physical_Device,
				immediate_pool: Command_Pool,
				graphics_pool: Command_Pool,
				immediate_fence: Fence,
				transfer_queue: Queue,
				graphics_queue: Queue,
			) -> (
				Index_Buffer,
				uint,
			) {
				indices := make([]T, prim.indices.count, context.temp_allocator)
				log.ensure(
					uint(len(indices)) ==
					gltf.accessor_unpack_indices(
						prim.indices,
						raw_data(indices),
						size_of(T),
						len(indices),
					),
				)
				return create_index_buffer(
						device,
						physical_device,
						indices,
						immediate_pool,
						graphics_pool,
						immediate_fence,
						transfer_queue,
						graphics_queue,
					),
					cast(uint)len(indices)
			}

			switch node_prim.indices.component_type {
			case .invalid, .r_8, .r_16, .r_32f:
				unreachable()
			case .r_8u:
				primitive.index_type = .UINT8
				primitive.ebo, primitive.index_count = upload_indices(
					u8,
					node_prim,
					device,
					physical_device,
					immediate_pool,
					graphics_pool,
					immediate_fence,
					transfer_queue,
					graphics_queue,
				)
			case .r_16u:
				primitive.index_type = .UINT16
				primitive.ebo, primitive.index_count = upload_indices(
					u16,
					node_prim,
					device,
					physical_device,
					immediate_pool,
					graphics_pool,
					immediate_fence,
					transfer_queue,
					graphics_queue,
				)
			case .r_32u:
				primitive.index_type = .UINT32
				primitive.ebo, primitive.index_count = upload_indices(
					u32,
					node_prim,
					device,
					physical_device,
					immediate_pool,
					graphics_pool,
					immediate_fence,
					transfer_queue,
					graphics_queue,
				)
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

			vertices := make([]Model_Vertex, pos_attr.data.count, context.temp_allocator)
			for i in 0 ..< len(vertices) {
				vertices[i] = {
					position  = positions[i],
					colour    = colours[i] if len(colours) > 0 else {1, 1, 1, 1},
					tex_coord = tex_coords[i] if len(tex_coords) > 0 else {0, 0},
				}
			}

			primitive.vert_count = uint(len(vertices))
			primitive.vbo = create_vertex_buffer(
				device,
				physical_device,
				vertices,
				immediate_pool,
				graphics_pool,
				immediate_fence,
				transfer_queue,
				graphics_queue,
			)

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

	return
}

destroy_model :: proc(device: Device, model: ^Model) {
	for &mesh in model.meshes {
		for &prim in mesh.primitives {
			destroy_vertex_buffer(device, &prim.vbo)
			destroy_index_buffer(device, &prim.ebo)
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
			// TODO: All verts/indices for a given mesh in contiguous buffers?
			vertex_buffers := []vk.Buffer{prim.vbo.handle}
			offsets := []vk.DeviceSize{0}
			vk.CmdBindVertexBuffers(
				cmd.handle,
				0,
				cast(u32)len(vertex_buffers),
				raw_data(vertex_buffers),
				raw_data(offsets),
			)

			vk.CmdBindIndexBuffer(cmd.handle, prim.ebo.handle, 0, prim.index_type)

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
			vk.CmdDrawIndexed(cmd.handle, cast(u32)prim.index_count, 1, 0, 0, 0)
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
