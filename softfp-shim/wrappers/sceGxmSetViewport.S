	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceGxmSetViewport
	.thumb_func
	.type	sceGxmSetViewport, %function
sceGxmSetViewport:
	vmov	s0, r1
	vmov	s1, r2
	vmov	s2, r3
	ldr	r1, [sp, #0]
	vmov	s3, r1
	ldr	r2, [sp, #4]
	vmov	s4, r2
	ldr	r3, [sp, #8]
	vmov	s5, r3
	b	__vita_softfp_target_sceGxmSetViewport
	.size	sceGxmSetViewport, . - sceGxmSetViewport
