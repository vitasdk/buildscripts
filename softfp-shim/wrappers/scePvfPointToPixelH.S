	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfPointToPixelH
	.thumb_func
	.type	scePvfPointToPixelH, %function
scePvfPointToPixelH:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_scePvfPointToPixelH
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	scePvfPointToPixelH, . - scePvfPointToPixelH
