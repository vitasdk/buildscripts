	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfSetSkewValue
	.thumb_func
	.type	scePvfSetSkewValue, %function
scePvfSetSkewValue:
	vmov	s0, r1
	vmov	s1, r2
	b	__vita_softfp_target_scePvfSetSkewValue
	.size	scePvfSetSkewValue, . - scePvfSetSkewValue
