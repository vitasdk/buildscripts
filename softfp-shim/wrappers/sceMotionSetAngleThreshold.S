	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceMotionSetAngleThreshold
	.thumb_func
	.type	sceMotionSetAngleThreshold, %function
sceMotionSetAngleThreshold:
	vmov	s0, r0
	b	__vita_softfp_target_sceMotionSetAngleThreshold
	.size	sceMotionSetAngleThreshold, . - sceMotionSetAngleThreshold
