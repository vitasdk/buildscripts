	.syntax unified
	.thumb
	.text
	.align	2
	.global	sce_paf_strtod
	.thumb_func
	.type	sce_paf_strtod, %function
sce_paf_strtod:
	push	{lr}
	bl	__vita_softfp_target_sce_paf_strtod
	vmov	r0, r1, d0
	pop	{lr}
	bx	lr
	.size	sce_paf_strtod, . - sce_paf_strtod
