	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceFontPixelToPointV
	.thumb_func
	.type	sceFontPixelToPointV, %function
sceFontPixelToPointV:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_sceFontPixelToPointV
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	sceFontPixelToPointV, . - sceFontPixelToPointV
