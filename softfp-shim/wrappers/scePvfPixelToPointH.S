	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfPixelToPointH
	.thumb_func
	.type	scePvfPixelToPointH, %function
scePvfPixelToPointH:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_scePvfPixelToPointH
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	scePvfPixelToPointH, . - scePvfPixelToPointH
