	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceFontPixelToPointH
	.thumb_func
	.type	sceFontPixelToPointH, %function
sceFontPixelToPointH:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_sceFontPixelToPointH
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	sceFontPixelToPointH, . - sceFontPixelToPointH
