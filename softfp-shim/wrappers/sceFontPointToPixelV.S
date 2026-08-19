	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceFontPointToPixelV
	.thumb_func
	.type	sceFontPointToPixelV, %function
sceFontPointToPixelV:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_sceFontPointToPixelV
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	sceFontPointToPixelV, . - sceFontPointToPixelV
