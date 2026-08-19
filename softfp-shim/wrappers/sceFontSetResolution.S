	.syntax unified
	.thumb
	.text
	.align	2
	.global	sceFontSetResolution
	.thumb_func
	.type	sceFontSetResolution, %function
sceFontSetResolution:
	vmov	s0, r1
	vmov	s1, r2
	b	__vita_softfp_target_sceFontSetResolution
	.size	sceFontSetResolution, . - sceFontSetResolution
