	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfPixelToPointV
	.thumb_func
	.type	scePvfPixelToPointV, %function
scePvfPixelToPointV:
	push	{lr}
	vmov	s0, r1
	mov	r1, r2
	bl	__vita_softfp_target_scePvfPixelToPointV
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	scePvfPixelToPointV, . - scePvfPixelToPointV
