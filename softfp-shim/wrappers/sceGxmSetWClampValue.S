	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceGxmSetWClampValue
	.thumb_func
	.type	sceGxmSetWClampValue, %function
sceGxmSetWClampValue:
	vmov	s0, r1
	b	__vita_softfp_target_sceGxmSetWClampValue
	.size	sceGxmSetWClampValue, . - sceGxmSetWClampValue
