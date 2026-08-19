	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceFontPointToPixelH
	.thumb_func
	.type	sceFontPointToPixelH, %function
sceFontPointToPixelH:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_sceFontPointToPixelH
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	sceFontPointToPixelH, . - sceFontPointToPixelH
