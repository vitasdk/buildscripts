	.syntax unified
	.thumb
	.text
	.align	2
	.global	scePafGraphicsUpdateCurrentWave
	.thumb_func
	.type	scePafGraphicsUpdateCurrentWave, %function
scePafGraphicsUpdateCurrentWave:
	vmov	s0, r1
	b	__vita_softfp_target_scePafGraphicsUpdateCurrentWave
	.size	scePafGraphicsUpdateCurrentWave, . - scePafGraphicsUpdateCurrentWave
