	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfPointToPixelV
	.thumb_func
	.type	scePvfPointToPixelV, %function
scePvfPointToPixelV:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_scePvfPointToPixelV
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	scePvfPointToPixelV, . - scePvfPointToPixelV
