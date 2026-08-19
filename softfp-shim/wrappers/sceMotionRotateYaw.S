	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceMotionRotateYaw
	.thumb_func
	.type	sceMotionRotateYaw, %function
sceMotionRotateYaw:
	vmov	s0, r0
	b	__vita_softfp_target_sceMotionRotateYaw
	.size	sceMotionRotateYaw, . - sceMotionRotateYaw
