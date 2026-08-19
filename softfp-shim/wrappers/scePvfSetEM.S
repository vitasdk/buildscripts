	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfSetEM
	.thumb_func
	.type	scePvfSetEM, %function
scePvfSetEM:
	vmov	s0, r1
	b	__vita_softfp_target_scePvfSetEM
	.size	scePvfSetEM, . - scePvfSetEM
