	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePvfSetResolution
	.thumb_func
	.type	scePvfSetResolution, %function
scePvfSetResolution:
	vmov	s0, r1
	vmov	s1, r2
	b	__vita_softfp_target_scePvfSetResolution
	.size	scePvfSetResolution, . - scePvfSetResolution
