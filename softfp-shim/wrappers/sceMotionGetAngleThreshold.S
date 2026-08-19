	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceMotionGetAngleThreshold
	.thumb_func
	.type	sceMotionGetAngleThreshold, %function
sceMotionGetAngleThreshold:
	push	{lr}
	bl	__vita_softfp_target_sceMotionGetAngleThreshold
	vmov	r0, s0
	pop	{lr}
	bx	lr
	.size	sceMotionGetAngleThreshold, . - sceMotionGetAngleThreshold
