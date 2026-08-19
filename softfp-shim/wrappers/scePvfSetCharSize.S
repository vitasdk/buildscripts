	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfSetCharSize
	.thumb_func
	.type	scePvfSetCharSize, %function
scePvfSetCharSize:
	vmov	s0, r1
	vmov	s1, r2
	b	__vita_softfp_target_scePvfSetCharSize
	.size	scePvfSetCharSize, . - scePvfSetCharSize
