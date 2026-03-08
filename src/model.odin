package rarity

import "core:log"
import glm "core:math/linalg/glsl"
import "core:path/filepath"
import "core:strings"
import gltf "vendor:cgltf"

load_model :: proc(path: string) -> (vertices: []Vertex, indices: []u32, texture_path: string) {
	OPTIONS :: gltf.options{}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	model_data, result := gltf.parse_file(OPTIONS, cpath)
	log.ensuref(result == .success, "Could not load '{}': {}", path, result)
	result = gltf.validate(model_data)
	log.ensuref(result == .success, "'{}' did not pass validation: {}", path, result)
	defer gltf.free(model_data)
	result = gltf.load_buffers(OPTIONS, model_data, cpath)
	log.ensuref(result == .success, "Could not load '{}': {}", path, result)

	log.ensure(len(model_data.textures) == 1, "Only one model texture is supported")
	log.ensure(len(model_data.meshes) == 1, "Only one model mesh is supported")
	// TODO: use model sampler info?

	texture_path, _ = filepath.join(
		{
			filepath.dir(path, context.temp_allocator),
			cast(string)model_data.textures[0].image_.uri,
		},
		context.allocator,
	)

	mesh := model_data.meshes[0]
	log.ensure(len(mesh.primitives) == 1, "Only ony model primitive is supported")
	prim := mesh.primitives[0]
	log.ensure(prim.type == .triangles, "Only triangle model primitives are supported")

	position_attrib_index := -1
	tex_coord_attrib_index := -1
	for attrib, i in prim.attributes {
		#partial switch attrib.type {
		case .position:
			position_attrib_index = i
		case .texcoord:
			tex_coord_attrib_index = i
		}
	}
	log.ensure(position_attrib_index >= 0 && tex_coord_attrib_index >= 0)

	position_attrib := prim.attributes[position_attrib_index]
	tex_coord_attrib := prim.attributes[tex_coord_attrib_index]
	log.ensure(position_attrib.data.count == tex_coord_attrib.data.count)

	indices = make([]u32, prim.indices.count)

	log.ensure(
		gltf.accessor_unpack_indices(
			prim.indices,
			raw_data(indices),
			size_of(u32),
			prim.indices.count,
		) ==
		len(indices),
	)

	vertices = make([]Vertex, position_attrib.data.count)

	positions := make([]glm.vec3, position_attrib.data.count, context.temp_allocator)
	tex_coords := make([]glm.vec2, tex_coord_attrib.data.count, context.temp_allocator)

	log.ensure(
		gltf.accessor_unpack_floats(
			position_attrib.data,
			cast([^]f32)raw_data(positions),
			len(positions) * len(glm.vec3),
		) ==
		len(positions) * len(glm.vec3),
	)

	log.ensure(
		gltf.accessor_unpack_floats(
			tex_coord_attrib.data,
			cast([^]f32)raw_data(tex_coords),
			len(tex_coords) * len(glm.vec2),
		) ==
		len(tex_coords) * len(glm.vec2),
	)

	for i in 0 ..< len(vertices) {
		vertices[i] = {
			position  = positions[i],
			colour    = {1, 1, 1, 1},
			tex_coord = tex_coords[i],
		}
	}

	return
}
