;
; If debug == 1 then time constants are lowered for faster simulation
; Also port 2 low nybble is virtually used to simulate buttons because
; s48 simulator has no commands to change interrupt and test input "pins"
;
.equ	debug,		0

; 8042 metronome, tempo from 60 to 236 beats per minute.

; This code is under MIT license. Ken Yap

;;;;;;;;;;;;;;;;;;;;;;;;;;

.ifdef	.__.CPU.		; if we are using as8048 this is defined
.8041
.area	CODE	(ABS)
.endif	; .__.CPU.

; if 1 a blink program will be executed instead
.equ	blinktest,	0

; 0 = driving multiplexed display, 1 = using TM1637 serial display
.equ	tm1637,		1

; 0 = logic 0 bit turns on segment, 1 = logic 1 bit turns on segment
.equ	highison,	1	; using 74LS244 non-inverting buffer

.equ	dingsound,	1	; accented beep turns on p2.4 instead of p2.5

; timing information.
; clk / 5 -- ale (osc / 15). "provided continuously" (pin 11)
; ale / 32 -- "normal" timer rate (osc / 480).
; with 12 MHz crystal, period is 40 us
; with  6 MHz crystal, period is 80 us
; set (negated) timer count, tick = period x scandiv

.if	debug == 1
.equ	scandiv,	-3	; speed up simulation
.else
.equ	scandiv,	-100	; 4 ms (250 Hz) with 12 MHz crystal
.endif	; debug

.equ	tick,		4	; length in ms determined by scandiv

; these are multiples of the tick
.equ	depmin,		100/tick	; switch must be down 100 ms to register
.equ	rptthresh,	500/tick	; repeat kicks in at 500 ms
.equ	rptperiod,	250/tick	; repeat 4 times / second

.if	dingsound == 1
.equ	biplen,		16/tick	; 16ms bip
.equ	beeplen,	60/tick	; 60ms ding, with decay
.else
.equ	biplen,		20/tick	; 20ms bip
.equ	beeplen,	80/tick	; 80ms beep
.endif	; dingsound
.equ	defmetre,	4	; beep, bip, bip, bip

.equ	scancnt,	4

;
; Registers
;
; r0	indirect register
; r3	sound duration count
; r4	period count
; r5	beat count (0 to metre-1)
; r6	temp
; r7	temp

; p1.0 thru p1.7 drive segments when driving with edge triggered latch
; p2.0 thru p2.3 are used in debug mode in simulator, not physically
; p2.4 thru p2.7 drive digits when driving directly. or TM1637
; t0 down tempo
; t1 up tempo
; both change metre
.equ	p22,		0x04
.equ	p22rmask,	~p22
.equ	p23,		0x08
.equ	p23rmask,	~p23
.equ	swmask,		p23|p22

.if	tm1637 == 1
;
; for driving TM1637 based display with 2 lines
;
.equ	data1mask,	0x80	; p2.7
.equ	data0mask,	~data1mask
.equ	clk1mask,	0x40	; p2.6
.equ	clk0mask,	~clk1mask
.equ	maxbright,	0x8f
.endif	; tm1637

.equ	bip1mask,	0x20	; p2.5
.equ	bip0mask,	~bip1mask
.equ	beep1mask,	0x10	; p2.4
.equ	beep0mask,	~beep1mask
; for turning off both
.equ	bipbeep1mask,	bip1mask|beep1mask

;
; scan digit storage (4 digits)
;
.equ	d0,		0x20	; LSD
.equ	d1,		0x21
.equ	d2,		0x22
.equ	d3,		0x23	; MSD

; current display digit storage
.equ	scand,		0x26

.equ	scanbase,	d0

.equ	swstate,	0x28	; previous state of switches
.equ	swtent,		0x29	; tentative state of switches
.equ	swmin,		0x2a	; count of how long state has been stable
.equ	decrepeat,	0x2c	; repeat counter for dectempo
.equ	increpeat,	0x2d	; repeat counter for inctempo

.equ	bpm,		0x30	; units of beats per minute
.equ	bpm10,		0x31	; tens of bpm
.equ	bpm100,		0x32	; hundreds of bpm
.equ	metre,		0x33	; metre: 0,2,3,4,5,6. 0 means no accented beat
.equ	pcount,		0x34	; table offset of counts and tempo

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; reset vector 
	.org	0
.if	blinktest == 1
	jmp	blink
.else
	jmp	metronome
.endif	; blinktest

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; external interrupt vector (pin 6) not used
	.org	3
	dis	i
	retr

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; timer interrupt vector
; scan order is from msd to lsd
; r7 saved a to restore on retr
; r6 digit index 0-3
; r5 saved low nybble of p2

	.org	7
	sel	rb1
	mov	r7, a		; save a
	mov	a, #scandiv	; restart timer
	mov	t, a
	strt	t
.if	tm1637 == 1
				; no interrupt work, TM1637 handles display
.else
	anl	p1, #0x00	; turn off all segments
	mov	r0, #scand
	mov	a, @r0
	dec	a
	mov	@r0, a
	jnz	nextdigit	; if zero, restore our count
	mov	@r0, #scancnt
nextdigit:
	anl	a, #0x03	; restrict to 0-3
	in	a, p2		; get p2 state
	anl	a, #0x0f	; low nybble
	orl	a, #0xf0
	mov	r5, a		; save
	mov	a, r6		; retrieve digit index
	add	a, #digit2mask
	movp	a, @a
	anl	a, r5		; preserve low nybble
	outl	p2, a
	mov	a, r6		; retrieve digit index
	add	a, #scanbase	; index into the 7 segment storage
	mov	r0, a
	mov	a, @r0
	outl	p1, a		; output digit
.endif	; tm1637
	mov	a, r7		; restore a
	retr

.if	tm1637 == 1		; not needed for external display
.else
; convert digit number 0-3 to for port 2 high nybble
digit2mask:
	.db	~0x10		; p2.4 is min
	.db	~0x20		; p2.5 is 10 min
	.db	~0x40		; p2.6 is hour
	.db	~0x80		; p2.7 is 10 hour
.endif	; tm1637

; switch handling
; t0 low is decrease tempo, hold to start, then hold to repeat
; t1 low is increase tempo hours, hold to start, then hold to repeat
; convert to bitmask to easily detect change
; use p2.2 and p2.3 to emulate for debugging
switch:
.if	debug == 1
	in	a, p2
.else
	mov	a, #0xff
	jt0	not0
	anl	a, #p22rmask
not0:
	jt1	not1
	anl	a, #p23rmask
not1:
.endif	; debug
	anl	a, #swmask	; isolate switch bits
	mov	r7, a		; save a copy
	mov	r0, #swtent
	xrl	a, @r0		; compare against last state
	mov	r0, #swmin
	jz	swnochange
	mov	@r0, #depmin	; reload timer
	mov	r0, #swtent
	mov	a, r7
	mov	@r0, a		; save current switch state
	ret
swnochange:
	mov	a, @r0		; check timer
	jz	swaction
	dec	a
	mov	@r0, a
	ret
swaction:
	call	changemetre
	jc	swactioned	; both buttons were down
	jz	noaction
	call	dectempo
	jc	swactioned
	call	inctempo
	jc	swactioned
	jmp	noaction
swactioned:
	call	updatedisplay
noaction:
	mov	r0, #swtent
	mov	a, @r0
	mov	r0, #swstate
	mov	@r0, a
	ret

dectempo:
	clr	c
	mov	r0, #swtent
	mov	a, @r0
	jb2	nodec		; first time through?
	mov	r0, #swstate
	mov	a, @r0
	jb2	dec1
	mov	r0, #decrepeat
	mov	a, @r0
	jz	decwaitover
	dec	a
	mov	@r0, a
	ret
decwaitover:
	mov	r0, #decrepeat
	mov	@r0, #rptperiod
dec1:
	mov	r0, #pcount
	mov	a, @r0
	xrl	a, #tbot-page3
	jz	decret
	mov	a, @r0
	dec	a
	mov	@r0, a
	cpl	c
decret:
	ret
nodec:
	mov	r0, #decrepeat
	mov	@r0, #rptthresh
	ret

inctempo:
	clr	c
	mov	r0, #swtent
	mov	a, @r0
	jb3	noinc		; first time through?
	mov	r0, #swstate
	mov	a, @r0
	jb3	inc1
	mov	r0, #increpeat
	mov	a, @r0
	jz	incwaitover
	dec	a
	mov	@r0, a
	ret
incwaitover:
	mov	r0, #increpeat
	mov	@r0, #rptperiod
inc1:
	mov	r0, #pcount
	mov	a, @r0
	xrl	a, #ttop-page3-1
	jz	incret
	inc	@r0
	cpl	c
incret:
	ret
noinc:
	mov	r0, #increpeat
	mov	@r0, #rptthresh
	ret

;
; r0 -> pcount
;
loadbpm:
	mov	r0, #pcount
	mov	a, @r0
	call	getbpm
	mov	r0, #bpm100
	xch	a, r7
	mov	@r0, a
	mov	a, r7
	mov	r0, #bpm10
	swap	a
	anl	a, #0x0f
	mov	@r0, a
	mov	a, r7
	mov	r0, #bpm
	anl	a, #0x0f
	mov	@r0, a
	ret

changemetre:
	clr	c
	mov	r0, #swtent
	mov	a, @r0
	jnz	nochangemetre	; both buttons down? a != 0
	mov	r0, #swstate
	mov	a, @r0
	jz	nochangemetre	; buttons still down? a == 0
	call	nextmetre	; one or both were up so first time
	clr	c
	cpl	c		; trigger updatedisplay
	clr	a		; also don't trigger any single actions
nochangemetre:
	ret

;
; 0 - 6: map metre to next metre setting
;
metretab:	.db	2, 2, 3, 4, 5, 6, 0

;
; Cycle through the sequence 0,2,3,4,5,6
;
nextmetre:
	mov	r0, #metre
	mov	a, @r0
	add	a, #metretab
	movp	a, @a
	mov	@r0, a
	jz	zerometre
	dec	a
zerometre:
	mov	r5, a		; set beat counter to last, or 0
	mov	r0, #pcount
	mov	a, @r0
	call	getcount
	mov	r4, a		; and reload period counter
	mov	r3, #1		; next tick will turn off sound
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	.org	0x100
metronome:
	clr	f0		; zero some registers and other cold boot stuff
	sel	rb0
.if	tm1637 == 1
.else
	mov 	r0, #scand	; set up digit scan parametres
	mov 	@r0, #scancnt
.endif	; tm1637
	mov	a, #0xff
	outl	p2, a		; p2 is all input
	anl	a, #swmask	; isolate switch bits
	mov	r0, #swstate
	mov	@r0, a
	mov	r0, #swtent
	mov	@r0, a
	mov	r0, #swmin	; preset switch depression counts
	mov	@r0, #depmin
	mov	r0, #increpeat	; and repeat thresholds
	mov	@r0, #rptthresh
	mov	r0, #decrepeat
	mov	@r0, #rptthresh
	mov	r0, #pcount
	mov	a, #defbpm-page3
	mov	@r0, a
	call	getcount
	mov	r4, a
	mov	r0, #metre
	mov	@r0, #defmetre
	mov	r5, #defmetre-1	; after inc will be at first beat
.if	tm1637 == 1
	mov	a, #maxbright
	call	setbright
.endif
	call	updatedisplay
	mov	a, #scandiv	; setup timer and enable its interrupt
	mov	t, a
	strt	t
	en 	tcnti

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; main loop
workloop:
	jtf	ticked
	jmp	workloop	; wait until tick is up
ticked:
	call	tickhandler
	call	switch
	jmp	workloop

; called once per tick
tickhandler:
; decrement sound count
	djnz	r3, soundcont
	inc	r3		; make it stay zero until reload
; turn both sound pins off
	orl	p2, #bipbeep1mask
; decrement period count
soundcont:
	djnz	r4, periodnz
; we decremented the period counter to zero
	call	onesound	; initiate the sound
	call	updatedisplay	; update the beat display
	mov	r0, #pcount
	mov	a, @r0
	call	getcount
	mov	r4, a		; and reload period counter
periodnz:
	ret

;
; This is the basic sound routine, we turn on the beeper for biplen periods
; or beeplen periods, depending on whether we have an accented beat
;
onesound:
	mov	r0, #metre
	mov	a, @r0
	jz	isbip		; if metre is 0 no accented beat
	mov	a, r5		; get current beat
	inc	a		; increment beat
	mov	r5, a
	xrl	a, @r0		; compare against metre
	jnz	isbip
	mov	r5, #0		; back to first beat
	mov	r3, #beeplen	; long beep
.if	dingsound == 1
	anl	p2, #beep0mask	; ding on p2.4
.else
	anl	p2, #bip0mask	; beep on p2.5
.endif	; dingsound
	ret
isbip:
	mov	r3, #biplen	; short bip
	anl	p2, #bip0mask
	ret

; convert binary values to 7-segment patterns
updatedisplay:
	call	loadbpm
	mov	r0, #bpm
	mov	a, @r0
	mov	r1, #d0
	call	byte2segment
	mov	r0, #bpm10
	mov	a, @r0
	mov	r1, #d1
	call	byte2segment
	mov	r0, #bpm100
	mov	a, @r0
	jnz	noblank
	mov	a, #10		; blank if zero
noblank:
	mov	r1, #d2
	call	byte2segment
	mov	r1, #d3
	call	beat2segment
.if	tm1637 == 1
	jmp	updatetm1637
.else
	ret
.endif	; tm1637

	.org	0x200

page2:
;
; TM1637 handling routines translated from C code at
; https://blog.3d-logic.com/2015/01/21/arduino-and-the-tm1637-4-digit-seven-segment-display/
;
.if	tm1637 == 1
updatetm1637:
	call	startxfer
	mov	a, #0x40
	call	writebyte
	call	stopxfer
	call	startxfer
	mov	a, #0xc0
	call	writebyte
	mov	r0, #d3
	mov	a, @r0
	call	writebyte
	mov	r0, #d2
	mov	a, @r0
	call	writebyte
	mov	r0, #d1
	mov	a, @r0
	call	writebyte
	mov	r0, #d0
	mov	a, @r0
	call	writebyte
	call	stopxfer
	ret

;
; Byte to write in A, destructive
;
writebyte:
.if	debug == 1		; don't actually write anything
.else
	mov	r6, #8
writebit:
	anl	p2, #clk0mask
	call	fiveus
	rrc	a
	jc	useor
	anl	p2, #data0mask	; turn bit off
	jmp	wrotebit
useor:
	orl	p2, #data1mask	; turn bit on
wrotebit:
	call	fiveus
	orl	p2, #clk1mask
	call	fiveus
	djnz	r6, writebit

	anl	p2, #clk0mask
	call	fiveus
	orl	p2, #data1mask
	orl	p2, #clk1mask
	call	fiveus
	in	a, p2
.endif	; debug
	ret			; ack in A

startxfer:
	orl	p2, #clk1mask
	orl	p2, #data1mask
	call	fiveus
	anl	p2, #data0mask
	anl	p2, #clk0mask
	call	fiveus
	ret

stopxfer:
	anl	p2, #clk0mask
	anl	p2, #data0mask
	call	fiveus
	orl	p2, #clk1mask
	orl	p2, #data1mask
	call	fiveus
	ret

; The call and return should take at least 5 us

fiveus:
	ret

setbright:
	call	startxfer	; desired brightness in  a
	call	writebyte
	call	stopxfer
	ret

.endif	; tm1637

.if	blinktest == 1
;
; short program to check chip works
;
.equ	p25on,		0xdf
.equ	p25off,		0xff
.equ	delaycount,	125

blink:
	mov	a, #p25on
	outl	p2, a
	call	delay500ms
	mov	a, #p25off
	outl	p2, a
	call	delay500ms
	jmp	blink

delay500ms:
	mov	r0, #delaycount
another4ms:
	mov	a, #scandiv	; restart timer
	mov	t, a
	strt	t
busy4ms:
	jtf	done4ms
	jmp	busy4ms
done4ms:
	stop	tcnt
	djnz	r0, another4ms
	ret
.endif	; blinktest

; font table. (beware of 8048 movp "page" limitation)
; 1's for lit segment since this turns on cathodes
; For TM1637: MSB=colon LSB=a
; Else: MSB=colon LSB=g
; entries for 10-15 are for blanking

dfont:
.if	tm1637 == 1
	.db	0x3f	; 0
	.db	0x06	; 1
	.db	0x5b
	.db	0x4f
	.db	0x66
	.db	0x6d
	.db	0x7d
	.db	0x07
	.db	0x7f
	.db	0x6f
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
.else
.if	highison == 1
	.db	0x7e	; 0
	.db	0x30	; 1
	.db	0x6d
	.db	0x79
	.db	0x33
	.db	0x5b
	.db	0x5f
	.db	0x70
	.db	0x7f
	.db	0x73
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
	.db	0x00
.else
	.db	~0x7e	; 0
	.db	~0x30	; 1
	.db	~0x6d
	.db	~0x79
	.db	~0x33
	.db	~0x5b
	.db	~0x5f
	.db	~0x70
	.db	~0x7f
	.db	~0x73
	.db	~0x00
	.db	~0x00
	.db	~0x00
	.db	~0x00
	.db	~0x00
	.db	~0x00
.endif	; highison
.endif	; tm1637

; convert byte to 7 segment
; a - input, r1 -> storage

byte2segment:
	anl	a, #0xf		; get units
	add	a, #dfont	; index into font table
	movp	a, @a		; grab font for this digit
	mov	@r1, a		; save it
	ret

;
; display the current beat as a sequence of segments
; font currently only for TM1637
;
segs0:
segs1:
	.db	0x00		; nothing for 0 and 1
segs2:
	.db	0x01,0x48	; [a][dg]
segs3:
	.db	0x01,0x41,0x49	; [a][ag][agd]
segs4:
	.db	0x20,0x60	; trace out 4
	.db	0x62,0x66
segs5:
	.db	0x01,0x21	; trace out 5
	.db	0x61,0x65
	.db	0x6d
segs6:
	.db	0x01,0x21	; trace out 6
	.db	0x31,0x39
	.db	0x3d,0x7d

bfont:	.db	segs0-page2	; offsets of start of segment lists
	.db	segs1-page2
	.db	segs2-page2
	.db	segs3-page2
	.db	segs4-page2
	.db	segs5-page2
	.db	segs6-page2

;
; converting to 7-segments pattern is a double index lookup
; first use the metre to index into bfont
; then use the beat number to index into the appropriate segment list
;
beat2segment:
	mov	r0, #metre
	mov	a, @r0		; get metre in a
	add	a, #bfont	; index into bfont
	movp	a, @a		; get start of segment list
	add	a, r5		; index into pattern
	movp	a, @a		; get segment
	mov	@r1, a		; store in d3
	ret

;
; Tables and lookup routines
;
	.org	0x300

page3:

.include	"table.asm"

getcount:
	add	a, #tbot-page3
	movp3	a, @a
	ret

;
; a -> offset
; return bpm as 100 * r7 + a
;
getbpm:
	rl	a	; *2
	mov	r7, a	; save
	inc	a
	add	a, #bcdtempi-page3
	movp3	a, @a	; get hundreds
	xch	a, r7
	add	a, #bcdtempi-page3
	movp3	a, @a	; get remainder
	ret

ident:
	.db	0x0
	.db	0x4b, 0x65, 0x6e
	.db	0x20
	.db	0x59, 0x61, 0x70
	.db	0x20
	.db	0x32, 0x30	; 20
	.db	0x31, 0x38	; 18
	.db	0x0

; end
