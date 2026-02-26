package rarity

import vk "vendor:vulkan"

Queue :: struct {
	handle: vk.Queue,
}

get_queue :: proc(device: Device, family, index: u32) -> (queue: Queue) {
	vk.GetDeviceQueue(device.handle, family, index, &queue.handle)
	return
}

queue_submit :: proc(
	queue: Queue,
	buffer: ^Command_Buffer,
	wait_sema, signal_sema: Semaphore,
	fence: Fence,
) {
	wait_semas := []vk.Semaphore{wait_sema.handle}
	wait_stages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}

	signal_semas := []vk.Semaphore{signal_sema.handle}

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = cast(u32)len(wait_semas),
		pWaitSemaphores      = raw_data(wait_semas),
		pWaitDstStageMask    = &wait_stages,
		commandBufferCount   = 1,
		pCommandBuffers      = &buffer.handle,
		signalSemaphoreCount = cast(u32)len(signal_semas),
		pSignalSemaphores    = raw_data(signal_semas),
	}

	CHECK(vk.QueueSubmit(queue.handle, 1, &submit_info, fence.handle))
}

queue_present :: proc(
	queue: Queue,
	swapchain: Swapchain,
	index: u32,
	wait_sema: Semaphore,
) -> vk.Result {
	index := index
	wait_semas := []vk.Semaphore{wait_sema.handle}

	swapchains := []vk.SwapchainKHR{swapchain.handle}

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = cast(u32)len(wait_semas),
		pWaitSemaphores    = raw_data(wait_semas),
		swapchainCount     = cast(u32)len(swapchains),
		pSwapchains        = raw_data(swapchains),
		pImageIndices      = &index,
	}

	return vk.QueuePresentKHR(queue.handle, &present_info)
}
