package rarity

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import vk "vendor:vulkan"

VERT_PATH :: "shaders/basic.vert.spv"
FRAG_PATH :: "shaders/basic.frag.spv"

Pipeline :: struct {
	handle:                vk.Pipeline,
	layout:                Pipeline_Layout,
	descriptor_set_layout: Descriptor_Set_Layout,
}

Pipeline_Layout :: struct {
	handle: vk.PipelineLayout,
}

create_pipeline :: proc(device: Device, swapchain: Swapchain) -> (pipeline: Pipeline) {
	vert_data, frag_data: []byte
	err: os.Error
	vert_data, err = os.read_entire_file(VERT_PATH, context.temp_allocator)
	if err != nil {
		log.fatalf("Could not read from '{}'", VERT_PATH)
		os.exit(1)
	}
	frag_data, err = os.read_entire_file(FRAG_PATH, context.temp_allocator)
	if err != nil {
		log.fatalf("Could not read from '{}'", VERT_PATH)
		os.exit(1)
	}

	vert_module := create_shader_module(device, vert_data)
	defer destroy_shader_module(device, &vert_module)
	set_debug_name(device, vert_module, fmt.tprintf("shader:{}", filepath.stem(VERT_PATH)))

	vert_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vert_module.handle,
		pName  = "main",
	}
	vert_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &BINDING_DESCRIPTION,
		vertexAttributeDescriptionCount = cast(u32)len(ATTRIBUTE_DESCRIPTIONS),
		pVertexAttributeDescriptions    = raw_data(ATTRIBUTE_DESCRIPTIONS),
	}

	frag_module := create_shader_module(device, frag_data)
	defer destroy_shader_module(device, &frag_module)
	set_debug_name(device, frag_module, fmt.tprintf("shader:{}", filepath.stem(FRAG_PATH)))

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
		topology               = .TRIANGLE_LIST,
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
		cullMode                = {.BACK},
		frontFace               = .COUNTER_CLOCKWISE,
		lineWidth               = 1,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = {._1},
	}

	colour_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = {.R, .G, .B, .A},
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp        = .ADD,
	}

	colour_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &colour_blend_attachment,
	}

	pipeline.descriptor_set_layout = create_descriptor_set_layout(device)

	layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &pipeline.descriptor_set_layout.handle,
	}
	CHECK(vk.CreatePipelineLayout(device.handle, &layout_info, nil, &pipeline.layout.handle))

	swapchain := swapchain
	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &swapchain.format.format,
	}

	create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_info,
		stageCount          = 2,
		pStages             = raw_data(stages),
		pVertexInputState   = &vert_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasteriser,
		pMultisampleState   = &multisampling,
		pDepthStencilState  = nil,
		pColorBlendState    = &colour_blending,
		pDynamicState       = &dynamic_state,
		layout              = pipeline.layout.handle,
	}

	CHECK(vk.CreateGraphicsPipelines(device.handle, 0, 1, &create_info, nil, &pipeline.handle))

	return
}

destroy_pipeline :: proc(device: Device, pipeline: ^Pipeline) {
	destroy_descriptor_set_layout(device, &pipeline.descriptor_set_layout)
	vk.DestroyPipelineLayout(device.handle, pipeline.layout.handle, nil)
	vk.DestroyPipeline(device.handle, pipeline.handle, nil)
	pipeline^ = {}
}
