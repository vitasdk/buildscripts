	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceGxmDepthStencilSurfaceSetBackgroundDepth
	.thumb_func
	.type	sceGxmDepthStencilSurfaceSetBackgroundDepth, %function
sceGxmDepthStencilSurfaceSetBackgroundDepth:
	vmov	s0, r1
	b	__vita_softfp_target_sceGxmDepthStencilSurfaceSetBackgroundDepth
	.size	sceGxmDepthStencilSurfaceSetBackgroundDepth, . - sceGxmDepthStencilSurfaceSetBackgroundDepth
