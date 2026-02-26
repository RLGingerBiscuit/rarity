package rarity

import vk "vendor:vulkan"

Command_Buffer :: struct {
	handle: vk.CommandBuffer,
}

allocate_command_buffer :: proc(device: Device, pool: Command_Pool) -> (buffer: Command_Buffer) {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool.handle,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}

	CHECK(vk.AllocateCommandBuffers(device.handle, &allocate_info, &buffer.handle))

	return
}

free_command_buffer :: proc(device: Device, pool: Command_Pool, buffer: ^Command_Buffer) {
	vk.FreeCommandBuffers(device.handle, pool.handle, 1, &buffer.handle)
	buffer^ = {}
}

reset_command_buffer :: proc(buffer: Command_Buffer) {
	vk.ResetCommandBuffer(buffer.handle, {})
}

command_buffer_begin :: proc(buffer: Command_Buffer, flags: vk.CommandBufferUsageFlags) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags,
	}

	CHECK(vk.BeginCommandBuffer(buffer.handle, &begin_info))
}

command_buffer_end :: proc(buffer: Command_Buffer) {
	CHECK(vk.EndCommandBuffer(buffer.handle))
}

record_commands :: proc(
	cmd: Command_Buffer,
	pass: Render_Pass,
	swapchain: Swapchain,
	index: u32,
	pipeline: Pipeline,
	vertex_buffer: Vertex_Buffer,
) {
	command_buffer_begin(cmd, {})

	clear_colour := vk.ClearValue {
		color = {float32 = {0, 0, 0, 1}},
	}

	pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = pass.handle,
		framebuffer = swapchain.framebuffers[index].handle,
		renderArea = {offset = {0, 0}, extent = swapchain.extent},
		clearValueCount = 1,
		pClearValues = &clear_colour,
	}

	vk.CmdBeginRenderPass(cmd.handle, &pass_info, .INLINE)

	vk.CmdBindPipeline(cmd.handle, .GRAPHICS, pipeline.handle)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)swapchain.extent.width,
		height   = cast(f32)swapchain.extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(cmd.handle, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = swapchain.extent,
	}
	vk.CmdSetScissor(cmd.handle, 0, 1, &scissor)

	vertex_buffers := []vk.Buffer{vertex_buffer.handle}
	offsets := []vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(
		cmd.handle,
		0,
		cast(u32)len(vertex_buffers),
		raw_data(vertex_buffers),
		raw_data(offsets),
	)

	vk.CmdDraw(cmd.handle, cast(u32)len(VERTICES), 1, 0, 0)

	vk.CmdEndRenderPass(cmd.handle)

	command_buffer_end(cmd)
}
