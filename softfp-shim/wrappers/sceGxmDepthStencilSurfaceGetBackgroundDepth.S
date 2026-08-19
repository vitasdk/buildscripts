	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceGxmDepthStencilSurfaceGetBackgroundDepth
	.thumb_func
	.type	sceGxmDepthStencilSurfaceGetBackgroundDepth, %function
sceGxmDepthStencilSurfaceGetBackgroundDepth:
	push	{lr}
	bl	__vita_softfp_target_sceGxmDepthStencilSurfaceGetBackgroundDepth
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	sceGxmDepthStencilSurfaceGetBackgroundDepth, . - sceGxmDepthStencilSurfaceGetBackgroundDepth
