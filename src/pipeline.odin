package rarity

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import vk "vendor:vulkan"

VERT_PATH :: "shaders/model.vert.spv"
FRAG_PATH :: "shaders/model.frag.spv"
EDGE_DETECT_VERT_PATH :: "shaders/edge_detect.vert.spv"
EDGE_DETECT_FRAG_PATH :: "shaders/edge_detect.frag.spv"
EDGE_OVERLAY_VERT_PATH :: "shaders/edge_detect_overlay.vert.spv"
EDGE_OVERLAY_FRAG_PATH :: "shaders/edge_detect_overlay.frag.spv"

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: Pipeline_Layout,
}

Pipeline_Layout :: struct {
	handle: vk.PipelineLayout,
}

Pipeline_Vertex_Input :: struct {
	bindings:   []vk.VertexInputBindingDescription,
	attributes: []vk.VertexInputAttributeDescription,
}

Pipeline_Push_Constant_Range :: struct {
	stages: vk.ShaderStageFlags,
	offset: u32,
	size:   u32,
}

Pipeline_Blend_State :: struct {
	enabled:                 bool,
	src_colour, dst_colour:  vk.BlendFactor,
	colour_op:               vk.BlendOp,
	src_alpha, dst_alpha:    vk.BlendFactor,
	alpha_op:                vk.BlendOp,
	colour_write_mask:       vk.ColorComponentFlags,
}

Pipeline_Create_Info :: struct {
	vertex_shader_path:   string,
	fragment_shader_path: string,
	vertex_input:         Pipeline_Vertex_Input,
	descriptor_layouts:   []Descriptor_Set_Layout,
	push_constants:       []Pipeline_Push_Constant_Range,
	colour_formats:       []vk.Format,
	depth_format:         vk.Format,
	use_depth:            bool,
	depth_test:           bool,
	depth_write:          bool,
	depth_compare:        vk.CompareOp,
	blend:                Pipeline_Blend_State,
	cull_mode:            vk.CullModeFlags,
	front_face:           vk.FrontFace,
	topology:             vk.PrimitiveTopology,
}

create_pipeline :: proc(device: Device, info: Pipeline_Create_Info) -> (pipeline: Pipeline) {
	vert_data, frag_data: []byte
	err: os.Error
	vert_data, err = os.read_entire_file(info.vertex_shader_path, context.temp_allocator)
	if err != nil {
		log.fatalf("Could not read from '{}'", info.vertex_shader_path)
		os.exit(1)
	}
	frag_data, err = os.read_entire_file(info.fragment_shader_path, context.temp_allocator)
	if err != nil {
		log.fatalf("Could not read from '{}'", info.fragment_shader_path)
		os.exit(1)
	}

	vert_module := create_shader_module(device, vert_data)
	defer destroy_shader_module(device, &vert_module)
	set_debug_name(device, vert_module, fmt.tprintf("shader:{}", filepath.stem(info.vertex_shader_path)))

	vert_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vert_module.handle,
		pName  = "main",
	}
	vert_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = cast(u32)len(info.vertex_input.bindings),
		pVertexBindingDescriptions      = raw_data(info.vertex_input.bindings),
		vertexAttributeDescriptionCount = cast(u32)len(info.vertex_input.attributes),
		pVertexAttributeDescriptions    = raw_data(info.vertex_input.attributes),
	}

	frag_module := create_shader_module(device, frag_data)
	defer destroy_shader_module(device, &frag_module)
	set_debug_name(device, frag_module, fmt.tprintf("shader:{}", filepath.stem(info.fragment_shader_path)))

	frag_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = frag_module.handle,
		pName  = "main",
	}

	stages := []vk.PipelineShaderStageCreateInfo{vert_info, frag_info}

	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		pDynamicStates    = raw_data(dynamic_states),
		dynamicStateCount = cast(u32)len(dynamic_states),
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = info.topology,
		primitiveRestartEnable = false,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasteriser := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		depthBiasEnable         = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = info.cull_mode,
		frontFace               = info.front_face,
		lineWidth               = 1,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	colour_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = info.blend.colour_write_mask,
		blendEnable         = b32(info.blend.enabled),
		srcColorBlendFactor = info.blend.src_colour,
		dstColorBlendFactor = info.blend.dst_colour,
		colorBlendOp        = info.blend.colour_op,
		srcAlphaBlendFactor = info.blend.src_alpha,
		dstAlphaBlendFactor = info.blend.dst_alpha,
		alphaBlendOp        = info.blend.alpha_op,
	}

	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable       = b32(info.depth_test),
		depthWriteEnable      = b32(info.depth_write),
		depthCompareOp        = info.depth_compare,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
	}

	colour_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &colour_blend_attachment,
	}

	push_constants := make([]vk.PushConstantRange, len(info.push_constants), context.temp_allocator)
	for range_info, i in info.push_constants {
		push_constants[i] = {
			stageFlags = range_info.stages,
			offset     = range_info.offset,
			size       = range_info.size,
		}
	}

	set_layouts := make([]vk.DescriptorSetLayout, len(info.descriptor_layouts), context.temp_allocator)
	for layout, i in info.descriptor_layouts {
		set_layouts[i] = layout.handle
	}

	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = cast(u32)len(set_layouts),
		pSetLayouts            = raw_data(set_layouts),
		pPushConstantRanges    = raw_data(push_constants),
		pushConstantRangeCount = cast(u32)len(push_constants),
	}
	CHECK(vk.CreatePipelineLayout(device.handle, &layout_info, nil, &pipeline.layout.handle))

	depth_attachment_format: vk.Format = .UNDEFINED
	if info.use_depth {
		depth_attachment_format = info.depth_format
	}

	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = cast(u32)len(info.colour_formats),
		pColorAttachmentFormats = raw_data(info.colour_formats),
		depthAttachmentFormat   = depth_attachment_format,
	}

	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_info,
		stageCount          = cast(u32)len(stages),
		pStages             = raw_data(stages),
		pVertexInputState   = &vert_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasteriser,
		pMultisampleState   = &multisampling,
		pDepthStencilState  = &depth_stencil,
		pColorBlendState    = &colour_blending,
		pDynamicState       = &dynamic_state,
		layout              = pipeline.layout.handle,
	}

	CHECK(vk.CreateGraphicsPipelines(device.handle, 0, 1, &create_info, nil, &pipeline.handle))

	return
}

default_blend_state :: proc(enabled: bool) -> Pipeline_Blend_State {
	return {
		enabled           = enabled,
		src_colour        = .SRC_ALPHA,
		dst_colour        = .ONE_MINUS_SRC_ALPHA,
		colour_op         = .ADD,
		src_alpha         = .ONE,
		dst_alpha         = .ZERO,
		alpha_op          = .ADD,
		colour_write_mask = {.R, .G, .B, .A},
	}
}

create_model_pipeline :: proc(
	device: Device,
	swapchain: Swapchain,
	descriptor_layout: Descriptor_Set_Layout,
) -> Pipeline {
	bindings := []vk.VertexInputBindingDescription{BINDING_DESCRIPTION}
	layouts := []Descriptor_Set_Layout{descriptor_layout}
	push_constants := []Pipeline_Push_Constant_Range {
		{stages = {.VERTEX}, offset = 0, size = cast(u32)size_of(Model_Push_Constants)},
	}
	colour_formats := []vk.Format{swapchain.format.format}
	return create_pipeline(
		device,
		{
			vertex_shader_path   = VERT_PATH,
			fragment_shader_path = FRAG_PATH,
			vertex_input         = {bindings = bindings, attributes = ATTRIBUTE_DESCRIPTIONS},
			descriptor_layouts   = layouts,
			push_constants       = push_constants,
			colour_formats       = colour_formats,
			depth_format         = swapchain.depth_format,
			use_depth            = true,
			depth_test           = true,
			depth_write          = true,
			depth_compare        = .LESS,
			blend                = default_blend_state(true),
			cull_mode            = {.BACK},
			front_face           = .COUNTER_CLOCKWISE,
			topology             = .TRIANGLE_LIST,
		},
	)
}

create_edge_detect_pipeline :: proc(
	device: Device,
	swapchain: Swapchain,
	descriptor_layout: Descriptor_Set_Layout,
) -> Pipeline {
	layouts := []Descriptor_Set_Layout{descriptor_layout}
	push_constants := []Pipeline_Push_Constant_Range {
		{stages = {.FRAGMENT}, offset = 0, size = cast(u32)size_of(Edge_Detect_Push_Constants)},
	}
	colour_formats := []vk.Format{swapchain.edge_format}
	return create_pipeline(
		device,
		{
			vertex_shader_path   = EDGE_DETECT_VERT_PATH,
			fragment_shader_path = EDGE_DETECT_FRAG_PATH,
			vertex_input         = {},
			descriptor_layouts   = layouts,
			push_constants       = push_constants,
			colour_formats       = colour_formats,
			use_depth            = false,
			blend                = default_blend_state(false),
			cull_mode            = {},
			front_face           = .COUNTER_CLOCKWISE,
			topology             = .TRIANGLE_LIST,
		},
	)
}

create_edge_overlay_pipeline :: proc(
	device: Device,
	swapchain: Swapchain,
	descriptor_layout: Descriptor_Set_Layout,
) -> Pipeline {
	layouts := []Descriptor_Set_Layout{descriptor_layout}
	push_constants := []Pipeline_Push_Constant_Range {
		{stages = {.VERTEX}, offset = 0, size = cast(u32)size_of(Edge_Overlay_Push_Constants)},
	}
	colour_formats := []vk.Format{swapchain.format.format}
	return create_pipeline(
		device,
		{
			vertex_shader_path   = EDGE_OVERLAY_VERT_PATH,
			fragment_shader_path = EDGE_OVERLAY_FRAG_PATH,
			vertex_input         = {},
			descriptor_layouts   = layouts,
			push_constants       = push_constants,
			colour_formats       = colour_formats,
			use_depth            = false,
			blend                = default_blend_state(true),
			cull_mode            = {},
			front_face           = .COUNTER_CLOCKWISE,
			topology             = .TRIANGLE_LIST,
		},
	)
}

destroy_pipeline :: proc(device: Device, pipeline: ^Pipeline) {
	vk.DestroyPipelineLayout(device.handle, pipeline.layout.handle, nil)
	vk.DestroyPipeline(device.handle, pipeline.handle, nil)
	pipeline^ = {}
}
