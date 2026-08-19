	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfSetEmboldenRate
	.thumb_func
	.type	scePvfSetEmboldenRate, %function
scePvfSetEmboldenRate:
	vmov	s0, r1
	b	__vita_softfp_target_scePvfSetEmboldenRate
	.size	scePvfSetEmboldenRate, . - scePvfSetEmboldenRate
