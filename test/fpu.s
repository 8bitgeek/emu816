;;
;; Copyright (c) 2016 Marco Granati <mg@unet.bz>
;;
;; Permission to use, copy, modify, and distribute this software for any
;; purpose with or without fee is hereby granted, provided that the above
;; copyright notice and this permission notice appear in all copies.
;;
;; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
;; WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
;; MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
;; ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
;; WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
;; ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
;; OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
;;

;; name: fpu.asm
;; rev.: 2016/06/05
;; o.s. 65C816 version v1.0

;; Implementation of ieee 754 quadruple precision floating point 
;; for 65C816 (accuracy 33/35 decimal digits)

; Implementation notes
;
;	+o  Precision is 34/35 decimal digits. All functions give an accuracy
;	    of 34 decimal digits (max. relative error < 1e-34) if not 
;	    differently specified.
;
;	+o  No exceptions mechanism is provided, instead any function returns
;	    invalid results (inf,nan) by setting carry flag. Also, operands
;	    can be checked by checking status byte (facst, argst).
;
;	+o  Subnormal numbers are properly handled.
;
;	+o  Internal format slightly different from the external IEEE format:
;	    the "hidden' bit explicity stored and whole significand
;	    is 128 bits sized (113 significand bits plus 15 guard bits).
;
;	+o  All internal operations done with 128 bits significand.
;
;	+o  Argument of circular functions (fsin, fcos, ftan, fcotan) should
;	    be less than 2^56 due to error reducing argument to pi/4.
;
;	+o  As in each floating point implementation, the subtraction of two
;	    very close arguments cause a partial "cancellation" and an
;	    accuracy losing. As example (exponent after 'P'):
;
;		0.0000001 	$D6BF94D5E57A42BC3D32907604691B4DP3FE7
;		1.0000001	$800000D6BF94D5E57A42BC3D32907604P3FFF
;		1.0000000	$80000000000000000000000000000000P3FFF
;
;	    but computing 1.0000001 - 1.0000000 give:
;
;				$D6BF94D5E57A42BC3D32907604000000P3FE7
;
;	    where "cancellation" cleared last 24 bits of significand and the
;	    decimal (rounded) results is (compare with the exact 1.0E-7):
;
;			9.9999999999999999999999999999997587E-0008
;

; Implemented functions:
;	fpadd, fpsub, fpmult, fpdiv: the 4 basic operations
;	fsquare:	x^2
;	frecip:		1/x
;	fscale:		x*2^n -- n integer (scale by power of two)
;	scale10:	x*10^n -- n integer (scale by power of ten)
;	fsqrt:		square root
;	fcbrt:		cube root
;	floge:		loge(x) = ln(x)
;	flog10:		log10(x)
;	flog2:		log2(x)
;	flogep1:	ln(1 + x)
;	flog10p1:	log10(1 + x)
;	flog2p1:	log2(1 + x)
;	fexp:		exp(x)
;	fexp10:		exp10(x) = 10^x
;	fexp2:		exp2(x) = 2^x
;	fexpm1:		exp(x) - 1
;	fpown:		x^n -- n integer
;	frootn:		x^(1/n) -- n integer
;	fpowxy:		x^y
;	fsin:		sin(x)
;	fcos:		cos(x)
;	ftan:		tan(x)
;	fcotan:		cotan(x)
;	fasin:		arcsin(x)
;	facos:		arccos(x)
;	fatan:		arctan(x)
;	fatanyx:	arctan(y/x) (computes the phase angle)
;	fsinh:		sinh(x)
;	fcosh:		cosh(x)
;	ftanh:		tanh(x)
;	fasinh:		arcsinh(x)
;	facosh:		arccosh(x)
;	fatanh:		arctanh(x)
;	fpfrac:		extract integral & fractional part
;	fprexp:		extract the exponent
;	ftrunc, fceil,
;	floor, fround: rounding functions
;	fpmod, fprem:	remainders functions
;	fldu16, fldu32, 
;	fldu64, fldu128: convert unsigned integer to float
;	uitrunc:	truncate (toward zero) a float to unsigned integer
;	str2fp:		convert ascii string to float
;	fp2str:		convert float to ascii string
;	str2int:	convert ascii string to integer
;	int2str:	convert integer to ascii string
;	int2dec:	convert signed integer to decimal ascii string
;	uint2dec:	convert unsigned integer to decimal ascii string
;	fpack:		round to 113 bits significand and store in IEEE format
;	funpack:	get an IEEE format and store in f.p. accumulator
	
.P816
.LOCALCHAR  '?'
.LIST on

;---------------------------------------------------------------------------
; macro's
;---------------------------------------------------------------------------

; status register
PNFLAG		=	%10000000	; Negative flag
PVFLAG		=	%01000000	; Overflow flag
PMFLAG		=	%00100000	; Acc/Mem 8 bit flag
PXFLAG		=	%00010000	; Index 8 bit flag
PDFLAG		=	%00001000	; Decimal flag
PIFLAG		=	%00000100	; IRQ disable flag
PZFLAG		=	%00000010	; Zero flag
PCFLAG		=	%00000001	; Carry flag

PFALL		=	PNFLAG+PVFLAG+PZFLAG+PCFLAG
	
; set A/M 16 bit
ACC16:		.MACRO
	.MLIST
	rep	#PMFLAG
	.LONGA	on
	.MNLIST
.ENDM

; set A/M 16 bit, clear carry
ACC16CLC:	.MACRO
	.MLIST
	rep	#(PMFLAG.OR.PCFLAG)
	.LONGA	on
	.MNLIST
.ENDM

; set A/M 8 bit
ACC08:		.MACRO
	.MLIST
	sep	#PMFLAG
	.LONGA	off
	.MNLIST
.ENDM

; set X/Y 16 bit
INDEX16:	.MACRO
	.MLIST
	rep	#PXFLAG
	.LONGI	on
	.MNLIST
.ENDM

; set X/Y 8 bit
INDEX08:	.MACRO
	.MLIST
	sep	#PXFLAG
	.LONGI	off
	.MNLIST
.ENDM

; set A/M & X/Y 16 bit
CPU16:		.MACRO
	.MLIST
	rep	#(PMFLAG.OR.PXFLAG)
	.LONGA	on
	.LONGI	on
	.MNLIST
.ENDM

; set A/M & X/Y 16 bit & clear carry
CPU16CLC:	.MACRO
	.MLIST
	rep	#(PMFLAG.OR.PXFLAG.OR.PCFLAG)
	.LONGA	on
	.LONGI	on
	.MNLIST
.ENDM

; set A/M & X/Y 8 bit
CPU08:		.MACRO
	.MLIST
	sep	#(PMFLAG.OR.PXFLAG)
	.LONGA	off
	.LONGI	off
	.MNLIST
.ENDM

; define a long-pointer (24 bit)
LP	.MACRO
	.RES 3
	.ENDM

;---------------------------------------------------------------------------
; direct page for floating point unit
;---------------------------------------------------------------------------

_DPFPU:	.SECTION page0, common, ref_only, offset 0	;FPU D.P.

MNTBITS		=	(16*8)	; significand bits + guard bits
MANTSIZ		=	16	; significand size
FREGSIZ		=	20	; floating point register size

tm		.RES	16	; temp. mantissa

fsubnf		.BYTE		; subnormal flag used by fac2dec
atncode		=	fsubnf	; fatanyx octant

sgncmp		.BYTE		; sign comparison: fac vs. arg

; floating Point accumulator (fac)
facm		.RES	16	; guard bits (32 bits)+significand (80 bits)
facexp		.WORD		; fac biased exponent
facsgn		.BYTE		; fac mantissa sign
facst		.BYTE		; fac status for floating point
				; <7>: 1 if fac is invalid (nan or inf)
				; <6>: 1 if fac=inf (with <7>=1)   
				;      0 if fac=nan (with <7>=1)   
				; <6>: 1 if fac=0   (with <7>=0)
				; <5>: always '0'

				; fac status for long integer
				; <7>: 1 if facm will be regarded as 'signed'
				; <6>: 1 if facm = 0
				; <5>: always '1'

fexph		.WORD		; unbiased fac exponent sign extension
facext		.WORD		; fac guard bits extension
wftmp2		=	facext
facsiz		=	facsgn	; integer only: size in bytes 	

; floating point operand (arg)
argm		.RES	16	; guard bits (32 bits)+significand (80 bits)
argexp		.WORD		; arg biased exponent
argsgn		.BYTE		; arg mantissa sign
argst		.BYTE		; arg status for floating point
				; <7>: 1 if arg is invalid (nan or inf)
				; <6>: 1 if arg=inf (with <7>=1)   
				;      0 if arg=nan (with <7>=1)   
				; <6>: 1 if arg=0   (with <7>=0)

				; arg status for long integer
				; <7>: 1 if facm will be regarded as 'signed'
				; <6>: 1 if facm = 0
				; <5>: always '1'
			
aexph		.WORD		; unbiased arg exponent sign extension
argext		.WORD

wftmp		=	aexph	; temp. word (int2dec, fpadd, fpsub)
argsiz		=	argsgn	; integer only: size in bytes 	

fcp		LP		; long pointer to flaot constants
scsgn		.BYTE		; scaling sign
scexp		.WORD		; scaling value
dexp		.WORD		; decimal exponent
dsgn		.BYTE		; decimal float sign
pdeg		.BYTE		; polyn. degree
powfg		=	pdeg	; flag used by fpowxy

tlp		LP		; string long pointer
fpidx		.BYTE		; string index
		
tfr0		.RES	20	; temp. float reg. 0
tfr1		.RES	20	; temp. float reg. 1
tfr2		.RES	20	; temp. float reg. 2
tfr3		.RES	20	; temp. float reg. 3
tfr4		.RES	20	; temp. float reg. 4
tfr5		.RES	20	; temp. float reg. 5
		.RES	4	; used by xcvt: doesn't change

XCVTEND		=	($ - 1)	; last byte of xcvt buffer

; buffer used by decimal conversion (overlap tfr0&tfr1: 40 bytes)
fpstr		=	tfr0	; 40 bytes buffer
; buffer used to format a decimal string
xcvt		=	tfr2	; 84 bytes buffer

fcpc0		=	tfr5	; constants pointer for exp. function
fcpc1		=	tfr5+2
fcpc2		=	tfr5+4
fcpp		=	tfr5+6
fcpq		=	tfr5+8
fcpd		=	tfr5+10
fcqd		=	tfr5+11
fcpolf		=	tfr5+12	; polynomial flag

tmdot		=	tfr5	; digit count after decimal dot
tmpa		=	tfr5+2	; temp: save A&Y
tmpy		=	tfr5+3
tmsgn		=	tfr5+4	; temp.: significand sign
tmcnt		=	tfr5+5	; temp.: significand digits count
tesgn		=	tfr5+6	; temp.: exponent sign 
tecnt		=	tfr5+7	; temp.: exponent digits count

mcand1		=	tfr5+8	; multiplicand's 
mcand2		=	tfr5+10
mcsgn		=	tfr5+12
dvsor		=	tfr5+14
quot		=	tfr5+16

fpprec		.WORD		; precision
fpfmt		.BYTE		; format
fpaltf		.BYTE		; alternate format
fpcap		.BYTE		; adding for lower case
fpstyle		.BYTE		; flag 'F' style
fpdot		=	pdeg	; decimal dot flag
fpoct		=	fpfmt	; octant (circular func's)
fpcsgn		=	fpaltf	; circular func's: argument sign
fpcot		=	fpcap	; cotangent flag
fpasin		=	fpcap	; asin flag

.ENDS

;---------------------------------------------------------------------------
; equates
;---------------------------------------------------------------------------

P0FPU		=	$1000		; direct page (arbitrary)

EBIAS		=	$3FFF		; exponent bias
INFEXP		=	$7FFF		; inf/nan biased exponent
INFSND		=	$8000		; infinity high word significand
NANSND		=	$C000		; nan high word significand
MAXEXP		=	$7FFE		; max. biased exponent
SNBITS		=	113		; significand bits

BIAS8		= 	(EBIAS + 7)	; bias exponent for 8 bit integer
BIAS16		= 	(BIAS8 + 8)	; bias exponent for 16 bit integer
BIAS32		= 	(BIAS16 + 16)	; bias exponent for 32 bit integer
BIAS64		= 	(BIAS32 + 32)	; bias exponent for 64 bit integer
BIAS128		= 	(BIAS64 + 64)	; bias exponent for 128 bit integer
BIAS56		=	$4037		; biased exponent of 2^56
LOG2H		=	19728		; approximated log10(2) * $10000
MAXDIGITS	=	36		; max. decimal digits
EXP10		=	38		; decimal exponent for 128 bits integer 
MINGEXP		=	-4		; min. decimal exponent 'G' format

MAXBSHIFT	=	-MNTBITS + 1	; max. shift mant.

XCVTMAX		=	80		; max. size of decimal string

;---------------------------------------------------------------------------
; code segment
; WARNING -- all routines need that on entry the direct page register loaded
; with the right value (here: P0FPU), and data bank register loaded with $00
;---------------------------------------------------------------------------

	.CODE

	.LONGA	off
	.LONGI	off

;---------------------------------------------------------------------------
; addition & subtraction implementation
;---------------------------------------------------------------------------

; fcsub - subtract the argument from one constant stored in program memory
;
;	entry:
;		fac = x
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		fac = K - x
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;-----
fcsub:
;-----
	jsr	ldarg		; move K to arg...
				; ...and execute arg - fac

; fpsub - subtract fac from arg and store result in fac
; main subtraction routine
;
;	entry:
;		arg = x
;		fac = y
;		CF = 1 if invalid result(inf or nan)
;
;	exit:
;		fac = x - y
;
;-----
fpsub:
;-----
	lda	facsgn		; change sign to fac...
	eor	#$FF
	sta	facsgn
	bra	fpadd		; and execute arg + (-fac)

; faddhalf - add 0.5 to the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = x + 0.5
;
; This routine is used internally and not intended for end use.
;
;--------
faddhalf:
;--------
	jsr	ldahalf		; move constant K=0.5 to arg...
	bra	fpadd		; ...and execute arg+fac

; faddone - add 1.0 to the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = x + 1.0
;
; This routine is used internally and not intended for end use.
;
;-------
faddone:
;-------
	jsr	ldaone		; move constant K=1.0 to arg...
	bra	fpadd		; ...and execute arg+fac

; fsubone - subtract 1.0 from the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = x - 1.0
;
; This routine is used internally and not intended for end use.
;
;-------
fsubone:
;-------
	jsr	ldaone		; move constant K=1.0 to arg...
	lda	#$FF
	sta	argsgn		; ...change sign to arg...
	bra	fpadd		; ...and execute arg+fac
	
; fcadd - add the argument to one constant stored in program memory
;
;	entry:
;		fac = x
;		fcp = long pointer to the constant K
;
;	exit:
;		fac = K + x
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;-----
fcadd:
;-----
	jsr	ldarg2		; move K to arg...
				; ...and execute arg + fac

; fpadd: add fac to arg and store result in fac
; main addition routine
;
;	entry:
;		arg = x
;		fac = y
;
;	exit:
;		fac = x + y
;		CF = 1 if invalid result(inf or nan)
;
; The smallest operand will be aligned shifting to right the mantissa and
; incrementing the exponent until is equal to exponent of the greatest
; operand. After alignment, mantissa of fac is added to mantissa of arg if
; fac and arg have same sign, otherwise mantissa of the smallest operand will
; be subctracted from mantissa of the greatest one (except in the case that
; none of the operands has been shifted: in this case maybe need to change
; sign to result).
;
;-----
fpadd:
;-----
	jsr	addtst		; operands test: check for inf,nan, 0
	ldx	#argm		; pointer to arg mantissa
	ldy	#0
	ACC16
	sec
	lda	argexp		; now compute right shift count's to...
	sbc	facexp		; ...align mantissa's
	beq	?go		; already aligned (same exponent)
	bcc	?sh		; arg < fac so shift right arg mantissa...
				; ...and result have same exp&sign of fac...
	
	; fac > arg so shift right fac mantissa - here CF=1, Y=0
	sta	wftmp		; positive shift's count
	lda	argexp		; result have same exp of arg...
	sta	facexp
	ldx	argsgn		; ...and same sign of arg
	stx	facsgn
	tya			; remember here CF=1
	sbc	wftmp		; negative shift's count
	ldx	#facm		; pointer to fac mantissa

?sh:	; right shift mantissa pointed by X - here C=negative shift's count
	cmp	#MAXBSHIFT	; shift out whole significand?
	bcs	?shm		; no
	stz	<0,x		; clear mantissa whole mantissa
	stz	<2,x
	stz	<4,x
	stz	<6,x
	stz	<8,x
	stz	<10,x
	stz	<12,x
	stz	<14,x
	bra	?go		; go to add/sub
	
?shm:	ACC08			; A=negative shift's count
	jsr	shrmx		; shift right mantissa pointed by X
	ACC16

	; add/sub aligned mantissa's
?go:	ldy	sgncmp		; fac & arg have same sign?
	bpl	?add		; yes, so add mantissa's

	; X=mantissa pointer (pssibly to the shifted operand)
	; always subtract the smallest operand from the greatest one,
	; except in the case that none of the operands has been shifted

	ldy	#facm
	cpx	#argm
	beq	?sub		; mantissa_fac - mantissa_arg
	ldy	#argm		; mantissa_arg - mantissa_fac
?sub:	sec
	lda	P0FPU,y
	sbc	<0,x
	sta	facm
	lda	P0FPU+2,y
	sbc	<2,x
	sta	facm+2
	lda	P0FPU+4,y
	sbc	<4,x
	sta	facm+4
	lda	P0FPU+6,y
	sbc	<6,x
	sta	facm+6
	lda	P0FPU+8,y
	sbc	<8,x
	sta	facm+8
	lda	P0FPU+10,y
	sbc	<10,x
	sta	facm+10
	lda	P0FPU+12,y
	sbc	<12,x
	sta	facm+12
	lda	P0FPU+14,y
	sbc	<14,x
	sta	facm+14
	ACC08
	bcs	normfac		; no borrow -- normalize fac
	
	; a borrow mean that result change sign so we should negate mantissa
	; this can happen just when operands have same exponent

	jsr	negfac		; negate fac because result change sign
	bra	normfac		; normalize fac  
	
?add: 	ACC16CLC		; add fac & arg mantissa's
	lda	facm
	adc	argm
	sta	facm
	lda	facm+2
	adc	argm+2
	sta	facm+2
	lda	facm+4
	adc	argm+4
	sta	facm+4
	lda	facm+6
	adc	argm+6
	sta	facm+6
	lda	facm+8
	adc	argm+8
	sta	facm+8
	lda	facm+10
	adc	argm+10
	sta	facm+10
	lda	facm+12
	adc	argm+12
	sta	facm+12
	lda	facm+14
	adc	argm+14
	sta	facm+14
	bcc	normfac		; normalize fac after addition
	
	; the sum generate a carry so we add carry to fac	

; addcf - add a carry to fac
;
;	fac exponent will be incrementated and mantissa will be shifted
;	one place to right, and '1' is routed to the mantissa msb.
;	Note that this operation can cause overflow
;
; This routine is used internally and not intended for end use.
;
;-----
addcf:
;-----
	ACC16
	lda	facexp
	inc	a		; increment exponent
	cmp	#INFEXP		; overflow?
	bcc	?10		; no
	jmp	fldinf		; yes, so set fac=inf
?10:	sta	facexp
	sec			; msb=1
	ror	facm+14		; shift right mantissa one place
	ror	facm+12
	ror	facm+10	
	ror	facm+8
	ror	facm+6
	ror	facm+4
	ror	facm+2
	ror	facm	
	ACC08
	clc			; return no error condition
	rts

; normfac - try to normalize fac after addition/subtraction or 
; while convert an integer to floting point
;
; 	The msb of mantissa will be '1', except in the case of subnormal.
;	This normalitation is accomplished by shifting toward left
;	the significand until msb=1 or biased exponent=1; at any shift
;	biased exponent is decremented.
;
; This routine is used internally and not intended for end use.
;
;-------
normfac:
;-------
	ACC16
	lda	facexp
	dec	a		; exp=exp-1
	beq	chkz		; fac have minimum biased exponent (1)
	sec
	ldy	#MANTSIZ
?lp:	ldx	facm+15
	bmi	?end		; already normalized: nothing to do
	bne	?shb		; shift bit at bit
	sbc	#8		; can shift a whole byte?
	bcc	?rst		; no, restore exponent
	ldx	facm+14		; shift toward left byte at byte
	stx	facm+15	
	ldx	facm+13
	stx	facm+14	
	ldx	facm+12
	stx	facm+13	
	ldx	facm+11
	stx	facm+12	
	ldx	facm+10
	stx	facm+11	
	ldx	facm+9
	stx	facm+10
	ldx	facm+8
	stx	facm+9
	ldx	facm+7
	stx	facm+8
	ldx	facm+6
	stx	facm+7
	ldx	facm+5
	stx	facm+6
	ldx	facm+4
	stx	facm+5
	ldx	facm+3
	stx	facm+4
	ldx	facm+2
	stx	facm+3
	ldx	facm+1
	stx	facm+2
	ldx	facm
	stx	facm+1
	ldx	#0		; in last byte enter a zero...
	stx	facm
	dey			; loop until all bytes was shifted
	bne	?lp
	stz	facexp		; at this point fac=0...
	bra	chkz2		; ...and set status byte
?rst:	adc	#8		; restore exponent...
	inc	a
?cnt:	dec	a		; decrement exponent while bit shifting...
	beq	?end		; can't shift more (exponent=1)
?shb:	asl	facm		; shift toward left one bit at time
	rol	facm+2
	rol	facm+4
	rol	facm+6
	rol	facm+8
	rol	facm+10
	rol	facm+12
	rol	facm+14	
	bpl	?cnt		; shift until msb=0
	bmi	?end2		; finish
?end:	inc	a		; restore exponent...
?end2:	sta	facexp		; ...and set fac exponent
	cmp	#INFEXP		; check overflow condition
	bcc	chkz		; no overflow: chexck if fac=0
	ACC08
	jmp	fldinf		; set fac=inf

; chkz - check if fac=0; if fac=0 set the status byte
;
; This routine is used internally and not intended for end use.
;
;----
chkz:
;----
	ACC16			; if all significand bits are '0'...
	lda	facm		; ...then fac=0
	ora	facm+2
	ora	facm+4
	ora	facm+6
	ora	facm+8
	ora	facm+10
	ora	facm+12
	ora	facm+14	
	bne	chkz3
	sta	facexp		; set biased exponent = 0
chkz2:	ldx	#$40		; set status byte for 'zero' condition
	stx	facst
chkz3:	ACC08
	clc
	rts

; negfac - negate fac (2's complement)
;
; this routine will be called after a subtraction
; that change the sign of the result
;
; This routine is used internally and not intended for end use.
;
;------
negfac:
;------
	lda	facsgn		; change fac sign
	eor	#$FF
	sta	facsgn
	ldx	#0
	CPU16			; two's complement
	sec
	txa
	sbc	facm
	sta	facm
	txa
	sbc	facm+2
	sta	facm+2
	txa
	sbc	facm+4
	sta	facm+4
	txa
	sbc	facm+6
	sta	facm+6
	txa
	sbc	facm+8
	sta	facm+8
	txa
	sbc	facm+10
	sta	facm+10
	txa
	sbc	facm+12
	sta	facm+12
	txa
	sbc	facm+14
	sta	facm+14
	CPU08
	rts

; shrmx - shift mantissa pointed by X toward right
;
;	entry:	A=negative shift's count (max. 128 bit)
;		X=mantissa pointer
;
;	exit:
;		mantissa is shifted toward right and 0 will be routed to msb
;
; This routine is used internally and not intended for end use.
;
;-----
shrmx:
;-----
	cmp	#$F9		; NF=1,CF=0 if $79<=A<$F9 else NF=0,CF=1
	bpl	?shb		; shift right less than 8 bit (CF=1)
	bra	?tst2		; CF=0, shift at least 8 bit or more
?sh16:	CPU16			; shift right 16 bit at time
	ldy	<2,x
	sty	<0,x
	ldy	<4,x
	sty	<2,x
	ldy	<6,x
	sty	<4,x
	ldy	<8,x
	sty	<6,x
	ldy	<10,x
	sty	<8,x
	ldy	<12,x
	sty	<10,x
	ldy	<14,x
	sty	<12,x
	stz	<14,x
	CPU08
	bra	?tst2		; continue
?tst1:	adc	#8		; check if can shift 16 bit at time
	bmi	?sh16		; yes (here CF=0)
	beq	?sh16		; yes (here CF=1)
	sbc	#8		; restore shift count and shift 8 bit at time
				; also note here result is negative and CF=0
?sh8:	ldy	<1,x		; shift right 8 bit at time
	sty	<0,x
	ldy	<2,x
	sty	<1,x
	ldy	<3,x
	sty	<2,x
	ldy	<4,x
	sty	<3,x
	ldy	<5,x
	sty	<4,x
	ldy	<6,x
	sty	<5,x
	ldy	<7,x
	sty	<6,x
	ldy	<8,x
	sty	<7,x
	ldy	<9,x
	sty	<8,x
	ldy	<10,x
	sty	<9,x
	ldy	<11,x
	sty	<10,x
	ldy	<12,x
	sty	<11,x
	ldy	<13,x
	sty	<12,x
	ldy	<14,x
	sty	<13,x
	ldy	<15,x
	sty	<14,x
	stz	<15,x
?tst2:	adc	#8		; test if can shift 8/16 bit at time
	bmi	?tst1		; test if can shift 16 bit at time (CF=0)
	beq	?sh8		; shift 8 bit (here CF=1)
	sbc	#8		; restore shift count
	bcs	?end		; finish if shift count >= 0
?shb:	tay			; residual bit shift count
	beq	?end		; nothing to shift
	ACC16
	lda	<0,x		; lsb+guard bits
?sh:	lsr	<14,x		; msb=0
	ror	<12,x
	ror	<10,x
	ror	<8,x
	ror	<6,x
	ror	<4,x
	ror	<2,x
	ror	a		; rotate lsb
	iny
	bne	?sh
	sta	<0,x		; store lsb+guards bits
	ACC08
?end:	rts

; shlmx - shift mantissa pointed by X to left until msb of mantissa equal 1
; and decrement unbiased exponent according with shift's count.
; 
; this routine is called for 'normalize' a subnormal operand
;
; call with A/M in 16 bit mode
;
; This routine is used internally and not intended for end use.
;
;-----
shlmx:
;-----
	.LONGA	on		; should be called with A/M=16 bit
	.LONGI	off

	sec
	lda	<16,x		; C=unbiased exponent
?lp1:	ldy	<15,x		; shift count < 8?
	bne	?sh		; yes
	sbc	#8		; 8 bits shift
	ldy	<14,x		; shift toward left byte at byte
	sty	<15,x	
	ldy	<13,x
	sty	<14,x	
	ldy	<12,x
	sty	<13,x	
	ldy	<11,x
	sty	<12,x	
	ldy	<10,x
	sty	<11,x	
	ldy	<9,x
	sty	<10,x
	ldy	<8,x
	sty	<9,x
	ldy	<7,x
	sty	<8,x
	ldy	<6,x
	sty	<7,x
	ldy	<5,x
	sty	<6,x
	ldy	<4,x
	sty	<5,x
	ldy	<3,x
	sty	<4,x
	ldy	<2,x
	sty	<3,x
	ldy	<1,x
	sty	<2,x
	ldy	<0,x
	sty	<1,x
	ldy	#0
	sty	<0,x
	cmp	#MAXBSHIFT	; shifted all whole mantissa?
	beq	?done		; yes, store exponent
	bcs	?lp1		; no, try again
	bra	?done		; store exponent
?lp2:	dec	a		; decrement exponent
	asl	<0,x
	rol	<2,x
	rol	<4,x
	rol	<6,x
	rol	<8,x
	rol	<10,x
	rol	<12,x
	rol	<14,x	
?sh:	bpl	?lp2		; if msb=0 shift to left one place
?done:	sta	<16,x		; store exponent
	bit	<16,x		; check exponent sign
	bpl	?end
	dec	<20,x		; sign extension to 32 bit
?end:	rts

	.LONGA	off

; addtst - test operands before to execute addition/subtraction
;
; This routine test fac & arg for validity, and return to the caller
; for any abnormal condition:
;
;	1) return nan if fac=nan or arg=nan
;	2) return nan if |fac|=|arg|=inf and arg&fac have opposites sign
;	3) return +inf or -inf if fac=arg=+/-inf
;	4) return +inf or -inf if fac=+/-inf and arg is valid
;	5) return +inf or -inf if arg=+/-inf and fac is valid
;
; This routine is used internally and not intended for end use.
;
;------
addtst:
;------
	lda	facsgn		; compare sign
	eor	argsgn
	sta	sgncmp
	sec			; invalid result flag
	bit	facst		; test fac
	bpl	?arg		; fac is valid, go to check arg
	bvc	?skp		; fac=nan so result=nan (fac sign)
	bit	argst		; fac=inf so check arg
	bpl	?skp		; fac=inf & arg=y so result=inf (fac sign)
	bvc	?mv		; fac=inf & arg=nan so result=nan (arg sign)
	bit	sgncmp		; fac=inf & arg=inf so check sign comparison
	bpl	?skp		; same sign so result=inf (fac sign)
	jsr	fldnan		; mismatch signs so result=nan (fac sign)
	bra	?skp		; skip resturn & exit with CF=1
?arg:	bit	argst		; fac is valid, so now check arg
	bmi	?mv		; arg=inf/nan so result=inf/nan (arg sign)
	clc			; now result is valid
	bvs	?skp		; arg=0 so result=fac
	bit	facst		; fac=0?
	bvc	?end		; no, return to add/sub operation
?mv:	jsr	mvatof		; move arg to fac (preserve CF)
?skp:	pla			; skip return address
	pla
?end:	rts

;---------------------------------------------------------------------------
; multiplication & division implementation - scaling routines
;---------------------------------------------------------------------------

; frexp - extracts the exponent from x.  It returns an integer
; power of two to scexp and the significand between 0.5 and 1 to fac
;
; 	entry:
;		fac 	= x (valid float)
;
;	exit:
;		fac 	= y (0.5 <= y < 1)
;		scexp	= N, exponent (signed integer)
;		scsgn	= sign of N
;		dexp	= |N| (absolute value of N)
;
;	note that:
;			 N
;		x = y * 2
;
;-----
frexp:
;-----
	sec
	bit	facst
	bmi	?end		; invalid fac	
	ACC16
	stz	scexp
	stz	dexp
	stz	wftmp
	ldx	#0		; assume positive sign
	lda	facexp
	beq	?s		; fac=0 so return exponent=0	
	dec	a		; subnormal?
	bne	?fn		; no
	ldx	facm+15
	bmi	?fn		; fac is norml
	sta	facexp		; clear to get negative exponent of subnormal
	ldx	#facm
	jsr	shlmx		; normalize subnormal fac
	lda	facexp
	sta	wftmp		; negative exponent of subnormal
	lda	#1		; restore biased exponent
	sta	facexp
?fn:	sec			; scale a normal f.p.
	lda	facexp
	sbc	#EBIAS-1	; new biased exponent
	clc
	adc	wftmp		; any subnormal negative exponent
	sta	scexp
	bpl	?p
	dex
	eor	#$FFFF
	inc	a		; return absolute value too
?p:	sta	dexp	
	lda	#EBIAS-1
	sta	facexp		; now 0.5 <= fac < 1
?s:	stx	scsgn		; exponent sign
	ACC08
	clc
?end:	rts

; fscale - multiplies argument by a power of two
;
; 	entry:
;		fac 	= x (valid float)
;		scexp	= N (signed integer)
;
;	exit:
;			       N
;		fac	= x * 2
;		CF      = 1 if invalid result(inf or nan)
;
;------
fscale:
;------
	sec			; invalid fac flag
	bit	facst
	bmi	?end2		; fac is invalid
	bvs	?end1		; fac=0
	ACC16
	lda	scexp
	beq	?end		; scale factor = 0
	lda	facexp
	dec	a
	bne	?fn		; fac is normal
	ldx	facm+15
	bmi	?fn		; fac is normal
	lda	scexp
	bpl	?ps		; positive scaling of subnormal
	bmi	?ns		; negative scaling of subnormal
?sn:	lda	facexp
?sn2:	stz	facexp		; set biased exponent=1
	inc	facexp
	dec	a		; count of right shift
?ns:	cmp	#MAXBSHIFT
	bcc	?z		; return fac=0
	ACC08
	ldx	#facm		; shift right
	jsr	shrmx
	jmp	chkz		; underflow test
	.LONGA	on
?ps:	ldx	facm+15		; shift subnormal toward left
	bmi	?fn
	asl	facm
	rol	facm+2
	rol	facm+4
	rol	facm+6
	rol	facm+8
	rol	facm+10
	rol	facm+12
	rol	facm+14
	dec	scexp
	bne	?ps
?end:	ACC08			; return
?end1:	clc
?end2:	rts
?z:	ACC08			; return fac=0
	jmp	fldz
	.LONGA	on
?fn:	stz	wftmp		; 32 bit exponent sign extension
	lda	scexp
	bpl	?p
	dec	wftmp		; scexp is negative
?p:	clc
	lda	facexp
	adc	scexp
	sta	facexp
	lda	#0
	adc	wftmp		; can be just negative or null
	bmi	?sn		; handle subnormal result
	lda	facexp
	beq	?sn2		; handle subnormal result
	cmp	#INFEXP		; overflow?
	bcc	?end		; no
	ACC08
	jmp	fldinf

	.LONGA	off
	
; scale10 - multiplies argument by a power of ten
;
; 	entry:
;		fac 	= x (valid float)
;		C	= N (signed integer)
;
;	exit:
;			        N
;		fac	= x * 10
;		CF      = 1 if invalid result(inf or nan)
;
; A lookup table  is used for values  from  10  through  10^7,
; then this is augmented by multiplying with  table entries 
; for  10^8/16/32/64/128/256/512/1024/2048/4096 which allows
; any power up. Negative powers are provided by a final division.
;
;-------
scale10:
;-------
	sec
	bit	facst		; valid fac?
	bmi	?end2		; no, exit
	bvs	?end1		; fac=0, exit
	ACC16
	cmp	#0
	beq	?end		; scaling exponent=0 so exit
	sta	scexp		; scaling exponent
	ldx	#0
	ldy	scexp+1		; test sign
	bpl	?pe		; positive exponent
	txa			; change sign
	dex
	sec
	sbc	scexp
	sta	scexp
?pe:	stx	scsgn		; store sign
?lp1:	cmp	#4096		; loop for big scaling
	ACC08
	bcc	?sc		; scaling<4096
	lda	#<fce4096
	ldy	#>fce4096
	bit	scsgn		; if negative svaling...
	bmi	?div		; ...divide...
	jsr	fcmult		; ...else multiplies by 4096
	bcs	?end2		; overflow, so exit
	bcc	?cnt		; continue
?div:	jsr	fcrdiv		; divide by 4096
	bcs	?end2
	bit	facst		; if fac=0 exit
	bvs	?end2
?cnt:	ACC16			; update scaling factor...
	sec
	lda	scexp
	sbc	#4096		; ...subtracting 4096...
	sta	scexp
	bne	?lp1		;...and repeat
?end:	ACC08
?end1:	clc
?end2:	rts
?sc:	jsr	mvf_t0		; save fac (tfr0=fac) in temp. reg.
	lda	scexp		; now decomposes scexp in factor...
	and	#7		; this for component from 1 to 1e7
	asl	a
	tax
	lda	>fcaddr+1,x
	tay
	lda	>fcaddr,x
	jsr	ldfac		; load fac with a constant from 1.0 to 1.0e7
	CPU16
	lda	#!fce8		; now find the high order factor...
	sta	fcp		; ...from 1.0e8 to 1.0e2048
	lda	scexp
	lsr	a		; divide by 8
	lsr	a
	lsr	a
	beq	?done		; if = 0 we are done
?lp2:	lsr	a		; divide by 2 high order bits
	bcc	?nxt		; if even load next constant
	sta	scexp		; save scale
	CPU08
	jsr	fcmult2		; multiplies by constant
	bcc	?ok
	bit	scsgn
	bpl	?end2		; overflow: fac=inf
	jmp	fldz		; underflow: fac=0
?ok:	CPU16
	lda	scexp
?nxt:	tax			; update pointer to next constant	
	lda	fcp
	adc	#FCSIZ
	sta	fcp
	txa
	bne	?lp2		; loop
?done:	CPU08
	jsr	mvt0_a		; move temp. reg. tfr0 to arg
	bit	scsgn
	bmi	fpdiv		; if negative scaling we divide arg by fac
	bra	fpmult		; if positive scaling we multiplies arg by fac

; fsquare - return the square of the argument
;
;	entry:
;		fac = x
;
;	exit:	       2
;		fac = x
;		CF  = 1 if invalid result(inf or nan)
;
;-------
fsquare:
;-------
	jsr	mvftoa		; move fac to arg
	bra	fpmult		; fac*fac

; mult10 - multiplies the argument with 10.0
;
;	entry:
;		fac = x
;
;	exit:
;		fac = x * 10
;
; This routine is used internally and not intended for end use.
;
;------
mult10:
;------
	lda	#<fce1		; address of constant = 10.0
	ldy	#>fce1

; fcmult - multiplies the argument with one constant stored in program memory
;
;	entry:
;		fac = x
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		fac = K * x
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;------
fcmult:
;------
	jsr	ldarg		; load arg with constant K
	bra	fpmult		; execute multiplication

; fcmult2 - multiplies the argument with one constant stored in program memory
;
;	entry:
;		fac = x
;		fcp = long pointer to constant K
;
;	exit:
;		fac = K * x
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;-------
fcmult2:
;-------
	jsr	ldarg2		; load arg with constant K

; fpmult - multiplies operands stored in arg & fac
; main multiplication routine
;
;	entry:
;		arg = x
;		fac = y
;
;	exit:
;		fac = x * y
;		CF  = 1 if invalid result(inf or nan)
;
;------
fpmult:
;------
	jsr	multst		; operands test
	clc			; multiplication flag for addexp
	jsr	addexp		; add exponent's
	CPU16			; clear the partial result
	stz	tm
	stz	tm+2
	stz	tm+4
	stz	tm+6
	stz	tm+8
	stz	tm+10
	stz	tm+12
	stz	tm+14	
	jsr	multm		; execute binary multiplication
	CPU08
	bra	movres		; move result to fac & normalize

; frecip - returns the reciprocal of the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = 1/x
;		CF  = 1 if invalid result(inf or nan)
;
;------
frecip:
;------
	lda	#<fce0		; load arg with constant 1.0
	ldy	#>fce0

; fcdiv - divide one constant stored in program memory by the argument
;
;	entry:
;		fac = x
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		fac = K / x
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;-----
fcdiv:
;-----
	jsr	ldarg		; move constant K to arg
	bra	fpdiv		; execute arg/fac

; div10 - divide the argument by 10.0
;
;	entry:
;		fac = x
;	exit:
;		fac = x / 10
;
; This routine is used internally and not intended for end use.
;
;-----
div10:
;-----
	lda	#<fce1		; address of constant = 10.0
	ldy	#>fce1

; fcrdiv - divide the argument by one constant stored in program memory
;
;	entry:
;		fac = x
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		fac = x / K
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;------
fcrdiv:
;------
	jsr	mvftoa		; nove fac to arg
	jsr	ldfac		; move constant to fac

; fpdiv - divide the argument stored in arg by the argument stored in fac
;
;	entry:
;		arg = x
;		fac = y
;
;	exit:
;		fac = x / y
;		CF  = 1 if invalid result(inf or nan)
;
;-----
fpdiv:
;-----
	jsr	divtst		; operands test
	sec			; flag division for addexp
	jsr	addexp		; add operands exponent
	jsr	divm		; binary division
	
; movres - move the result of multiplication/division to fac & normalize
;
; This routine is used internally and not intended for end use.
;
;------
movres:
;------
	ACC16
	lda	tm		; move the result (16 bytes) to fac
	sta	facm
	lda	tm+2
	sta	facm+2
	lda	tm+4
	sta	facm+4
	lda	tm+6
	sta	facm+6
	lda	tm+8
	sta	facm+8
	lda	tm+10
	sta	facm+10
	lda	tm+12
	sta	facm+12
	lda	tm+14
	sta	facm+14
	ACC08
	lda	fexph		; operation involved subnormal?
	beq	?fn		; no
	ldx	#facm		; now should shift to right fac...
	jsr	shrmx		; ...because fac is subnormal
?tz:	jmp	chkz		; underflow test; check if fac=0
?fn:	ACC16			; normalize fac after mult/div	
	lda	facexp
	cmp	#1
	beq	?tz		; can't normalize: underflow test
	ldx	facm+15		; check msb
	bmi	?done		; already normalized
?sh:	cmp	#1
	beq	?done		; can't shift more
	dec	a		; decrement exponent at any shift
	asl	facext
	rol	facm
	rol	facm+2
	rol	facm+4
	rol	facm+6
	rol	facm+8
	rol	facm+10
	rol	facm+12
	rol	facm+14	
	bpl	?sh		; shift until msb=1
?done:	sta	facexp		; store exponent
	cmp	#INFEXP		; check if overflow
	bcs	ovfw		; overflow
	ldx	facext+1	; if msb=1 we round 128 bits mantissa
	bpl	ifx		; no rounding bit: done
	jsr	chkovf		; we check exponent for a potential overflow
	bcs	ifx		; no round is possible (we avoid overflow)	
	inc	facm		; inc. 15 guard bits and significand lsb
	bne	ifx

; incfac - increment the high order 96 bits of the fac significand
; Called when round fac mantissa
;
; This routine is used internally and not intended for end use.
;
;------
incfac:
;------
	inc	facm+2
	bne	ifx
	inc	facm+4
	bne	ifx
	inc	facm+6
	bne	ifx
	inc	facm+8
	bne	ifx
	inc	facm+10
	bne	ifx
	inc	facm+12
	bne	ifx
	inc	facm+14
	bne	ifx
	CPU08
	jmp	addcf		; add carry to significand, no overflow
ifx:	CPU08
	clc
	rts

; set fac=inf
;----
ovfw:
;----
	CPU08			; overflow
	jmp	fldinf

; chkovf - check potential fac overflow due to a roundoff
;
;	return CF=1 if a rounding can cause overflow
;
;	This routine should be called with A/M = 16 bit
;
; This routine is used internally and not intended for end use.
;
;------
chkovf:
;------
	.LONGA	on

	cmp	#MAXEXP		; we check exponent for possible overflow
	bcc	?end		; ok, no overflow after rounding
	lda	#$FFFF		; check if mantissa is all one's
	cmp	facm
	bne	?ok
	cmp	facm+2
	bne	?ok
	cmp	facm+4
	bne	?ok
	cmp	facm+6
	bne	?ok
	cmp	facm+8
	bne	?ok
	cmp	facm+10
	bne	?ok
	cmp	facm+12
	bne	?ok
	cmp	facm+14
?ok:	clc			; rounding is possible
	bne	?end
	sec			; no rounding possible 
?end:	rts
	
	.LONGA	off

; addexp - add exponent of fac & arg for multiplication/division
;
;	entry:
;		arg = x
;		fac = y
;		CF  = 1 if multiplication, else division
;
;	exit:
;		facexp = exponent of the result (x*y or x/y)
;		fexph  = negative exponent if result is subnormal,
;		         otherwise =0 if result is normal
;
; This routine is used internally and not intended for end use.
;
;------
addexp:
;------
	php			; save carry
	ACC16
	stz	fexph		; clear exponent sign extension 
	stz	aexph
	stz	facext		; extension used while mult/div
	lda	facm+14
	bmi	?a		; fac is norml
	ldx	#facm
	jsr	shlmx		; normalize subnormal fac
?a:	lda	argm+14
	bmi	?b		; arg is norml
	ldx	#argm
	jsr	shlmx		; normalize subnormal arg
?b:	plp			; restore carry	
	CPU16
	lda	argexp
	bcs	?div		; subtract exponent for division
	adc	facexp		; add exponent with sign extension
	tax
	lda	aexph
	adc	fexph
	tay
	sec
	txa
	sbc	#EBIAS-1	; adjust biased exponent for mult
	tax
	tya
	sbc	#0
	bra	?tst		; check exponent
?div:	sbc	facexp		; subtract exponent with sign extension
	tax
	lda	aexph
	sbc	fexph
	tay
	clc
	txa
	adc	#EBIAS		; adjust biased exponent
	tax
	tya
	adc	#0
?tst:	bmi	?sn		; negative exponent so result is subnormal
	txa
	beq	?sn		; null exponent so result is subnormal
	sta	facexp		; exp >= 1 so result is normal
	stz	fexph
	bra	?done
?sn:	dex			; negative count of shift toward right
	cpx	#MAXBSHIFT-1
	bcc	?z		; underflow: set fac=0
	stx	fexph		; negative count of shift
	lda	#1
	sta	facexp		; subnormasl have exponent=1
?done:	CPU08
	rts
?z:	CPU08			; underflow: load zero into fac...
	pla			; ...and exit
	pla
	jmp	fldz

; multm - binary multiplication of the arg mantissa with fac mantissa
;
; classic binary multiplication "shift and add" method
; only high order 144 bits of 256 are retained in result
; Due the fact that facm and argm are normalized, the result is
; always between 1.000000... and 2.ffffff....
;
; should be called with A/M=16 bits, X/Y=16 bits
;
; This routine is used internally and not intended for end use.
;
;-----
multm:
;-----
	.LONGA	on
	.LONGI	on

	lda	facm		; multiply any word of facm with whole argm
	jsr	?mlt
	lda	facm+2
	jsr	?mlt
	lda	facm+4
	jsr	?mlt
	lda	facm+6
	jsr	?mlt
	lda	facm+8
	jsr	?mlt
	lda	facm+10
	jsr	?mlt
	lda	facm+12
	jsr	?mlt
	lda	facm+14		; multiply msb that never is null
	bra	?mlt2	
?mlt:	beq	?shr		; if null shift right partial result (16 bit)
?mlt2:	lsr	a		; multiplicator bit
	ora	#$8000		; bit for stop iteration (16 cycles)
?lp:	tay
	bcc	?sh		; multiplicator=0 so shift result to right
	clc
	lda	tm		; add multiplicand to partial result
	adc	argm
	sta	tm
	lda	tm+2
	adc	argm+2
	sta	tm+2
	lda	tm+4
	adc	argm+4
	sta	tm+4
	lda	tm+6
	adc	argm+6
	sta	tm+6
	lda	tm+8
	adc	argm+8
	sta	tm+8
	lda	tm+10
	adc	argm+10
	sta	tm+10
	lda	tm+12
	adc	argm+12
	sta	tm+12
	lda	tm+14
	adc	argm+14
	sta	tm+14
?sh:	ror	tm+14		; shift any carry into partial result...
	ror	tm+12		; ...and shift partial result toward right
	ror	tm+10	
	ror	tm+8
	ror	tm+6
	ror	tm+4
	ror	tm+2
	ror	tm
	ror	facext		; greater accuracy with this extension
	tya
	lsr	a		; end of loop when null
	bne	?lp
	rts			; always return CF=1
	
?shr:	lda	tm		; shift partial result toward right...
	sta	facext		; ...16 bit at time
	lda	tm+2
	sta	tm
	lda	tm+4
	sta	tm+2
	lda	tm+6
	sta	tm+4
	lda	tm+8
	sta	tm+6
	lda	tm+10
	sta	tm+8
	lda	tm+12
	sta	tm+10
	lda	tm+14
	sta	tm+12
	stz	tm+14
	rts
	
	.LONGA	off
	.LONGI	off

; divm - computes the division of the arg mantissa by fac mantissa
;
; Classic fixed point division, that use the recurrence equation:
;
;	R    =  2*R  -  D*Q  
;	 j+1	   j       n-(j+1)	
;
;	R   =  V  ,  Q    = 1 if V >= D
;	 0            n-1
;
; where: V=dividend, D=divisor, R  = partial remainder, Q  is the k-th
;			         j			 k
;
; bit of the quotient, starting from the msb: k=n-(j+1), 
; n=130 is the quotient size, j=1..n-1 is the loop index.
; Only 130 bits of quotient are retained.
;
; Due the fact that facm and argm are normalized, the result is
; always between 0.100000... and 1.ffffff....
;
; This routine is used internally and not intended for end use.
;
;----
divm:
;----
	ldx	#MANTSIZ	; loop for all bytes of mantissa
	lda	#$01		; 8 bits quotient -- quotient = 0
?lp1:	jsr	?cmp		; compare argm vs. facm
?lp2:	php			; save carry (CF=1 if argm>=facm)
	rol	a		; shift in CF (quotient bit) into lsb
	bcc	?sub		; bits loop...stop when CF=1
	dex			; index of quotient array
	bmi	?done		; end of division
	sta	tm,x		; store this byte of quotient (start with msb)
	beq	?lst		; last quotient is 2 bits only
	lda	#$01		; 8 bits quotient -- quotient = 0
?sub:	plp			; restore CF from comparing argm vs. facm
	ACC16
	bcc	?sh		; quotient bit = 0: no subtraction
	tay			; save partial quotient: here CF=1
	lda	argm		; get the partial remainder...
	sbc	facm		; ...subtracting the divisor facm
	sta	argm
	lda	argm+2
	sbc	facm+2
	sta	argm+2
	lda	argm+4
	sbc	facm+4
	sta	argm+4
	lda	argm+6
	sbc	facm+6
	sta	argm+6
	lda	argm+8
	sbc	facm+8
	sta	argm+8
	lda	argm+10
	sbc	facm+10
	sta	argm+10
	lda	argm+12
	sbc	facm+12
	sta	argm+12
	lda	argm+14
	sbc	facm+14
	sta	argm+14
	tya			; restore partial quotient
?sh:	asl	argm		; now shift argm to left (one place)
	rol	argm+2
	rol	argm+4
	rol	argm+6
	rol	argm+8
	rol	argm+10
	rol	argm+12
	rol	argm+14
	ACC08
	bcs	?lp2		; CF=1: quotient bit = 1
	bmi	?lp1		; CF=0, MSB=1: compare again argm vs. facm
	bpl	?lp2		; CF=0, MSB=0: quotient bit = 0
?lst:	lda	#$40		; 2 last bits quotient for normalitation...
	bra	?sub		; ...and rounding
?done:	plp			; end of division
	asl	a		; last truncated quotient (00..03)...
	asl	a		; ...shifted to bits 15&14 of facext...
	asl	a		; ...to have greater accuracy...
	asl	a
	asl	a
	asl	a
	sta	facext+1	
	rts

?cmp:	ldy	argm+15		; comparation: arg mantissa vs. fac mantissa
	cpy	facm+15
	bne	?end
	ldy	argm+14
	cpy	facm+14
	bne	?end	
	ldy	argm+13
	cpy	facm+13
	bne	?end
	ldy	argm+12
	cpy	facm+12
	bne	?end
	ldy	argm+11
	cpy	facm+11
	bne	?end
	ldy	argm+10
	cpy	facm+10
	bne	?end
	ldy	argm+9
	cpy	facm+9
	bne	?end
	ldy	argm+8
	cpy	facm+8
	bne	?end
	ldy	argm+7
	cpy	facm+7
	bne	?end
	ldy	argm+6
	cpy	facm+6
	bne	?end
	ldy	argm+5
	cpy	facm+5
	bne	?end
	ldy	argm+4
	cpy	facm+4
	bne	?end
	ldy	argm+3
	cpy	facm+3
	bne	?end
	ldy	argm+2
	cpy	facm+2
	bne	?end
	ldy	argm+1
	cpy	facm+1
	bne	?end
	ldy	argm
	cpy	facm
?end:	rts

; multst - test operands before to execute multiplication
;
; This routine test fac & arg for validity, set the sign of the result,
; and return to the caller for any abnormal condition:
;
;	1) return nan if fac=nan or arg=nan
;	2) return +inf if fac=+inf and arg=+inf or arg>0
;	3) return +inf if fac=-inf and arg=-inf or arg<0
;	4) return -inf if fac=-inf and arg=+inf or arg>0
;	5) return -inf if fac=+inf and arg=-inf or arg<0
;	6) return +inf if arg=+inf and fac>0
;	7) return +inf if arg=-inf and fac<0
;	8) return -inf if arg=-inf and fac>0
;	9) return -inf if arg=+inf and fac<0
;      10) return nan if fac=+/-inf and arg=0
;      11) return nan if arg=+/-inf and fac=0
;
; This routine is used internally and not intended for end use.
;
;------
multst:
;------
	lda	facsgn		; compare sign
	eor	argsgn
	sta	facsgn		; set result sign
	sta	argsgn
	sec			; invalid result flag
	bit	facst		; test fac
	bpl	?fv		; fac is valid
	bvc	?skp		; fac=nan so result=nan
	bit	argst		; fac=inf so check arg
	bpl	?az		; fac=inf & arg=y so check if arg=0
	bvc	?mv		; fac=inf & arg=nan so result=nan
	bra	?skp		; fac=inf & arg=inf so result=inf
?az:	bvc	?skp		; fac=inf & arg not null so result=inf
	bra	?nan		; fac=inf & arg=0 so result=nan
?fv:	bit	argst		; fac is valid, so now check arg
	bpl	?vv		; arg too is valid
	bvc	?mv		; fac=x & arg=nan so result=nan
	bit	facst		; fac=x & arg=inf so check if fac=0
	bvc	?mv		; fac not null & arg=inf so result=inf
?nan:	jsr	fldnan		; fac=0 & arg=inf so result=nan
	bra	?skp		; skip resturn & exit with CF=1
?vv:	clc			; now result is valid
	bvs	?mv		; arg=0 so result=0
	bit	facst		; fac=0?
	bvc	?end		; no, return to mult operation
	jsr	fldz		; result=0 (with CF=0)
	bra	?skp
?mv:	jsr	mvatof		; move arg to fac (preserve CF)
?skp:	pla			; skip return address
	pla
?end:	rts

; divtst - test operands before to execute division
;
; This routine test fac & arg for validity, set the sign of the result,
; and return to the caller for any abnormal condition:
;
;	1) return nan if fac=nan or arg=nan
;	2) return nan if fac=0 and arg=0
;	3) return nan if fac=+/-inf and arg=+/-inf
;	4) return +inf if arg=+inf and fac>=0
;	5) return +inf if arg=-inf and fac<0
;	6) return -inf if arg=-inf and fac>=0
;	7) return -inf if arg=+inf and fac<0
;	8) return +inf if arg>0 and fac=0
;	9) return -inf if arg<0 and fac=0
;      10) return 0 if arg=0 and fac=+/-inf
;
; This routine is used internally and not intended for end use.
;
;------
divtst:
;------
	lda	facsgn		; compare sign
	eor	argsgn
	sta	facsgn		; set result sign
	sta	argsgn
	sec			; invalid result flag
	bit	facst		; test fac
	bpl	?fv		; fac is valid
	bvc	?skp		; fac=nan so result=nan
	bit	argst		; fac=inf so check arg
	bmi	?nan		; fac=inf & arg=inf/nan so result=nan
	bra	?z		; fac=inf & arg=y so result=0	
?fv:	lda	argst		; fac is valid, so now check arg
	bmi	?mv		; fac=x & arg=nan/inf so result=nan/inf
	and	facst
	asl	a		; both null?
	bmi	?nan		; yes so result=nan
	bit	facst
	bvs	?inf
	bit	argst
	bvc	?end
?z:	jsr	fldz		; result=0 (with CF=0)
	bra	?skp
?nan:	jsr	fldnan		; fac=0 & arg=0 so result=nan
	bra	?skp		; skip resturn & exit with CF=1	
?inf:	jsr	fldinf
	bra	?skp
?mv:	jsr	mvatof		; move arg to fac (preserve CF)
?skp:	pla			; skip return address
	pla
?end:	rts

;---------------------------------------------------------------------------
; pack/unpack to/from 128 bit quadruple-precision IEEE format
; these routines convert to/from internal format from/to std. IEEE format
;---------------------------------------------------------------------------

; frndm - round 128-bit fac mantissa to 113-bit mantissa 
;
; standard rounding method: round to nearest and tie to even
;
; let G = (guard bits)*2 and L = lsb significand:
;
;	if G < $8000 then round down (truncate)
;	if G > $8000 then round up
;	if G = $8000 then 'tie even':
;		if L = 0 then round down (truncate)
;		         else round up
;
; if exponent equal to $7FFE and mantissa is all 1's, no round up take place, 
; to avoid ovorflow
;
; The main use of this routine is to round fac before to convert to IEEE
; format, but can be called after any operation (of course losing guard bits)
;
;-----
frndm:
;-----
	CPU16
	lda	facm		; check guard bits
	tax			; retain guard bits (G)
	and	#$8000		; mask bit 15 (significand lsb)
	sta	facm		; clear guard bits (G)
	tay			; Y=lsb significand (L)
	beq	?rnd		; if bit 15=0 always possible to round up
	lda	facexp		; we check exponent for possible overflow
	jsr	chkovf
	bcs	?done		; no round is possible (avoid overflow)	
?rnd:	txa			; check guard bits
	asl	a
	cmp	#$8000
	bcc	?done		; G < $8000 so round down (truncate)
	bne	?cf		; G > $8000 so round up (CF=1 here)
	tya			; G = $8000 so check L (lsb significand)
	bpl	?done		; if L=0 round down -- tie even (truncate)
?cf:	tya			; here CF=1 -- round up
	adc	#$7FFF		; really add $8000
	sta	facm		; lsb sigificand
	bcs	?inc		; mantissa increment, because carry from lsb
?done:	CPU08
	rts
?inc:	jmp	incfac		; now this increment never cause overflow


; pack - pack fac & store in memory in std. quadruple precision IEEE format
;
; Main routine to store in memory a floating point number
;
;	entry:
;		fac = float point
;		A   = low  memory address
;		X   = high memory address
;		Y   = memory bank
;
;	exit:
;		quadruple precision stored in memory
;
; This routine round 128-bit fac mantissa to 113-bit mantissa, pack to
; quadruple precision IEEE standard format, and store it in memory
;
;-----
fpack:
;-----
	sta	fcp		; set long pointer to memory buffer
	stx	fcp+1
	sty	fcp+2
	jsr	frndm		; round fac to 113 bit mantissa
	ACC16
	lda	facm
	asl	a		; rotate lsb of packed format
	lda	facm+2		; rotate all remaining 112 bits...
	rol	a
	sta	[fcp]		; ...and store
	lda	facm+4
	rol	a
	ldy	#2
	sta	[fcp],y
	lda	facm+6
	rol	a
	ldy	#4
	sta	[fcp],y
	lda	facm+8
	rol	a
	ldy	#6
	sta	[fcp],y
	lda	facm+10
	rol	a
	ldy	#8
	sta	[fcp],y
	lda	facm+12
	rol	a
	ldy	#10
	sta	[fcp],y
	lda	facm+14
	rol	a		; CF = hidden bit (msb)
	ldy	#12
	sta	[fcp],y	
	lda	facexp
	bcs	?fn		; CF=1 mean normal float
	lda	#0		; subnormal float or zero
?fn:	ldx	facsgn
	bpl	?exp		; positive float
	ora	#$8000		; negative float
?exp:	ldy	#14
	sta	[fcp],y
	ACC08
	rts

; unpack - get a quadruple precision IEEE format from memory and store in fac
;
; Main routine to load fac with a floating point number stored in memory
;
;	entry:
;		A   = low  memory address
;		X   = high memory address
;		Y   = memory bank
;
;	exit:
;		fac = floating point number in internal fortmat
;
;
;-------
funpack:
;-------
	sta	fcp		; set long pointer to memory buffer
	stx	fcp+1
	sty	fcp+2
	ACC16CLC		; CF=0: assume hidden bit = 0
	ldx	#0		; assume positive sign
	ldy	#14
	lda	[fcp],y		; exponent
	bpl	?fp		; positive float
	dex			; negative float
?fp:	stx	facsgn
	ldx	#$00		; assume normal float
	and	#$7FFF		; mask off sign
	sta	facexp
	beq	?get		; zero or subnormal (msb=0)
	sec			; hidden bit: msb=1
?get:	ldy	#12
	lda	[fcp],y		; significand
	ror	a		; rotate in hidden bit...
	sta	facm+14		; ...then rotate all 112 bits...
	ldy	#10		; ...and store to fac mantissa
	lda	[fcp],y
	ror	a
	sta	facm+12
	ldy	#8
	lda	[fcp],y
	ror	a
	sta	facm+10
	ldy	#6
	lda	[fcp],y
	ror	a
	sta	facm+8
	ldy	#4
	lda	[fcp],y
	ror	a
	sta	facm+6
	ldy	#2
	lda	[fcp],y
	ror	a
	sta	facm+4
	lda	[fcp]
	ror	a
	sta	facm+2
	txa			; shift in lsb
	ror	a		; <14:0> are all zero (guard bits)
	sta	facm
	lda	facexp		; check exponent
	beq	?chkz		; if exp=0 check if fac=0	
	cmp	#INFEXP
	bcc	?st		; valid float, set status
	lda	#INFEXP
	sta	facexp		; fac=inf or fac=nan
	ldx	#$C0		; assume inf
	lda	facm+14		; check type
	cmp	#INFSND
	beq	?st		; set inf in fac stastus
	ldx	#$80		; set nan in fac status
	bra	?st
?chkz:	lda	facm		; exponent is zero: check if fac=0
	ora	facm+2
	ora	facm+4
	ora	facm+6
	ora	facm+8
	ora	facm+10
	ora	facm+12
	ora	facm+14
	bne	?sn		; fac is subnormal
	ldx	#$40		; fac is zero
	bra	?st
?sn:	inc	facexp		; subnormal exponent = 1
?st:	stx	facst		; set fac status
	ACC08
	rts

;---------------------------------------------------------------------------
; load fac & arg with special values
;---------------------------------------------------------------------------

; fldp1 - load the constant +1.0 into fac
;
;	exit:
;		fac = +1.0
;
;-----
fldp1:
;-----
	stz	facsgn
	bra	fld1

; fldm1 - load the constant -1.0 into fac
;
;	exit:
;		fac = -1.0
;
;-----
fldm1:
;-----
	lda	#$FF
	sta	facsgn

;----
fld1:
;----
	ACC16
	lda	#EBIAS
	sta	facexp
	lda	#$8000
	sta	facm+14	
	stz	facm
	stz	facm+2
	stz	facm+4
	stz	facm+6
	stz	facm+8
	stz	facm+10
	stz	facm+12
	ACC08
	stz	facst
	clc
	rts

; fldz - load the constant 0.0 into fac
;
;	exit:
;		fac = 0.0
;
;----
fldz:
;----
	ACC16
	stz	facm+14	
	stz	facexp
	stz	facm
	stz	facm+2
	stz	facm+4
	stz	facm+6
	stz	facm+8
	stz	facm+10
	stz	facm+12
	ACC08
	stz	facsgn
	lda	#$40
	sta	facst
noer:	clc
	rts

; fldnan - set fac=nan
;------
fldnan:
;------
	ACC16
	lda	#NANSND
	ldx	#$80		; nan flag
	bra	fldinv

; fldinf - set fac=inf
;------
fldinf:
;------
	ACC16
	lda	#INFSND
	ldx	#$C0		; inf flag

fldinv:
	sta	facm+14		; set msb
	lda	#INFEXP		; set invalid exponent
	sta	facexp
	stz	facm+12
	stz	facm+10
	stz	facm+8
	stz	facm+6
	stz	facm+4
	stz	facm+2
	stz	facm
	ACC08
	stx	facst
	sec			; return error condition
	rts

; ldahalf - load the constant 0.5 into arg
;
;	exit:
;		arg = 0.5
;
;-------
ldahalf:
;-------
	ACC16
	lda	#EBIAS-1
	bra	amsb

; ldaone - load the constant +1.0 into arg
;
;	exit:
;		arg = +1.0
;
;------
ldaone:
;------
	ACC16
	lda	#EBIAS
	bra	amsb

; ldatwo - load the constant +2.0 into arg
;
;	exit:
;		arg = +2.0
;
;------
ldatwo:
;------
	ACC16
	lda	#EBIAS+1

amsb:
	sta	argexp		; store exponent
	lda	#$8000
	sta	argm+14		; high word = $8000
	stz	argm		; reset all remaining bits
	stz	argm+2
	stz	argm+4
	stz	argm+6
	stz	argm+8
	stz	argm+10
	stz	argm+12
	stz	argsgn		; positive sign
	ACC08
	clc	
	rts

;---------------------------------------------------------------------------
; conversion from integer to float & from float to integer
;---------------------------------------------------------------------------

; fldu128 - load fac with an unsigned 128 bit integer (n)
;
;	entry:
;		tm..tm+15 = n, unsigned 128 bit integer
;
;	exit:
;		fac = n
;
;-------
fldu128:
;-------
	jsr	fldz		; set fac=0
	stz	facsgn
	ACC16
	lda	tm+14		; load 128 bit value
	sta	facm+14
	lda	tm+12
	sta	facm+12
	lda	tm+10
	sta	facm+10
	lda	tm+8
	sta	facm+8
	lda	tm+6
	sta	facm+6
	lda	tm+4
	sta	facm+4
	lda	tm+2
	sta	facm+2
	lda	tm
	sta	facm
	ora	facm+2		; test if n=0
	ora	facm+4
	ora	facm+6
	ora	facm+8
	ora	facm+10
	ora	facm+12
	ora	facm+14
	beq	okz		; n=0
	lda	#BIAS128	; biased exponent for 128 bit value	
	bra	fldu

	.LONGA	off

; fldu64 - load fac with an unsigned 64 bit integer (n)
;
;	entry:
;		tm..tm+7 = n, unsigned 64 bit integer
;
;	exit:
;		fac = n
;
;------
fldu64:
;------
	jsr	fldz		; set fac=0
	stz	facsgn
	ACC16
	lda	tm+6		; load 64 bit value
	sta	facm+14
	lda	tm+4
	sta	facm+12
	lda	tm+2
	sta	facm+10
	lda	tm
	sta	facm+8
	ora	facm+10		; test if n=0
	ora	facm+12
	ora	facm+14
	beq	okz		; n=0
	lda	#BIAS64		; biased exponent for 64 bit value	
	bra	fldu

	.LONGA	off

okz:	ACC08
	clc
	rts

; fldu32 - load fac with an unsigned 32 bit integer (n)
;
;	entry:
;		tm..tm+3 = n, unsigned 32 bit integer
;
;	exit:
;		fac = n
;
;------
fldu32:
;------
	jsr	fldz		; set fac=0
	stz	facsgn
	ACC16
	lda	tm+2
	sta	facm+14		; load 32 bit value
	lda	tm
	sta	facm+12
	ora	facm+14		; test if n=0
	beq	okz		; n=0
	lda	#BIAS32		; biased exponent for 32 bit value	
	bra	fldu

	.LONGA	off

; fldbyt - load fac with an unsigned 8 bit integer (n)
;
;	entry:
;		A = n, unsigned 8 bit integer
;
;	exit:
;		fac = n
;
;------
fldbyt:
;------
	tax			; save A
	jsr	fldz		; set fac=0
	stz	facsgn
	txa
	beq	okz		; n=0	
	stx	facm+15		; put byte in high order bits
	ACC16
	lda	#BIAS8		; biased exponent for 8 bit value
	bra	fldu

	.LONGA	off
	
; fldu16 - load fac with an unsigned 16 bit integer (n)
;
;	entry:
;		A = low  8 bit of n, unsigned 16 bit integer
;		Y = high 8 bit of n, unsigned 16 bit integer
;
;	exit:
;		fac = n
;
;------
fldu16:
;------
	tax			; save A
	jsr	fldz		; set fac=0
	stx	facm+14		; low 8 bit
	sty	facm+15		; high 8 bit
	stz	facsgn
	txa
	ora	facm+15		; test if n=0
	beq	okz		; n=0		
	ACC16
	lda	#BIAS16		; biased exponent for 16 bit value

;----	
fldu:
;----
	sta	facexp		; store exponent
	ACC08
	stz	facst		; normal fac <> 0
	jmp	normfac		; normalize fac

; uitrunc - convert the integral part of fac to unsigned 128 bit integer
;
; this routine truncate toward zero, and ignore fac sign
;
;	entry:
;		fac = x
;
;	exit:
;		tm..tm+15 = unsigned 128 bit integer = integral part of |x|
;		CF = 1 if the integral part of |x| not fit in 128 bit
;
; In overflow condition, or if fac=nan/inf, tm..tm+15 will be filled with
; the max. 128 bit value and the carry flag will be set.
;
;-------
uitrunc:
;-------
	bit	facst		; valid fac?
	bpl	?fv		; yes
	ACC16			; set tm..tm+15 to max.
?ovf:	sec			; invalid flag
	lda	#$FFFF		; set max.
	bra	?set
?z:	lda	#0
?z1:	clc			; valid flag
?set:	sta	tm
	sta	tm+2
	sta	tm+4
	sta	tm+6
	sta	tm+8
	sta	tm+10
	sta	tm+12
	sta	tm+14
	ACC08
	rts
?fv:	ACC16
	bvs	?z		; fac=0, so return tm=0
	lda	facexp
	beq	?z1		; fac=0, so return tm=0
	sec
	sbc	#EBIAS		; unbias exponent
	bcc	?z		; fac<1, so return tm=0
	cmp	#MNTBITS	; limit to 128 bit integer
	bcs	?ovf		; 128 bits integer overflow
	sbc	#MNTBITS-2	; take in account CF=0 here
	tax			; A=X=negative count of shift toward right
	lda	facm		; move fac mantissa to tm
	sta	tm
	lda	facm+2
	sta	tm+2
	lda	facm+4
	sta	tm+4
	lda	facm+6
	sta	tm+6
	lda	facm+8
	sta	tm+8
	lda	facm+10
	sta	tm+10
	lda	facm+12
	sta	tm+12
	lda	facm+14
	sta	tm+14
	ACC08
	txa			; A=negative count of shift toward right
	beq	?done		; no shift so exit
	ldx	#tm		; shift tm..tm15 toward right
	jsr	shrmx		; align integer with exponent
?done:	clc
	rts

;---------------------------------------------------------------------------
; rounding routines
;---------------------------------------------------------------------------	

; fceil - returns the smallest f.p. integer greater than or equal the argument
;
; This routine truncates toward plus infinity
;
;	entry:
;		fac = x
;
; 	exit:
;		fac = y = integral part of x truncated toward plus infinity
;		CF = 1 if invalid result(inf or nan)
;
;	fceil(3.0)  =  3.0
;	fceil(2.3)  =  3.0
;	fceil(0.5)  =  1.0
;	fceil(-0.5) =  0.0
; 	fceil(-2.3) = -2.0
; 	fceil(-3.0) = -3.0
;
;-----
fceil:
;-----
	bit	facst
	bpl	?fv		; fac is valid
	sec			; return invalid flag
	rts
?fv:	bvc	?nz		; fac <> 0
	stz	facsgn		; return fac=0
	clc
	rts
?nz:	lda	facsgn
	eor	#$FF		; fceil(x)=-floor(-x)
	sta	facsgn
	jsr	floor
	lda	facsgn
	eor	#$FF
	sta	facsgn
	rts

; fround - returns the integral value that is nearest to ergument x, 
; with halfway cases rounded away from zero.
;
; This routine truncates toward the nearest integer value
;
;	entry:
;		fac = x
;
; 	exit:
;		fac = y = integral part of x truncated toward the nearest
;		CF = 1 if invalid result(inf or nan)
;
;	fround(3.8)   =   4.0
;	fround(3.4)   =   3.0
;	fround(0.5)   =   1.0
;	fround(0.4)   =   0.0
;	fround(-0.4)  =   0.0
;	fround(-0.5)  =  -1.0
;	fround(-3.4)  =  -3.0
;	fround(-3.8)  =  -4.0
;
;------
fround:
;------
	bit	facst
	bpl	?fv		; fac is valid
	sec			; return invalid flag
?ret:	rts
?fv:	bvc	?nz		; fac <> 0
	stz	facsgn		; return fac=0
	clc
	rts
?nz:	lda	facsgn
	pha			; save fac sign
	stz	facsgn
	jsr	faddhalf	; |x|+0.5
	pla
	sta	facsgn		; restore fac sign
	bcs	?ret		; overflow

	; return sign(x)*ftrunc(|x|+0.5)
	bmi	fceil		; ftrunc(x)=fceil(x) if x<0
	bra	floor		; ftrunc(x)=floor(x) if x>0
	
; ftrunc - returns the nearest integral value that is not larger 
; in magnitude than the argument x.
;
; This routine truncates toward zero
;
;	entry:
;		fac = x
;
; 	exit:
;		fac = y = integral part of x truncated toward zero
;		CF = 1 if invalid result(inf or nan)
;
;	ftrunc(3.0)  =  3.0
;	ftrunc(2.3)  =  2.0
;	ftrunc(0.5)  =  0.0
;	ftrunc(-0.5) =  0.0
; 	ftrunc(-2.3) = -2.0
; 	ftrunc(-3.0) = -3.0
;
;------
ftrunc:
;------
	bit	facst
	bpl	?fv		; fac is valid
	sec			; return invalid flag
	rts
?fv:	bvc	?nz		; fac <> 0
	stz	facsgn		; return fac=0
	clc
	rts
?nz:	lda	facsgn
	bmi	fceil		; ftrunc(x)=fceil(x) if x<0
				; ftrunc(x)=floor(x) if x>0
				
; floor - returns the largest f.p. integer less than or equal to the argument
;
; This routine truncates toward minus infinity
;
;	entry:
;		fac = x
;
; 	exit:
;		fac = y = integral part of x truncated toward minus infinity
;		CF = 1 if invalid result(inf or nan)
;
;	floor(3.0)  =  3.0
;	floor(2.3)  =  2.0
;	floor(0.5)  =  0.0
;	floor(-0.5) = -1
; 	floor(-2.3) = -3.0
; 	floor(-3.0) = -3.0
;
;-----
floor:
;-----
	bit	facst
	bpl	?fv		; fac is valid
	sec			; return invalid flag
	rts
?fv:	bvc	?nz		; fac <> 0
	stz	facsgn		; return fac=0
	clc
	rts
?nz:	jsr	frndm
	ACC16
	lda	facexp
	sec
	sbc	#EBIAS
	sta	wftmp		; save unbiased exponent
	ACC08
	bcs	?gt1		; |fac|>=1
	bit	facsgn
	bmi	?m1		; if -1<fac<0 return fac=-1...
	jmp	fldz		; ...else return fac=0
?m1:	jmp	fldm1		; return fac=-1
?gt1:	jsr	mvftoa		; move fac to arg for later comparation	
	ACC16			; here CF=1
	lda	#SNBITS-1
	sbc	wftmp		; if this is <=0 then fac already integral
	ACC08
	bcc	?int		; fac already integral
	beq	?int		; fac already integral
	
	; now A=count of bits to clear starting from mantissa ending
	; and we can clear the fractional part to get just the integral part
	
	stz	facm+1		; clear lsb
	dec	a
	beq	?int		; done: fac is integral
	ldy	#0		; Y=0
	tyx			; X=0
?lp:	cmp	#8		; clear 8 bits at time?
	bcc	?bit		; no, we have to clear less than 8 bits
	sty	facm+2,x
	inx
	sbc	#8		; update count
	beq	?int		; done: fac is integral
	bra	?lp		; loop until we can clear 8 bits at time
?bit:	txy			; save mantissa index			
	tax			; X=count of bits
	dex
	lda	>fmask,x	; load bits mask
	tyx			; X=mantissa index
	and	facm+2,x	; mask mantissa byte
	sta	facm+2,x
?int:	bit	facsgn		; if fac>0...
	bpl	?end		; ...then done
	ACC16			; ...else we compare if integral part...
				; ...is equal to original fac
	lda	facm+2
	cmp	argm+2
	bne	?chk
	lda	facm+4
	cmp	argm+4
	bne	?chk
	lda	facm+6
	cmp	argm+6
	bne	?chk
	lda	facm+8
	cmp	argm+8
	bne	?chk
	lda	facm+10
	cmp	argm+10
	bne	?chk
	lda	facm+12
	cmp	argm+12
	bne	?chk
	lda	facm+14
	cmp	argm+14
?chk:	ACC08
	beq	?end		; if equal then return it...
	jmp	fsubone		; ...otherwise subtract 1
?end:	clc
	rts

; bit mask to clear
fmask:
	.BYTE	$FE,$FC,$F8,$F0,$E0,$C0,$80

;---------------------------------------------------------------------------
; remainders routines
;---------------------------------------------------------------------------	

; fpmod, fprem - returns the remainder of x/y
;
;	entry:
;		fac = y
;		arg = x
;
;	exit:
;		fac = remainder
;		arg = integral part of the quotient
;		CF = 1 if invalid results
;
; The quotient is truncated toward zero in fpmod, and rounded to nearest
; in fprem. The remainder is computed as: x - n*y, where n is the integral
; quotient.
;
;-----
fpmod:
;-----
	jsr	rdiv		; x/y
	jsr	ftrunc
	bra	rem
		
;-----	
fprem:
;-----
	jsr	rdiv		; x/y
	jsr	fround

;---
rem:
;---
	jsr	mvf_t2		; tfr2 = n
	jsr	mvt1_a		; y
	jsr	fpmult		; y*n	
	jsr	mvt0_a
	jsr	fpsub		; fac = x - y*n
	jmp	mvt2_a		; arg = n

;----
rdiv:
;----
	jsr	mvf_t1		; tfr1 = y
	jsr	mva_t0		; tfr0 = x
	jsr	fpdiv		; x/y
	bcc	?ret		; ok
	jsr	fldnan		; return nan
	jsr	mvftoa
	pla			; skip return address
	pla
	sec
?ret:	rts
	
; fpfrac - returns the integral part, trucated toward zero, and the fractional
; part of the argument x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = y = fractional part of x, with: -1 < y < +1
;		arg = k = integral part of x, as returned by ftrunc(x)
;		CF = 1 if invalid result (inf or nan)
;		in this case fac=arg=nan/inf
;
; note that y and k have the same sign of x and:
;
;		x = k + y
;
;------
fpfrac:
;------
	bit	facst
	bpl	?fv		; fac is valid
?er:	jsr	mvftoa		; set arg=fac
	sec			; return invalid flag
	rts
?fv:	jsr	mvf_t3		; move fac to temp. reg. tfr3
	jsr	ftrunc		; fac=k=ftrunc(x)
	bcs	?er		; overflow
	jsr	mvf_t2		; tfr2=k
	jsr	mvt3_a		; arg=x
	jsr	fpsub		; fac=y=x-k
	jmp	mvt2_a		; arg=k

;---------------------------------------------------------------------------
; conversion decimal/hexadecimal to binary
;---------------------------------------------------------------------------	

; str2int, str2int2 - convert the initial portion of the source string to
; an unsigned or signed 128 bits integer.
;
;	entry:
;		A = low  address of source string
;		X = high address of source string
;		Y = bank that hold source string
;		B = flag signed conversion ($80), ignored for hex. string
;
; str2int2 is the re-entry point when long pointer tlp is already set,
; and in this case:
;
;	entry:
;		A = flag signed conversion ($80), ignored for hex. string
;		tlp = long pointer to source string
;
; 	exit:
;		facm..facm+15 = 128 bits integer
;		facsiz = minimum number of bytes that can hold the integer
;		A = first character where conversion stop
;		tlp = long pointer to first char. where conversion stop
;		CF = 0 if conversion was succesfully done
;		VF = 1 if integer overflow
;		CF = 1 (VF don't care) if input string is invalid
;
; Conversion start parsing source string from left toward right, skipping any
; leading blank and/or tab: if initial portion of string begin with '$',
; or '0x', or '0X', the conversion is done in base 16, otherwise in base 10.
; In decimal conversion an optional single sign '+' or '-' can precede any 
; decimal digit, while in hexadecimal conversion just hexadecimal's digits 
; (both lower case and upper case) can follow the initial '$' or '0x'.
; Conversion stop at the end of the string or at the first character that 
; does not produce a valid digit in the given base, and tlp hold the long 
; pointer to this character.
;
;-------
str2int:
;-------
	sta	tlp		; set long pointer to source ascii string
	stx	tlp+1
	sty	tlp+2
	xba			; signed flag

;--------
str2int2:
;--------
	and	#$80		; mask signed flag
	ora	#$60		; set bit 6&5 (assume integer = 0)
	sta	facst		; flag signed conversion
	stz	facsgn		; assume positive sign
	ldx	#17		; clear facm
?clr:	stz	facm,x		; facexp used for overflow check (extension)
	dex
	bpl	?clr
	stz	wftmp+1		; digit's flag
	ldy	#0		; init string pointer
	bra	?get0
?nx0:	iny
	beq	?iy		; string index overflow
?get0:	lda	[tlp],y		; get char
	beq	?eos		; end of string
	cmp	#' '
	beq	?nx0		; skip leading blanks
	cmp	#$08
	beq	?nx0		; skip leading 'tab'
	cmp	#'$'		; hex. string?
	beq	?hex		; yes, convert ascii hex. string
	cmp	#'0'
	bne	?dec		; go to decimal conversion
	tax			; save char
	iny			; bump pointer
	beq	?iy		; string index overflow
	lda	[tlp],y		; get char
	cmp	#'x'		; '0x' so hex. conversion
	beq	?hex
	cmp	#'X'		; '0X' so hex. conversion
	beq	?hex
	dey			; re-fetch previous char
	txa			; this is '0'
	bra	?dec2		; handle decimal digit
	
	; parsing of ascii decimal string
?dec:	cmp	#'+'
	beq	?nxt		; skip '+' sign
	cmp	#'-'
	bne	?dec2		; handle decimal digit
	bit	facst		; convert to unsigned?
	bpl	?eos		; invalid '-' sign in unsigned conversion	
	lda	#$80
	sta	facsgn		; set negative sign flag
?nxt:	iny			; next byte
	beq	?iy		; string index overflow
	lda	[tlp],y		; get next char
	beq	?eos		; end of string
?dec2:	sec
	sbc	#'0'+10
	clc
	adc	#10
	bcc	?eos		; not a digit: stop string parsing
	jsr	?m10		; facm*10
	bcs	?ov		; overflow
	jsr	?addg		; fac=fac+digit
	bcs	?ov		; overflow
	lda	#$80
	sta	wftmp+1		; decimal digit indicator
	bra	?nxt		; get next char
?iy:	dey			; string index overflow
	bra	?er		; invalid string
?eos:	sty	fpidx		; end of string or end of parsing
	ldx	wftmp+1		; parsed at least one digit?
	beq	?er2		; no, so error (invalid string)
	jsr	?test		; final conversion test
	clv			; no overflow
	bcc	?done		; CF=0, VF=0 -- ok
?ov:	lda	#$40
	trb	facst
	clc
	sep	#PVFLAG		; VF=1 -- overflow
	bra	?done		; CF=0, VF=1 if signed integer overflow
?er:	sty	fpidx		; save string pointer
?er2:	ldx	#17		; clear facm
?clr2:	stz	facm,x
	dex
	bpl	?clr2
	sec			; error flag (invalid string)
?done:	php			; save carry
	jsr	?gsiz		; compute min. size
	lda	tlp		; update string pointer
	clc
	adc	fpidx
	sta	tlp
	bcc	?end
	inc	tlp+1
	bne	?end
	inc	tlp+2
?end:	lda	[tlp]		; A=last parsed character	
	plp			; restore carry	
	rts
	
	; parsing of ascii hex. string
?hex:	lda	#$60	
	sta	facst		; unsigned conversion only
?hex1:	iny			; bump pointer
	beq	?iy		; string index overflow
?hex2:	lda	[tlp],y		; get next char
	beq	?eos		; end of string
	cmp	#'a'		; test hex. digit
	bcc	?hex3
	sbc	#$20		; capitalize 'a', 'b',...
?hex3:	sec
	sbc	#('0'+10)	; check digits '0'..'9'
	clc
	adc	#10
	bcs	?hex4		; ok, valid hex. digit
	sbc	#(6+16)		; check 'A'..'F'
	clc
	adc	#6
	bcc	?eos		; no hex digit: stop parsing
	adc	#9		; valid hex. digit
?hex4:	and	#$0F		; mask low nibble
	sta	wftmp
	ACC16
	jsr	?m2		; facm*16
	jsr	?m2
	jsr	?m2
	jsr	?m2
	lda	facm+16		; overflow test
	ACC08
	bne	?ov		; overflow
	lda	wftmp		; add hex. digit
	ora	facm		; last low nibble
	sta	facm
	lda	#$80
	sta	wftmp+1		; digits flag
	bra	?hex1		; continue string parsing

?test:	ACC16	
	lda	facm+14		; check if zero
	ldx	#12
?lp1:	ora	facm,x
	dex
	dex
	bpl	?lp1
	cmp	#$0000
	ACC08
	beq	?vf		; finish: integer = 0
	lda	#$40
	trb	facst		; not zero integer indicator
	bit	facst		; conversion test
	bpl	?vf		; wanted unsigned integer: finish
	bit	facsgn		; if negative decimal...
	bmi	?neg		; ...should negate facm
	lda	facm+15		; should be <$80 if positive signed integer
	bpl	?vf		; finish: positive signed integer
	bmi	?of		; signed integer overflow
?neg:	ACC16
	ldx	#0		; facm index
	ldy	#8		; counter (8 words)
	sec
?lp2:	lda	#0		; two's complement
	sbc	facm,x
	sta	facm,x
	inx
	inx
	dey
	bne	?lp2
	lda	facm+14		; must be negative
	ACC08
	bpl	?of		; signed integer overflow
?vf:	clc			; valid flag
	rts
?of:	sec			; overflow
	rts
	
?m10:	ldx	#17		; multiplies facm by 10
	sty	fpidx		; save Y
	sta	wftmp		; save digit	
?m101:	lda	facm,x		; move facm to argm
	sta	argm,x
	dex
	bpl	?m101
	ACC16
	jsr	?m2		; facm*2
	jsr	?m2		; facm*4
	jsr	?add		; facm*4+argm=facm*5
	jsr	?m2		; facm*10
	lda	facm+16		; check overflow
	ACC08
	beq	?nof		; no overflow
	sec			; overflow flag
?nof:	ldy	fpidx		; restore Y
	lda	wftmp		; restore digit
	rts

?m2:	asl	facm		; multiplies facm by 2
	rol	facm+2
	rol	facm+4
	rol	facm+6
	rol	facm+8
	rol	facm+10
	rol	facm+12
	rol	facm+14
	rol	facm+16
	rts

?addg:	sty	fpidx		; add digit to facm - save Y
	sta	argm		; digit
	ACC16			; argm was already cleared
	jsr	?add
	lda	facm+16		; check overflow
	ACC08
	beq	?nof1		; no overflow
	sec			; overflow flag
?nof1:	ldy	fpidx		; restore Y
	rts

?add:	clc			; facm=facm+argm
	ldx	#0		; facm&argm index
	ldy	#9		; counter (9 words)
?ad1:	lda	facm,x		; facm=facm+argm
	adc	argm,x
	sta	facm,x
	stz	argm,x		; and clear argm for later use
	inx
	inx
	dey
	bne	?ad1
	rts

?gsiz:	bcs	?gse		; invalid string
	lda	#16		; assume max. possible size
	sta	facsgn
	bvs	?gse		; overflow condition
	bit	facst		; compute min. integer size (in bytes #)
	bvc	?gs0		; not zero
	lda	#1		; zero can fit in one byte
	sta	facsgn
?gse:	rts
?gs0:	bmi	?gss		; signed integer
	ldx	#16
	ACC16
	lda	facm+14
	ora	facm+12
	ora	facm+10
	ora	facm+8
	bne	?gs1		; 16 bytes integer
	ldx	#8
	lda	facm+6
	ora	facm+4
?gs1:	ACC08
	bne	?gs2		; 8 bytes integer
	ldx	#4
	lda	facm+3
	bne	?gs2		; 4 bytes integer
	dex
	lda	facm+2
	bne	?gs2		; 3 bytes integer (long pointer)
	dex
	lda	facm+1
	bne	?gs2		; 2 bytes integer
	dex			; 1 byte integer
?gs2:	stx	facsgn
	rts
?gss:	ldy	facm+15
	bpl	?gsp		; signed integer is positive
	ldx	#16
	ACC16
	lda	facm+14
	and	facm+12
	and	facm+10
	and	facm+8
	cmp	#$FFFF
	bne	?gs4		; 16 bytes signed integer
	lda	facm+6
	bpl	?gs4		; 16 bytes signed integer
	ldx	#8
	and	facm+4
	cmp	#$FFFF
	bne	?gs4		; 8 bytes signed integer
	lda	facm+2
	bpl	?gs4		; 8 bytes signed integer
	ldx	#4
	cmp	#$FFFF
	ACC08
	bne	?gs4		; 4 bytes signed integer
	lda	facm+1
	bpl	?gs4		; 4 bytes signed integer
	ldx	#2
	cmp	#$FF
	bne	?gs4		; 2 bytes signed integer
	lda	facm
	bpl	?gs4
	dex
?gs4:	ACC08	
	stx	facsgn
	rts
?gsp:	ldx	#16
	ACC16
	lda	facm+14
	ora	facm+12
	ora	facm+10
	ora	facm+8
	bne	?gs6		; 16 bytes signed integer
	lda	facm+6
	bmi	?gs6		; 16 bytes signed integer
	ldx	#8
	ora	facm+4
	bne	?gs6		; 8 bytes signed integer
	lda	facm+2
	bmi	?gs6		; 8 bytes signed integer
	ldx	#4
	cmp	#0
	bne	?gs6		; 4 bytes signed integer
	ACC08
	lda	facm+1
	bmi	?gs6		; 4 bytes signed integer
	ldx	#2
	tay
	bne	?gs6		; 2 bytes signed integer
	lda	facm
	bmi	?gs6		; 2 bytes signed integer
	dex			; 1 byte signed integer
?gs6:	ACC08	
	stx	facsgn
	rts
	
; str2fp, str2fp2 - convert the initial portion of the source string to
; a 128 bits binary floating point.
;
;	entry:
;		A = low  address of source string
;		X = high address of source string
;		Y = bank that hold source string
;
; str2fp2 is the re-entry point when long pointer tlp is already set,
; and in this case:
;
;	entry:
;		tlp = long pointer to source string
;
; 	exit:
;		fac = converted floating point
;		A = first character where conversion stop
;		tlp = long pointer to first char. where conversion stop
;		CF = 0 if conversion was succesfully done
;		VF = 1 if fac=inf/nan
;		CF = 1 (VF don't care) if input string is invalid
;
; Conversion start parsing source string from left toward right, skipping any
; leading blank and/or tab.
; The expected form of the input string is either:
;
;	+o  an hexadecimal ascii string beginning with '$' or '0x' or '0X',
;	    followed by exactly 32 hexadecimal digits (case don't care) for
;	    the significand, followed by a 'p' or a 'P', followed by 4 
;	    hexadecimals digits for the biased exponent. Significand sign
;	    should be ored with msb of the biased exponent.
;	    Example:
;		$80000000000000000000000000000000pbfff = -1.0	
;		$80000000000000000000000000000000p3fff = +1.0	
;		$00000000000000000000000000000000p0000 = +0.0	
;	    Number 0.0 can be expressed either by significand=0 and/or
;	    exponent=0.
;
;	+0  an hexadecimal ascii string beginning with '#', followed by
;	    exactly 32 hexadecimal digits (case don't care), seen as a packed
;	    standard ieee quadruple format.
;	    Example:
;		#bfff0000000000000000000000000000 = -1.0	
;		#3fff0000000000000000000000000000 = +1.0	
;		#00000000000000000000000000000000 = +0.0	
;
;	+o  a decimal ascii string, beginning with an optional single '+'
;	    or '-' sign, followed by a decimal significand consisting of a
;	    sequence of decimal digits optionally containing a decimal-point
;	    character, '.'. The	significand may	be optionally followed by an 
;	    exponent. An exponent consists of an 'E' or 'e' followed by an
;	    optional plus or minus sign, followed by a sequence of decimal 
;	    digits; the exponent indicates the power of 10 by which the
;	    significand should be scaled.
;
;	+o  a string "+INF", "-INF", "+NAN", "-NAN", where the sign '+' or
;	    '-' is optional (case don't care).
;
; Conversion stop at the end of the string or at the first character that 
; does not produce a valid digit in the given base, and tlp hold the long 
; pointer to this character.
;
;------
str2fp:
;------
	sta	tlp		; set long pointer to source ascii string
	stx	tlp+1
	sty	tlp+2

;-------
str2fp2:
;-------
	stz	fexph		; clear exponent
	stz	fexp+1
	stz	tmdot		; count of decimal digits (after a dot)
	stz	tmdot+1
	stz	facst		; clear status
	stz	facsgn		; clear sign
	stz	tmsgn		; sign&dot indicator
	stz	tmcnt		; count of mantissa digits
	stz	tesgn		; sign&exponent indicator
	stz	tecnt		; count of exponent digit
	jsr	fldz		; set fac=0
	ldy	#0		; init string pointer
	bra	?get0
?nx0:	iny
	beq	?iy		; string index overflow
?get0:	lda	[tlp],y		; get char
	beq	?eos		; end of string
	cmp	#' '
	beq	?nx0		; skip leading blanks
	cmp	#$08
	beq	?nx0		; skip leading 'tab'
	cmp	#'#'		; ieee packed hex. string?
	bne	?ckh		; no
	jsr	?ieee		; convert hex. packed to float
	bra	?ehx	
?ckh:	cmp	#'$'		; hex. string?
	beq	?hex		; yes, convert ascii hex. string
	cmp	#'0'
	bne	?dec		; go to decimal conversion
	tax			; save char
	iny			; bump pointer
	beq	?iy		; string index overflow
	lda	[tlp],y		; get char
	cmp	#'x'		; '0x' so hex. conversion
	beq	?hex
	cmp	#'X'		; '0X' so hex. conversion
	beq	?hex
	dey			; re-fetch previous char
	txa			; this is '0'
	bra	?dec2		; handle decimal digit
?hex:	jsr	?hfp		; convert hex. string to float
?ehx:	sty	fpidx		; store index
	clv			; ignore VF for hex. conversion
	jmp	?done

	; parsing of ascii decimal string
?dec:	cmp	#'+'
	beq	?nxt		; skip '+' sign
	cmp	#'-'
	bne	?dec2		; handle decimal digit
	lda	#$80
	sta	tmsgn		; set negative sign flag
?nxt:	iny			; next byte
	beq	?iy		; string index overflow
	lda	[tlp],y		; get next char
	beq	?eos		; end of string
?dec2:	sec
	sbc	#'0'+10
	clc
	adc	#10
	bcc	?ndg		; is not a digit
	bit	tesgn		; will process exponent digits?
	bvs	?edec		; yes
	inc	tmcnt		; count of mantissa digits 
	jsr	?mupd		; update mantissa (add digit)
	bcc	?nxt		; next byte
	bcs	?ovf		; overflow error
?edec:	inc	tecnt		; process exponent digit
	jsr	?eupd		; update exponent (add digit)
	bcc	?nxt		; next byte
	bcs	?ovf		; exponent overflow error

?iy:	dey			; here when index overflow
	bra	?nv		; invalid string

	; end of string or parsing of an invalid char
?eos:	sty	fpidx		; store index	
	ldx	tmcnt
	beq	?nv1		; no mantissa digits: invalid string
	bit	tesgn
	bvc	?sc		; no exponent: scale fac according decimals 
	ldx	tecnt
	beq	?nv1		; no exponent digits: invalid string
	bra	?sc		; scale fac according to exponent&decimals

	; handle no-digit character	
?ndg:	adc	#'0'		; restore character
	cmp	#'.'		; check if decimal dot
	bne	?cke		; go to check 'e', 'E'
	ldx	tmcnt
	beq	?nv		; no mantissa digits so error
	lda	#$40		; test&set dot indicator
	tsb	tmsgn
	bne	?nv		; duplicate dot so error
	bra	?nxt		; next byte
?cke:	cmp	#'E'		; check exponent
	beq	?cke1
	cmp	#'e'
	beq	?cke1
	jsr	?ginf		; read INF or NAN string	
	bcs	?eos		; invalid string
	bra	?done
?cke1:	ldx	tmcnt
	beq	?nv		; no mantissa digits so error
	lda	#$40		; test&set dot indicator
	tsb	tesgn
	bne	?nv		; duplicate 'E' so error
	iny			; get next byte
	beq	?iy		; string index overflow
	lda	[tlp],y
	beq	?eos		; end of string
	cmp	#'+'
	beq	?nxt		; skip '+' sign
	cmp	#'-'
	bne	?dec2		; process this byte
	lda	#$80
	tsb	tesgn		; set negative exponent sign
	bra	?nxt		; get next byte

	; mantissa or exponent overflow
?ovf:	sty	fpidx		; store index of last parsed byte
	ldx	tmsgn		; attual mantissa sign
	stx	facsgn
	jsr	fldinf		; load inf because overflow
	clc			; no error (string is valid)
	sep	#PVFLAG		; VF=1 (overflow)
	bra	?done		; done

	; duplicate dot, duplicate 'E', no valid digits: invalid string
?nv:	sty	fpidx
?nv1:	ldx	tmsgn		; attual mantissa sign
	stx	facsgn
	jsr	fldz		; fac=0
	sec			; error: invalid string
	bra	?done		; done

	; now scale fac according to decimal digits count & exponent
?sc:	ldy	tmsgn
	sty	facsgn
	ldx	#0
	ACC16
	sec
	txa			; change sign to decimal count
	sbc	tmdot
	sta	tmdot
	lda	fexph
	ldy	tesgn		; check exponent sign
	bpl	?sc1
	eor	#$FFFF		; change sign to exponent
	inc	a
?sc1:	clc
	adc	tmdot		; scale fac with this value
	ACC08
	jsr	scale10
	clv			; VF=0
	bcc	?done		; no overflow
	clc			; no error (string is valid)
	sep	#PVFLAG		; VF=1 (overflow)	
?done:	php			; save CF&VF
	lda	tlp
	clc
	adc	fpidx
	sta	tlp
	bcc	?rts
	inc	tlp+1
	bne	?rts
	inc	tlp+2
?rts:	plp	
	rts

	; update mantissa: fac=(fac*10)+byte (where A=byte)
?mupd:	sty	tmpy		; save Y
	sta	tmpa		; save A
	bit	tmsgn		; digit after a decimal dot?
	bvc	?mupd1		; no
	inc	tmdot		; increment decimal count
?mupd1:	jsr	mult10		; fac=fac*10
	bcs	?mupd2		; invalid
	jsr	mvftoa		; move fac to arg
	lda	tmpa
	jsr	fldbyt		; load byte into fac
	jsr	fpadd		; fac=(fac*10)+A
?mupd2:	ldy	tmpy		; restore string index
	rts			; CF=1 if overflow

	; update exponent: fexph=(10*fexph)+A
?eupd:	sta	tmpa		; save byte to add
	stz	tmpa+1		; high byte = 0
	ACC16
	lda	fexph
	cmp	#$0CCC		; check overflow condition
	bcs	?eupd1		; limit exponent to $7FFF
	sta	wftmp
	asl	a		; mult. 10
	asl	a
	adc	wftmp
	asl	a
	adc	tmpa		; add byte
	sta	fexph		; update exponent
?eupd1:	ACC08
	rts			; CF=1 if exponent overflow

	; convert hexadecimal string: $xxx...xxpyyyy
	; where xx...xx=significand, yyyy=biased exponent
?hfp:	jsr	?ghex		; convert hex. to fp
	bcs	?ghx		; error getting significand
	ldx	#15
?hfl:	lda	tm,x		; move tm to facm
	sta	facm,x
	dex
	bpl	?hfl
	jsr	?hexp		; get high exponent
	bcs	?ghx		; error
	tax
	and	#$80
	sta	facsgn		; sign
	txa
	and	#$7F
	sta	facexp+1
	jsr	?2hex		; get low exponent
	bcs	?ghx		; error
	sta	facexp
	jsr	?hsep		; check end of string
	bcs	?ghx		; error
	stz	facst
	jsr	chkz		; check if fac=0	
	bit	facst
	bvs	?ghx		; fac=0, exit (CF=0)
	lda	facexp
	ora	facexp+1	; exponent=0?
	beq	?hfz		; yes, set fac=0
	tax
	lda	facm+15
	bmi	?hf3		; normal
	cpx	#1		; subnormal should have exponent=1
	bne	?1hex4		; invalid string
	clc
	rts
?hf3:	jmp	?htst		; test inf/nan
?hfz:	jmp	fldz
	
?ghex:	ldx	#15		; get 128 bits hex
?ghl:	jsr	?2hex
	bcs	?ghx		; error
	sta	tm,x		; store (high-to-low order)
	dex
	bpl	?ghl
?ghx:	rts			; CF=0 if no error

?hexp:	iny			; get 'p' biased high exponent
	beq	?1hex3		; string index overflow
	lda	[tlp],y		; get next char
	cmp	#'p'		; exponent indicator
	beq	?2hex		; ok
	cmp	#'P'
	bne	?1hex4		; invalid string

?2hex:	jsr	?1hex		; convert two digits at time
	bcs	?ghx		; error
	asl	a		; high nibble
	asl	a
	asl	a
	asl	a
	sta	wftmp
	jsr	?1hex		; get low nibble
	bcs	?ghx		; error
	ora	wftmp		; concatenate high & low nibble
	rts			; CF=0, no error

?1hex:	iny			; convert one hex. digit
	beq	?1hex3		; string index overflow
	lda	[tlp],y		; get next char
	beq	?1hex4		; premature end of string
	cmp	#'a'		; convert one hex digit
	bcc	?1hex1
	sbc	#$20		; capitalize 'a', 'b',...
?1hex1:	sec
	sbc	#('0'+10)	; check digits '0'..'9'
	clc
	adc	#10
	bcs	?1hex2		; ok, valid hex. digit
	sbc	#(6+16)		; check 'A'..'F'
	clc
	adc	#6
	bcc	?1hex4		; no hex digit: error
	adc	#9		; valid hex. digit
?1hex2:	and	#$0F		; mask low nibble
?hxok:	clc			; digit ok
	rts
?hsep:	iny			; check valid separator at the end of string
	beq	?1hex3		; string index overflow
	lda	[tlp],y		; get next char
	beq	?hxok		; ok, end of string
	cmp	#' '		; should be a separator
	beq	?hxok		; blank
	cmp	#$08
	beq	?hxok		; tab
	iny			; invalid string
?1hex3:	dey			; string too long
?1hex4:	sec			; error
	rts

?ieee:	jsr	?ghex		; convert hex. to fp
	bcs	?ghx		; error getting significand
	jsr	?hsep		; check end of string
	bcs	?ghx		; error
	lda	tm+15
	tax
	and	#$80
	sta	facsgn		; sign
	txa
	and	#$7F
	sta	facexp+1
	lda	tm+14
	sta	facexp
	sec			; hidden bit
	ora	facexp+1
	bne	?ie1		; normal: hidden bit=1
	clc			; subnormal: hidden bit=0
	inc	a
	sta	facexp		; subnormal have biased exponent=1		
?ie1:	ACC16
	lda	tm+12
	ror	a		; rotate in hidden bit
	sta	facm+14
	lda	tm+10
	ror	a
	sta	facm+12
	lda	tm+8
	ror	a
	sta	facm+10
	lda	tm+6
	ror	a
	sta	facm+8
	lda	tm+4
	ror	a
	sta	facm+6
	lda	tm+2
	ror	a
	sta	facm+4
	lda	tm
	ror	a
	sta	facm+2
	lda	#0		; significand lsb
	ror	a
	sta	facm
	ora	facm+2		; check if zero
	ora	facm+4
	ora	facm+6
	ora	facm+8
	ora	facm+10
	ora	facm+12
	ora	facm+14
	bne	?htst
	sta	facexp		; fac = 0
	ACC08
	lda	#$40
	sta	facst
	clc
	rts
?htst:	ACC16			; test inf/nan
	ldx	#0
	lda	facexp
	cmp	#INFEXP
	bcc	?ie2		; valid float
	ldx	#$C0		; assume inf
	lda	facm+14		; check type
	cmp	#INFSND
	beq	?ie2		; set inf in fac stastus
	ldx	#$80		; set nan in fac status
?ie2:	stx	facst
	ACC08
	clc
	rts

?ginf:	cmp	#'I'
	beq	?inf
	cmp	#'i'
	beq	?inf
	cmp	#'N'
	beq	?nan
	cmp	#'n'
	beq	?nan
	sec			; invalid string
	rts
?inf:	iny
	beq	?inf3		; string index overflow
	lda	[tlp],y		; get next char
	beq	?inf4		; end of string
	ora	#$20
	cmp	#'n'
	bne	?inf4
	iny
	beq	?inf3		; string index overflow
	lda	[tlp],y		; get next char
	beq	?inf4		; end of string
	ora	#$20
	cmp	#'f'
	bne	?inf4
	jsr	?hsep		; terminator or separator
	bcs	?inf5
	sty	fpidx
	jsr	fldinf
?inf0:	clc
	lda	tmsgn
	sta	facsgn
	sep	#PVFLAG
	rts
?inf3:	dey			; string too long
?inf4:	sec			; error
?inf5:	rts

?nan:	iny
	beq	?inf3		; string index overflow
	lda	[tlp],y		; get next char
	beq	?inf4		; end of string
	ora	#$20
	cmp	#'a'
	bne	?inf4
	iny
	beq	?inf3		; string index overflow
	lda	[tlp],y		; get next char
	beq	?inf4		; end of string
	ora	#$20
	cmp	#'n'
	bne	?inf4
	jsr	?hsep		; terminator or separator
	bcs	?inf5
	sty	fpidx
	jsr	fldnan
	bra	?inf0
	
;---------------------------------------------------------------------------
; conversion from binary to decimal
;---------------------------------------------------------------------------	

; int2str - convert an integer to asciiz string (decimal or hexadecimal)
;
; This routine is intended to format a string used by sprintf()-like function,
; but can be used in stand-alone mode too.
;
;	entry:
;		facm = integer (1, 2, 4, 8, 16 bytes)
;
;		A = additional formattation flags
;		    <7>: alternate format
;		    <6>: group thousands
;		    <1>: emit a sign '+' rather than a blank (if bit0=1)
;		    <0>: take account of bit 1, otherwise no '+'/blank emitted
;
;		Y = format: x,X,p,P,d
;
;		X = precision (minimum number of digits)
;
;	exit:
;		X = pointer to ascii buffer
;		Y = size of buffer
;
; The integer parameter stored in facm will be converted, according to the
; format specifier and the requested precision, formatting the output ascii
; string null-terminated:
;
;	p,P format: the integer is interpreted as long pointer (24 bits) and
;	            formatted as 6 hexadecimal digits prepended by '$' or by
;		    '0x' or '0X' if alternate format was specified.
;		    Precision ignored.
;
;	x,X format: the integer is converted as unsigned and formatted as 
;		    sequence of hexadecimal digits prepended by '$' or by
;		    '0x' or '0X' if alternate format was specified.
;
;	d format:   the integer is converted according to the status byte
;		    (facst) either as signed or unsigned integer, and
;		    formatted as sequence of decimal digits. 
;		    If bit 6 of flags is 1, thousands are grouped
;		    3 digits by 3 digits, separated by a comma.
;
; The precision, if any, gives	the minimum number of digits that must appear;
; if the converted value requires fewer digits, it is padded on the left 
; with zeros (precision is ignored for pP format).
;
;-------
int2str:
;-------
	sta	fpaltf		; alternate flag format
	tya			; A=format char
	ldy	#0		; upper case
	cmp	#'a'
	bcc	?nc
	cmp	#'z'+1
	bcs	?nc
	and	#$DF		; capitalize
	ldy	#$20		; lower case
?nc:	sty	fpcap
	cmp	#'P'
	beq	?stf
	cmp	#'X'
	beq	?stf
	cmp	#'D'
	beq	?stf	
	lda	#'D'		; force 'D' format if unknow one	
?stf:	sta	fpfmt		; format style
	cpx	#XCVTMAX	; limit the precision to the buffer size
	bcc	?pr1
	ldx	#XCVTMAX
?pr1:	cmp	#'P'		; 'P' format?
	bne	?pr2
	ldx	#6		; fixed precision = 6 for 'P' format
?pr2:	stx	fpprec		; store wanted precision
	cmp	#'D'
	beq	?dec		; decimal conversion
	lda	#$06		; value to add for digits A..F
	ora	fpcap
	sta	wftmp
	lda	#$7F		; ignore all format bits but bit 7
	trb	fpaltf
	ldx	#15		; counter
	ldy	#0
?hex:	lda	facm,x
	jsr	b2hex		; convert to hexadecimal
	sta	!P0FPU+fpstr,y	; store high digit
	iny
	xba
	sta	!P0FPU+fpstr,y	; store low digit
	iny
	dex
	bpl	?hex
	tyx
	stz	fpstr,x		; put terminator
	bra	?fmt		; final formattation
?dec:	jsr	int2dec		; convert to decimal
?fmt:	ldx	#fpstr		; get pointer to first and last digits
	jsr	?frst		; X -> first, Y->last, A=size
	jsr	?thg		; move (and group) to the xcvt
	tyx			; X = pointer to fisrt significative digit
	sta	wftmp		; A = size of significative string
	lda	fpprec
	sec
	sbc	wftmp
	beq	?nop		; no padding needs
	bcc	?nop		; no padding needs
	ldy	#'0'
?pad:	dex
	sty	<0,x		; padding string with '0'
	dec	a
	bne	?pad
	lda	fpprec
?nop:	tay			; Y = string size
	lda	fpfmt
	cmp	#'D'
	beq	?sts		; decimal formattation
	cmp	#'P'
	bne	?hx0
	ldx	#XCVTEND-6
?hx0:	bit	fpaltf
	bpl	?hx1		; '$' prefix
	dex
	lda	#'X'
	ora	fpcap		; add lower case
	sta	<0,x
	iny			; update size
	lda	#'0'		; '0x' or '0X' prefix
	bra	?hx2
?hx1:	lda	#'$'
?hx2:	dex	
	sta	<0,x
	iny			; update size
	rts
?sts:	sty	fpidx		; store sign according format flags
	bit	dsgn		; sign test
	bpl	?sts1		; positive
	ldy	#'-'		; negative: store sign '-'
	bra	?sts2
?sts1:	lda	fpaltf		; check if should store sign/blank
	lsr	a		; fpaltf<0>: 1 if should store
	bcc	?done		; no store
	ldy	#'+'
	lsr	a		; fpaltf<1>: 1 if should store blank
	bcs	?sts2		; store '+' sign
	ldy	#' '		; store blank
?sts2:	dex	
	sty	<0,x
	inc	fpidx
?done:	ldy	fpidx
	rts

	; move digits from fpstr buffer to xcvt buffer and
	; group the digits in thousands (use comma as separator)
	; on entry: Y = index of first significative digit on fpstr
	;	    X = pointer to last digit on fpstr
	; on exit:  Y = pointer to first significative digit
	;	    A = size of string
	;	    X = pointer to last digit
?thg:	sty	wftmp		; index of first significative digit
	txy			; Y = pointer to last digit
	ldx	#XCVTEND	; X = pointer to end of xcvt buffer
	stz	<0,x		; put string terminator
	dex			; bump pointer
?thg2:	lda	#3		; goups 3 digits
?thg4:	xba			; B = digits counter
	lda	!P0FPU,y	; A = current digit
	sta	<0,x		; move digit
	dey
	cpy	wftmp		; finish?
	bcc	?frst		; yes
	xba			; A = digits counter
	dex
	dec	a
	bne	?thg4		; groups 3 digits
	bit	fpaltf		; check if should groups thousands
	bvc	?thg2		; no groups
	lda	#','		; thousands separator
	sta	<0,x
	dex
	bra	?thg2		; repeat until end of source string

	; get the pointer to first significative digit (not '0')
	; on entry: X = pointer to first digit
	; on exit:  Y = pointer to first significative digit
	;	    A = size of string
	;	    X = pointer to last digit
?frst:	stx	wftmp+1
?fr0:	lda	<0,x
	beq	?fr1		; end of string
	cmp	#'0'
	bne	?fr2		; first significative digit
	inx
	bra	?fr0		; search again
?fr1:	dex			; X = pointer to last digit
?fr2:	txy			; Y = pointer to first significative digit
	ldx	wftmp+1		; start of string
?fr3:	lda	<0,x		; search end of string
	beq	?fr4
	inx
	bra	?fr3
?fr4:	dex			; X = pointer to last digit
	txa
	sty	wftmp
	sec
	sbc	wftmp
	inc	a		; significative string size
	rts

; fp2str - convert a quadruple precision floating point to asciiz string
;
; This routine is intended to format a string used by sprintf()-like function,
; but can be used in stand-alone mode too.
;
;	entry:
;		fac = floating point argument
;
;		A = additional formattation flags
;		    <7>: alternate format
;		    <6>: not discriminate +0.0 from -0.0
;		    <1>: emit a sign '+' rather than a blank (if bit0=1)
;		    <0>: take account of bit 1, otherwise no '+'/blank emitted
;
;		Y = format: e,E,f,F,g,G,a,A,k,K
;
;		X = precision/count of decimal digits (after the '.')
;
;	exit:
;		X = pointer to ascii buffer
;		Y = size of buffer
;
; The formatted decimal string is either the f/F format:
;	[sign]ddd.ddd
; or the e/E format:
;	[sign]d.ddde+|-[d][d]dd
; where the number of digits after the decimal-point character is equal to
; precision specification. The exponent in E format always contains at least
; two digits; if the value is zero, the exponent is 00.
; In the G format, precision specifies the number of significant digits: if
; it is zero, is teeated as 1. G format can format decimal string in E style
; or F style: style E is used if the exponent from its conversion is less 
; than MINGEXP or greater than or equal to the precision.
; Trailing decimal points are usually suppressed, as also are trailing 
; fraction zeroes in the G/g format. If bit 7 of additional flag is 1
; then trailing decimal dot remain, and G/g format will not trim zeroes.
; The format a/A format an hexadecimal string that contain 32 hexadecimal
; digits (the content of the 128 bits mantissa), followed by the biased
; exponent (introduced by literal 'p' or 'P'), or-ed at bit 15 with sign of 
; the float. Hexadecimal string is prepended either by '$' or '0x' or '0X'.
; The no-standard format k/K format an hexadecimal string that contain the 32
; hexadecimal digits of the packed float (ieee format). 
; Hexadecimal string is prepended by '#'.
;
; The result formatted string can have at max. XCVTMAX characters: if the
; requested format & precision cannot fit into this limit, the format is
; switched to 'E' and limited in size.
;
;------
fp2str:
;------
	sta	fpaltf		; alternate flag format
	stz	fpstyle		; assume 'E' style
	tya			; A=format char
	ldy	#0		; upper case
	cmp	#'a'
	bcc	?nc
	cmp	#'z'+1
	bcs	?nc
	and	#$DF		; capitalize
	ldy	#$20		; lower case
?nc:	sty	fpcap
	cmp	#'E'
	beq	?stf
	cmp	#'F'
	beq	?stf
	cmp	#'A'
	beq	?stf
	cmp	#'K'
	beq	?stf	
	lda	#'G'		; force 'G' format if unknow one	
?stf:	sta	fpfmt		; format style
	cpx	#XCVTMAX	; limit the precision to the buffer size
	bcc	?pr1
	ldx	#XCVTMAX
?pr1:	cmp	#'G'		; 'G' format?
	bne	?pr2		; no
	txy			; if precision=0 and 'G' format...
	beq	?pr3		; ...then set precision=1
	bne	?pr4		; significant digits for 'G' format
?pr2:	cmp	#'E'		; 'E' format?
	bne	?pr4		; no
?pr3:	inx			; 'E' format need one digit more	
?pr4:	stx	fpprec		; store wanted precision
	stz	fpprec+1	; extend precision P to 16 bits

	; P=fpprec specifies significant digits for 'E' & 'G' format, 
	; and digit counts of fractional part for 'F' format
	
	cmp	#'A'		; 'A' format?
	bne	?kfmt		; no
	
	; format floating point as hexadecimal full mantissa
	; plus biased exponent (or-ed with mantissa sign)
	ldy	#0		; string index
	bit	fpaltf
	bpl	?a1		; '$' prfix
	ldx	#'0'		; '0x' or '0X' prefix
	stx	xcvt,y
	iny
	lda	#'X'
	ora	fpcap		; add lower case
	tax
	bra	?a2
?a1:	ldx	#'$'
?a2:	stx	xcvt,y
	iny
	lda	#$06		; value to add for digits A..F
	ora	fpcap
	sta	wftmp
	ldx	#15		; counter
?a4:	lda	facm,x
	jsr	b2hex		; convert
	sta	!P0FPU+xcvt,y	; store high digit
	iny
	xba
	sta	!P0FPU+xcvt,y	; store low digit
	iny
	dex
	bpl	?a4
	lda	#'P'		; exponent separator
	ora	fpcap
	tax
	stx	xcvt,y
	iny
	lda	facsgn
	and	#$80		; mask sign
	ora	facexp+1
	jsr	b2hex		; convert high exponent + sign
	sta	!P0FPU+xcvt,y	; store high digit
	iny
	xba
	sta	!P0FPU+xcvt,y	; store low digit
	iny
	lda	facexp
	jsr	b2hex		; convert low exponent
	sta	!P0FPU+xcvt,y	; store high digit
	iny
	xba
	sta	!P0FPU+xcvt,y	; store low digit
	iny
	jmp	?done

?kfmt	cmp	#'K'		; packed format?
	bne	?cvt		; no
	lda	#tm
	ldx	#>P0FPU
	ldy	#0
	jsr	fpack		; pack to tm..tm+15
	ldy	#0
	ldx	#'#'
	stx	xcvt,y
	iny
	lda	#$06		; value to add for digits A..F
	ora	fpcap
	sta	wftmp
	ldx	#15		; counter
?kl:	lda	tm,x
	jsr	b2hex		; convert
	sta	!P0FPU+xcvt,y	; store high digit
	iny
	xba
	sta	!P0FPU+xcvt,y	; store low digit
	iny
	dex
	bpl	?kl
	bra	?done
	
	; The basic conversion to a decimal string is done by fp2dec,
	; with this function responsible for "customizing" the simple
	; format which fp2dec returns. 
?cvt:	jsr	fp2dec		; let E=dexp=decimal exponent
	bit	facst		; fac is valid?
	bpl	?vf		; yes
	jsr	?sts		; store sign
	ldx	#0		; store string NAN or INF
?inv:	lda	fpstr,x	
	ora	fpcap		; add lower case
	sta	!P0FPU+xcvt,y	; store
	iny
	inx
	cpx	#3
	bcc	?inv
	bra	?done		; done
?vf:	jsr	?round10	; round up decimal number
	
	; Now that we have the basic string, decide what format the caller
	; wants it to be put into. Use the F format if either of the 
	; following is true:
	; 	o+ the format is 'f' or 'F'
	;	o+ the format is 'g' or 'G' and the exponent
	;	   is between MINGEXP and precision (fpprec)
	; and if overall digits count is less than XCVTMAX.
	lda	fpfmt	
	cmp	#'E'
	beq	?end2		; caller wants 'E' format
	cmp	#'G'
	ACC16CLC
	bne	?ff		; caller wants 'F' format
	lda	dexp		; if E < 0...
	bmi	?g1		; ...compare vs. MINGEXP 
	cmp	fpprec		; ...else compare with P
	bcs	?end		; if E >= P select 'E' style
	lda	fpprec		; 'G' format, E>=0: overall digits count = P
	bra	?g2
?g1:	cmp	#MINGEXP
	bcc	?end		; if E < MINGEXP select 'E' style
	eor	#$FFFF		; complement decimal exponent
	inc	a
	clc
	adc	fpprec		; 'G' format, E<0...
?g2:	sta	wftmp		; ...overall digits count = |E|+P
	bra	?f2
?ff:	lda	fpprec		; 'F' format: P = P + 1
	inc	a
	ldx	dexp+1
	bmi	?f1		; 'F', E<0: overall digits count = P+1
	adc	dexp		; 'F', E>=0: overall digits count = E+P+1
?f1:	sta	wftmp
?f2:	cmp	#XCVTMAX	; fit into buffer?
	ACC08
	bcc	?f3		; yes
	lda	#MAXDIGITS
	sta	fpprec
	bcs	?end2		; force 'E' style
?f3:	ldx	#$80
	stx	fpstyle		; select 'F' style
	bra	?end2
?end:	ACC08	
?end2:	jsr	?sts		; emit sign
	sty	fpidx		; index of the first digit
	bit	fpstyle		; 'F' format?
	bpl	?ee		; no, 'E' format
	jsr	?ffmt
	bra	?done
?ee:	jsr	?efmt
?done:	ldx	#0
	stx	xcvt,y
	ldx	#xcvt
	rts

	; If E<0, the 'F' format place a digit '0' followed by a decimal dot, 
	; followed by |E|-1 leading zeroes. After, place all needs significant
	; digits.
?ffmt:	stz	fpdot	
	lda	dexp		; exponent E
	bpl	?ffp		; E>=0
	ldx	#'0'
	stx	xcvt,y
	iny
	ldx	#'.'
	stx	xcvt,y
	iny
	dec	wftmp		; update digits count
	dec	fpdot		; decimal dot indicatr
	ldx	#'0'
?ff0:	inc	a
	beq	?ffr		; when E=0 put significant...
	stx	xcvt,y		; put leading zeroes...
	iny
	dec	wftmp
	bra	?ff0		; ...until E=0
?ffp:	inc	a		; we increment exponent for easily manage '.'
?ffr:	ldx	#0		; index
	sta	scexp		; save current exponent
	
	; Now write the regular digits, inserting a '.' if it is somewhere
	; in the middle of the numeral.
?ffl:	lda	fpstr,x		; regular digit
	beq	?ff2		; end
	sta	!P0FPU+xcvt,y	; store digit
	iny
	inx
	dec	wftmp
	dec	scexp
	bne	?ffl		; loop until last digit or E=0
	lda	#'.'
	sta	!P0FPU+xcvt,y	; store '.'
	iny
	dec	fpdot		; decimal dot indicatr	
	bra	?ffl
?ff2:	ldx	dexp
	bmi	?ff4		; 0.dddd... form
	bit	fpdot
	bmi	?ff4		; no more integral digits
	lda	scexp		; ddd.ddd... form
	beq	?ff4		; no more integral digits
	ldx	#'0'		; must complete an integral number padding it..
?ff3:	stx	xcvt,y		; ...with zeroes
	iny
	dec	wftmp
	dec	a	
	bne	?ff3
	ldx	#'.'		; put in a trailing decimal dot
	stx	xcvt,y
	iny
	dec	fpdot		; decimal dot indicator
?ff4:	lda	fpfmt
	cmp	#'G'		; 'G' format remove trailing zeroes...
	bne	?ff5
	bit	fpaltf		; ...if not alternate format
	bmi	?ff5
	bit	fpdot		; ...and if was putted in a decimal dot
	bpl	?ff5
	jmp	?trim		; trim trailing zeroes
?ff5:	lda	wftmp		; pad string with '0'
	beq	?ff7
	ldx	#'0'
?ff6:	stx	xcvt,y
	iny
	dec	a
	bne	?ff6
?ff7:	bit	fpaltf		; trim trailing '.' if any...
	bmi	?ff8		; ...and not alternate format
	dey
	ldx	xcvt,y
	cpx	#'.'
	beq	?ff8
	iny
?ff8:	rts

	; The E format always places one digit to the left of the decimal
	; point, followed by fraction digits, and then an 'E' followed
	; by a decimal exponent.  The exponent is always 2 digits unless
	; it is of magnitude > 99.
?efmt:	ldx	fpprec
	cpx	#XCVTMAX-6
	bcc	?e0
	ldx	#XCVTMAX-6
?e0:	stx	wftmp		; overall digits count
	ldx	#0		; decimal string index
	lda	fpstr,x
	sta	!P0FPU+xcvt,y	; store first digit
	dec	wftmp
	inx
	iny
	lda	#'.'		; decimal dot
	xba			; B='.'
	lda	fpstr,x		; follow a digit?
	bne	?e2		; yes
	bit	fpaltf		; if alternate format is false...
	bpl	?exx		; ...not emit trailing '.'
	xba			; otherwise yes
	sta	!P0FPU+xcvt,y	; store '.'
	iny
	bra	?exx		; emit exponent
?e2:	inx			; bump pointer
	xba
	sta	!P0FPU+xcvt,y	; store '.'
	iny
	xba			; 2nd digit
?e3:	sta	!P0FPU+xcvt,y	; store following digits
	iny
	dec	wftmp
	lda	fpstr,x		; next digit
	beq	?e4		; no more digits
	inx
	bra	?e3
?e4:	lda	fpfmt
	cmp	#'G'		; 'G' format remove trailing zeroes...
	bne	?e5
	bit	fpaltf		; ...if not alternate format
	bmi	?e5
	jsr	?trim		; trim trailing zeroes
	bra	?exx		; emit exponent
?e5:	lda	wftmp		; pad string with '0'
	beq	?exx
	ldx	#'0'
?e6:	stx	xcvt,y
	iny
	dec	a
	bne	?e6
?exx:	lda	#'E'		; emit exponent
	ora	fpcap		; add letter case
	sta	!P0FPU+xcvt,y
	iny
	ACC16
	ldx	#'+'
	lda	dexp
	bpl	?exs		; positive exponent
	eor	#$FFFF
	inc	a
	ldx	#'-'
?exs:	sta	tm		; store unsigned exponent
	sta	scexp
	stx	xcvt,y		; store exponent sign
	iny
	sty	fpidx		; save string index
	ACC08
	jsr	w2dec		; convert exponent to decimal
	ACC16
	ldx	#1		; index if exp>=1000
	lda	scexp
	cmp	#1000
	bcs	?ex2
	inx			; 100 <= exp < 1000
	cmp	#100
	bcs	?ex2
	inx			; exp < 100
?ex2:	ACC08
	ldy	fpidx		; string index
?ex3:	lda	fpstr,x
	beq	?ex4
	sta	!P0FPU+xcvt,y
	iny
	inx
	bra	?ex3
?ex4:	rts

	; trim trailing zeroes
?trim:	dey			; pointer to last character
	cpy	fpidx		; if it is the first digit...
	beq	?tr1		; ...restore pointer and exit
	ldx	xcvt,y
	cpx	#'0'		; trim trailing '0'...
	beq	?trim
	cpx	#'.'		; trim trailing '.' if any
	beq	?tr2
?tr1:	iny
?tr2:	rts

?sts:	ldy	#0		; store sign according format flags
	bit	dsgn		; sign test
	bpl	?sts1		; positive
	ldx	#'-'		; negative: store sign '-'
	bra	?sts2
?sts1:	lda	fpaltf		; check if should store sign/blank
	lsr	a		; fpaltf<0>: 1 if should store
	bcc	?sts3		; no store
	ldx	#'+'
	lsr	a		; fpaltf<1>: 1 if should store blank
	bcs	?sts2		; store '+' sign
	ldx	#' '		; store blank
?sts2:	stx	xcvt,y
	iny
?sts3:	rts

?round10:
	; Round up the decimal string according to the wanted precision P
	; We round directly the decimal string at the N-th digit, where:
	;	o+  N=P if 'E' or 'G' format
	;	o+  N=E+P+1 if 'F' format
	; round up with usual decimal method: round to nearest away from zero
	;
	; on entry VF=1 if decimal float = 0.0

	ldx	fpprec		; X=P=precision (8 bit)
	lda	fpfmt		; A=wanted format
	bvs	?zz		; number = 0
	cmp	#'F'
	bne	?rnd		; 'E'&'G' format: N=P
	ACC16CLC		; 'F' format: N=E+P+1
	lda	dexp		; signed addition
	adc	fpprec
	inc	a		; N=E+P+1
	bmi	?rtz		; if N<0 we round to zero
	cmp	#MAXDIGITS	; we limit rounding to the max. possible
	ACC08
	bcc	?rnd0
	lda	#MAXDIGITS
?rnd0:	tax
?rnd:	cpx	#MAXDIGITS	; limit the digit index to round up
	bcc	?rnd1		; round up at N-th digit
	ldx	#MAXDIGITS
	stz	fpstr,x		; truncate??
	rts
?rnd1:	lda	fpstr,x		; last digit: can cause round up
	stz	fpstr,x		; truncate decimal string
	cmp	#'5'		; if last digits < '5'...
	bcc	?rend		; no round up
	txy			; X=0?
	bne	?rnd2		; no
	
	; special case for 'F' format when E<0: can happen that N=E+P+1=0
	; in this case we round up to '1' theb first digit and increment
	; decimal exponent
	stz	fpstr+1		; string contain just one digits '1'...
	bra	?rinc		; ...and we increment exponent
?rnd2:	ldy	#'0'	
?rndl:	dex			; previous digit index
	bmi	?rinc		; rounding up zeroes all digits...
	lda	fpstr,x 
	inc	a		; round up digit
	cmp	#'9'+1
	bcc	?rnd3		; stop rounding up
	sty	fpstr,x		; round digit to '0'...
	bcs	?rndl		; ...and repeat
?rnd3:	sta	fpstr,x		; store rounded digit
	rts			; stop rounding up
?rinc:	ACC16			; rounding generate a carry to first digit
	inc	dexp		; increment decimal exponent
	ACC08
	lda	#'1'		; store '1' because rounding change a 999...
	sta	fpstr		; ...to 1000...
?rend:	rts
?rtz:	ACC08			; round to zero	
	lda	#'0'
	ldx	#EXP10-1	; zeroes all digits...
	stz	fpstr+1,x
?zlp:	sta	fpstr,x
	dex
	bpl	?zlp
	stz	dexp		; clear decimal exponent
	ldx	fpprec
	lda	fpfmt		; A=wanted format
?zz:	cmp	#'F'
	bne	?z1
	inx			; 'F' format: one digit more for '0'
?z1:	cpx	#MAXDIGITS	; limit the digit index
	bcc	?z2
	ldx	#MAXDIGITS
?z2:	stz	fpstr,x		; truncate string
	bit	fpaltf		; check for a signed zero or not
	bvc	?z3		; standard signed zero
	stz	dsgn		; force +0.0
?z3:	rts

; convert byte to 2 hex. digits
; return A=high digit, B=low digit
b2hex:
	pha			; save value
	jsr	?hex
	xba			; B=low digit
	pla			; restore value
	lsr	a		; divide by 16
	lsr	a
	lsr	a
	lsr	a
?hex:	and	#$0F		; mask nibble
	cmp	#10
	bcc	?hex1
	adc	wftmp		; add value for a..f/A..F
?hex1:	adc	#'0'
	rts
	

; fp2dec - convert the floating point fac to decimal ascii string
;
;	entry:
;		fac = argument (either valid or invalid)
;
;	exit:
;		fpstr = 38 digits ascii decimal string (null terminated)
;		        (implicit decimal dot between first and 2nd digit)
;		dsgn = sign of the decimal significand
;		dexp = decimal exponent (2's complement)
;
; 	If fac is not valid return either the string 'NAN' or 'INF' according
;	with fac status (dexp=don't care).
;	If fac=0 (or rounded to 0.0), return a string of digits '0',
;	and dexp=0.
;
; strategy:
;
;	o  find the decimal exponent N of the 'normalized' decimal floating
;	   point number, such that:
;
;				  N
;		|x| = d.ffff... 10	1<= d <=9, f=fractional part
;
;	o  scale |x| by a power of ten equal to M = 37 - N, such that:
;
;			  M		     N	   37 - N		   37
;		y = x * 10   = d.ffff... * 10  * 10	   = d.ffff... * 10
;
;	   select 37 justified by the fact that the maximum decimal exponent
;	   for a 128 bits number is 38.
;
;	o  this scaling give an y such that:
;
;		  37	      38
;		10   <= y < 10   
;
;	   and y can be regarded as 'integral' value with 38 significative digits
;	   (first d digit, followed by 37 ffff... digits of the fractional part),
;	   and can be converted to decimal string. The implicit decimal dot is
;	   between first and 2nd digits.
;
; This routine is used internally and not intended for end use.
;
;------ 
fp2dec:
;------
	lda	facsgn
	stz	facsgn		; absolute fac
	sta	dsgn		; save sign of decimal float
	stz	dexp		; clear decimal exponent
	stz	dexp+1
	bit	facst
	bpl	?vf
	ACC16
	bvc	?nan		; fac=nan
	lda	#'NI'		; fac=inf
	sta	fpstr
	lda	#'F'		; store 'INF'
	bra	?end
?nan:	lda	#'AN'
	sta	fpstr
	lda	#'N'		; store 'NAN'
?end:	sta	fpstr+2
	ACC08
	rts
?vf:	bvc	?nz		; fac <> 0
	lda	#'0'
	ldx	#37		; store 38 digits '0'...
	stz	fpstr+1,x
?z:	sta	fpstr,x
	dex
	bpl	?z
	rts			; ...and exit
?nz:	ldx	#0
	lda	facm+15
	bmi	?nf		; normal float
	lda	#<fce64		; pre-scale by 1e64 the subnormal float
	ldy	#>fce64
	jsr	fcmult
	ldx	#$FF
?nf:	stx	fsubnf		; remember if we prescaled by 1e64
	jsr	frndm		; round mantissa to 113 bits
	
	; For a fast evaluation of the decimal exponent, we make a swift  
	; estimate of the log10 of the float, then check it later.
	; We can form the estimate by multiplying the binary exponent 
	; by a conversion factor Log10(2) with 16 bit accuracy, using
	; an integer signed multiplication 16x16 and taking the high
	; 16 bit of the result. The error is at most one digit up or
	; down.

	ACC16			; get an estimate of the decimal exponent
	sec
	lda	facexp
	sbc	#EBIAS
	ldx	#<LOG2H		; log(2)*$10000 (approximate to 16 bits)
	ldy	#>LOG2H
	jsr	imult		; return C=estimate exponent (high 16 bits)
	sta	dexp		; this can be +/-1 from the real decimal exp.
	lda	#EXP10-1	; get difference exponent with 1e37...	
	sec			; ... to scale fac in range [1e37..1e38-1]
	sbc	dexp
	ACC08
	jsr	scale10		; scale fac by 37 - N
	
	; now check if we will divide by 10 or multiplies by 10 to get
	; the exact decimal exponent; should be: 1e37 <= fac < 1e38

	lda	#<fce38		; now compare fac vs. 1e38
	ldy	#>fce38
	jsr	fccmp		; should be fac<1e38
	bmi	?tst		; fac < 1e38, so go to check if fac>=1e37
	ACC16
	inc	dexp		; increment decimal exponent...
	ACC08			; ...because next division by 10
	jsr	div10		; fac=fac/10 so now fac<1e38
	bra	?cvt		; convert to decimal
?tst:	lda	#<fce37		; now compare fac vs. 1e37
	ldy	#>fce37
	jsr	fccmp
	beq	?cvt		; fac=1e37
	bpl	?cvt		; fac>1e37
	ACC16
	dec	dexp		; decrement decimal exponent because...
	ACC08
	jsr	mult10		; ...we mult x 10

	; now we have 1e37 <= fac < 1e38
	; note that we no round fac because we use all 128 bits mantissa
	; move fac mantissa (128 bits) to temporary mantissa tm
?cvt:	ACC16
	ldx	fsubnf		; we prescaled the float?
	beq	?cvt1		; no
	sec
	lda	dexp		; adjust decimal exponent
	sbc	#64
	sta	dexp
?cvt1:	lda	facm		; we use guard bits too in conversion
	sta	tm
	lda	facm+2
	sta	tm+2
	lda	facm+4
	sta	tm+4
	lda	facm+6
	sta	tm+6
	lda	facm+8
	sta	tm+8
	lda	facm+10
	sta	tm+10
	lda	facm+12
	sta	tm+12
	lda	facm+14
	sta	tm+14
	lda	facexp		; get how many shift need to align tm...
	sec			; ...to get the effective long integer
	sbc	#EBIAS+MNTBITS-1
	ACC08			; negative or null, just 8 bits value
	beq	?cvt2		; tm aligned, no shift
	ldx	#tm
	jsr	shrmx		; shift tm to right to align at 128 bits int.
?cvt2:	jsr	ui2dec		; convert integer to 39 decimal digits

	; first digit is always a leading '0', beacuse 1e37 <= fac < 1e38
	; max. integer is: 340282366920938463463374607431768211455 (> 1e38)
	
	ldx	#0		; we shift one digit to left (normalitation)
?sh:	lda	fpstr+1,x
	sta	fpstr,x
	beq	?done
	inx
	bra	?sh
?done:	rts			; 38 digits + null terminator

; int2dec - convert a signed/unsigned 128 bits long integer to decimal ascii
;
;	entry:
;		facm..facm+15 = signed long integer
;
;	exit:
;		fpstr = 39 digits ascii decimal string (null terminated)
;
; This routine check automatically if signed/unsigned (facst byte test, bit 7)
; Note: this routine store leading not-significative digits '0'
;
;-------
int2dec:
;-------
	stz	dsgn
	ldx	#15		; move facm to tm
?lp:	lda	facm,x
	sta	tm,x
	dex
	bpl	?lp
	stz	dsgn
	bit	facst
	bpl	ui2dec		; unsigned integer
	lda	tm+15
	sta	dsgn		; decimal sign
	bpl	ui2dec		; positive
	ACC16
	ldx	#0
	ldy	#8
	sec
?lp2:	lda	#0		; two's complement
	sbc	tm,x
	sta	tm,x
	inx
	inx
	dey
	bne	?lp2
	ACC08
	bra	ui2dec		; negative

; uint2dec - convert an unsigned 128 bits long integer to decimal ascii
;
;	entry:
;		facm..facm+15 = uint32_t integer
;
;	exit:
;		fpstr = 39 digits ascii decimal string (null terminated)
;
; Note: this routine store leading not-significative digits '0'
;
;--------
uint2dec:
;--------
	ldx	#15		; move facm to tm
?lp:	lda	facm,x
	sta	tm,x
	dex
	bpl	?lp
	stz	dsgn		; clear decimal sign

; ui2dec - convert an unsigned 128 bits long integer to decimal ascii
;
;	entry:
;		tm..tm+15 = uint32_t integer
;
;	exit:
;		fpstr = 39 digits ascii decimal string (null terminated)
;
; Note: this routine store leading not-significative digits '0'
;
; This routine is used internally and not intended for end use.
;
;------
ui2dec:
;------
	phb			; save dbr
	phk
	plb			; set current dbr=pbr
	ldx	#0		; index to decimal table
	stx	wftmp+1		; index to the destination ascii buffer
	ldy	#$80		; partial quotient (alternate positive/neg.)
?lp:	ACC16			; main loop
?sub:	lda	tm		; repeated subtraction's
	sec
	sbc	!dectbl0,x	; low bytes 
	sta	tm
	lda	tm+2
	sbc	!dectbl0+2,x
	sta	tm+2
	lda	tm+4
	sbc	!dectbl1,x
	sta	tm+4
	lda	tm+6
	sbc	!dectbl1+2,x
	sta	tm+6
	lda	tm+8
	sbc	!dectbl2,x
	sta	tm+8
	lda	tm+10
	sbc	!dectbl2+2,x
	sta	tm+10
	lda	tm+12
	sbc	!dectbl3,x
	sta	tm+12
	lda	tm+14
	sbc	!dectbl3+2,x
	sta	tm+14		; CF=0 if remainder is negative
	iny			; increment partial quotient (N flag)
	bcs	?pr		; remainder is positive
	bpl	?sub		; neg. rem. & pos. quot.: repeat subtraction
	bmi	?st		; else store digit
?pr:	bmi	?sub		; pos. rem. & neg. quot.: repeat subtraction 
				; else store digit
?st:	ACC08	
	tya
	bcc	?nr		; remainder is negative
	eor	#$FF		; 10's complement of the quotient
	adc	#10
?nr:	adc	#'0'-1		; A is one more beacuse the 'iny'...
	tay
	stx	wftmp		; save counter
	ldx	wftmp+1		; current decimal string index
	and	#$7F		; strip off bit 7
	sta	fpstr,x		; store digit
	inx
	stx	wftmp+1		; update string index
	tya			; invert sign of the starting quotient
	eor	#$FF
	and	#$80
	tay
	lda	wftmp		; update table index
	clc
	adc	#4
	tax
	cpx	#DTBLSIZ
	bcc	?lp		; repeat until done
	ldx	wftmp+1		; terminate decimal string...
	stz	fpstr,x		; ...with a null
	plb			; restore dbr
	rts

; w2dec - convert an unsigned 16 bits integer to decimal ascii
;
;	entry:
;		C = unsigned 16 bits integer
;
;	exit:
;		fpstr = 5 bytes ascii decimal string (null terminated)
;
; Note: this routine store leading not-significative digits '0'
;
;-----
w2dec:
;-----
	phb			; save dbr
	phk
	plb			; set current dbr=pbr
	ldx	#I16IDX		; index to decimal table
	stz	wftmp+1		; decimal string index
	ldy	#$80		; partial quotient (alternate positive/neg.)
	ACC16
	sta	tm		; 16 bit value
	stz	tm+2		; sign extension
?lp:	ACC16			; main loop
?sub:	lda	tm		; repeated subtraction's
	sec
	sbc	!dectbl0,x	; low bytes 
	sta	tm
	lda	tm+2
	sbc	!dectbl0+2,x
	sta	tm+2		; CF=0 if remainder is negative
	iny			; increment partial quotient
	bcs	?pr		; remainder is positive
	bpl	?sub		; neg. rem. & pos. quot.: repeat subtraction
	bmi	?st		; else store digit
?pr:	bmi	?sub		; pos. rem. & neg. quot.: repeat subtraction 
				; else store digit
?st:	ACC08	
	tya
	bcc	?nr		; negative remainder
	eor	#$FF		; complement
	adc	#10
?nr:	adc	#'0'-1
	tay
	stx	wftmp
	ldx	wftmp+1
	and	#$7F
	sta	fpstr,x
	inx
	stx	wftmp+1
	tya
	eor	#$FF
	and	#$80
	tay
	lda	wftmp
	clc
	adc	#4
	tax
	cpx	#DTBLSIZ
	bcc	?lp
	ldx	wftmp+1
	stz	fpstr,x
	plb
	rts

; table of decreasing powers of ten, from 1e38 down to 1e0, with
; alternating sign, used to convert 128 bits integer in decimal
; Any constant is 128 bits, but table is splitted in four pieces,
; to easily access with an 8 bit index.
; bits from 0 to 31
dectbl0:
	.BYTE	$00,$00,$00,$00		; +1E38
	.BYTE	$00,$00,$00,$00		; -1E37
	.BYTE	$00,$00,$00,$00		; +1E36
	.BYTE	$00,$00,$00,$00		; -1E35
	.BYTE	$00,$00,$00,$00		; +1E34
	.BYTE	$00,$00,$00,$00		; -1E33
	.BYTE	$00,$00,$00,$00		; +1E32
	.BYTE	$00,$00,$00,$80		; -1E31
	.BYTE	$00,$00,$00,$40		; +1E30
	.BYTE	$00,$00,$00,$60		; -1E29
	.BYTE	$00,$00,$00,$10		; +1E28
	.BYTE	$00,$00,$00,$18		; -1E27
	.BYTE	$00,$00,$00,$E4		; +1E26
	.BYTE	$00,$00,$00,$B6		; -1E25
	.BYTE	$00,$00,$00,$A1		; +1E24
	.BYTE	$00,$00,$80,$09		; -1E23
	.BYTE	$00,$00,$40,$B2		; +1E22
	.BYTE	$00,$00,$60,$21		; -1E21
	.BYTE	$00,$00,$10,$63		; +1E20
	.BYTE	$00,$00,$18,$76		; -1E19
	.BYTE	$00,$00,$64,$A7		; +1E18
	.BYTE	$00,$00,$76,$A2		; -1E17
	.BYTE	$00,$00,$C1,$6F		; +1E16
	.BYTE	$00,$80,$39,$5B		; -1E15
	.BYTE	$00,$40,$7A,$10		; +1E14
	.BYTE	$00,$60,$8D,$B1		; -1E13
	.BYTE	$00,$10,$A5,$D4		; +1E12
	.BYTE	$00,$18,$89,$B7		; -1E11
	.BYTE	$00,$E4,$0B,$54		; +1E10
	.BYTE	$00,$36,$65,$C4		; -1E09
	.BYTE	$00,$E1,$F5,$05		; +1E08
	.BYTE	$80,$69,$67,$FF		; -1E07
	.BYTE	$40,$42,$0F,$00		; +1E06
	.BYTE	$60,$79,$FE,$FF		; -1E05
	.BYTE	$10,$27,$00,$00		; +1E04
	.BYTE	$18,$FC,$FF,$FF		; -1E03
	.BYTE	$64,$00,$00,$00		; +1E02
	.BYTE	$F6,$FF,$FF,$FF		; -1E01
	.BYTE	$01,$00,$00,$00		; +1E00

; bits from 32 to 63
dectbl1:
	.BYTE	$40,$22,$8A,$09		; +1E38
	.BYTE	$60,$C9,$0B,$FF		; -1E37
	.BYTE	$10,$9F,$4B,$B3		; +1E36
	.BYTE	$18,$70,$78,$D4		; -1E35
	.BYTE	$64,$8E,$8D,$37		; +1E34
	.BYTE	$F6,$A4,$3E,$C7		; -1E33
	.BYTE	$81,$EF,$AC,$85		; +1E32
	.BYTE	$D9,$B4,$6E,$3F		; -1E31
	.BYTE	$EA,$ED,$74,$46		; +1E30
	.BYTE	$35,$E8,$8D,$92		; -1E29
	.BYTE	$61,$02,$25,$3E		; +1E28
	.BYTE	$C3,$7F,$2F,$60		; -1E27
	.BYTE	$D2,$0C,$C8,$DC		; +1E26
	.BYTE	$B7,$FE,$EB,$E9		; -1E25
	.BYTE	$ED,$CC,$CE,$1B		; +1E24
	.BYTE	$B5,$1E,$38,$FD		; -1E23
	.BYTE	$BA,$C9,$E0,$19		; +1E22
	.BYTE	$3A,$52,$36,$CA		; -1E21
	.BYTE	$2D,$5E,$C7,$6B		; +1E20
	.BYTE	$FB,$DC,$38,$75		; -1E19
	.BYTE	$B3,$B6,$E0,$0D		; +1E18
	.BYTE	$87,$BA,$9C,$FE		; -1E17
	.BYTE	$F2,$86,$23,$00		; +1E16
	.BYTE	$81,$72,$FC,$FF		; -1E15
	.BYTE	$F3,$5A,$00,$00		; +1E14
	.BYTE	$E7,$F6,$FF,$FF		; -1E13
	.BYTE	$E8,$00,$00,$00		; +1E12
	.BYTE	$E8,$FF,$FF,$FF		; -1E11
	.BYTE	$02,$00,$00,$00		; +1E10
	.BYTE	$FF,$FF,$FF,$FF		; -1E09
	.BYTE	$00,$00,$00,$00		; +1E08
	.BYTE	$FF,$FF,$FF,$FF		; -1E07
	.BYTE	$00,$00,$00,$00		; +1E06
	.BYTE	$FF,$FF,$FF,$FF		; -1E05
	.BYTE	$00,$00,$00,$00		; +1E04
	.BYTE	$FF,$FF,$FF,$FF		; -1E03
	.BYTE	$00,$00,$00,$00		; +1E02
	.BYTE	$FF,$FF,$FF,$FF		; -1E01
	.BYTE	$00,$00,$00,$00		; +1E00

; bits from 64 to 95
dectbl2:
	.BYTE	$7A,$C4,$86,$5A		; +1E38
	.BYTE	$26,$B9,$25,$2A		; -1E37
	.BYTE	$15,$07,$C9,$7B		; +1E36
	.BYTE	$7D,$B2,$38,$8D		; -1E35
	.BYTE	$C0,$87,$AD,$BE		; +1E34
	.BYTE	$6C,$72,$BB,$39		; -1E33
	.BYTE	$5B,$41,$6D,$2D		; +1E32
	.BYTE	$DD,$DF,$41,$C8		; -1E31
	.BYTE	$D0,$9C,$2C,$9F		; +1E30
	.BYTE	$51,$F0,$E1,$BC		; -1E29
	.BYTE	$5E,$CE,$4F,$20		; +1E28
	.BYTE	$C3,$D1,$C4,$FC		; -1E27
	.BYTE	$D2,$B7,$52,$00		; +1E26
	.BYTE	$6A,$BA,$F7,$FF		; -1E25
	.BYTE	$C2,$D3,$00,$00		; +1E24
	.BYTE	$D2,$EA,$FF,$FF		; -1E23
	.BYTE	$1E,$02,$00,$00		; +1E22
	.BYTE	$C9,$FF,$FF,$FF		; -1E21
	.BYTE	$05,$00,$00,$00		; +1E20
	.BYTE	$FF,$FF,$FF,$FF		; -1E19
	.BYTE	$00,$00,$00,$00		; +1E18
	.BYTE	$FF,$FF,$FF,$FF		; -1E17
	.BYTE	$00,$00,$00,$00		; +1E16
	.BYTE	$FF,$FF,$FF,$FF		; -1E15
	.BYTE	$00,$00,$00,$00		; +1E14
	.BYTE	$FF,$FF,$FF,$FF		; -1E13
	.BYTE	$00,$00,$00,$00		; +1E12
	.BYTE	$FF,$FF,$FF,$FF		; -1E11
	.BYTE	$00,$00,$00,$00		; +1E10
	.BYTE	$FF,$FF,$FF,$FF		; -1E09
	.BYTE	$00,$00,$00,$00		; +1E08
	.BYTE	$FF,$FF,$FF,$FF		; -1E07
	.BYTE	$00,$00,$00,$00		; +1E06
	.BYTE	$FF,$FF,$FF,$FF		; -1E05
	.BYTE	$00,$00,$00,$00		; +1E04
	.BYTE	$FF,$FF,$FF,$FF		; -1E03
	.BYTE	$00,$00,$00,$00		; +1E02
	.BYTE	$FF,$FF,$FF,$FF		; -1E01
	.BYTE	$00,$00,$00,$00		; +1E00

; bits from 96 to 127
dectbl3:
	.BYTE	$A8,$4C,$3B,$4B		; +1E38
	.BYTE	$EF,$11,$7A,$F8		; -1E37
	.BYTE	$CE,$97,$C0,$00		; +1E36
	.BYTE	$9E,$BD,$EC,$FF		; -1E35
	.BYTE	$09,$ED,$01,$00		; +1E34
	.BYTE	$B2,$CE,$FF,$FF		; -1E33
	.BYTE	$EE,$04,$00,$00		; +1E32
	.BYTE	$81,$FF,$FF,$FF		; -1E31
	.BYTE	$0C,$00,$00,$00		; +1E30
	.BYTE	$FE,$FF,$FF,$FF		; -1E29
	.BYTE	$00,$00,$00,$00		; +1E28
	.BYTE	$FF,$FF,$FF,$FF		; -1E27
	.BYTE	$00,$00,$00,$00		; +1E26
	.BYTE	$FF,$FF,$FF,$FF		; -1E25
	.BYTE	$00,$00,$00,$00		; +1E24
	.BYTE	$FF,$FF,$FF,$FF		; -1E23
	.BYTE	$00,$00,$00,$00		; +1E22
	.BYTE	$FF,$FF,$FF,$FF		; -1E21
	.BYTE	$00,$00,$00,$00		; +1E20
	.BYTE	$FF,$FF,$FF,$FF		; -1E19
	.BYTE	$00,$00,$00,$00		; +1E18
	.BYTE	$FF,$FF,$FF,$FF		; -1E17
	.BYTE	$00,$00,$00,$00		; +1E16
	.BYTE	$FF,$FF,$FF,$FF		; -1E15
	.BYTE	$00,$00,$00,$00		; +1E14
	.BYTE	$FF,$FF,$FF,$FF		; -1E13
	.BYTE	$00,$00,$00,$00		; +1E12
	.BYTE	$FF,$FF,$FF,$FF		; -1E11
	.BYTE	$00,$00,$00,$00		; +1E10
	.BYTE	$FF,$FF,$FF,$FF		; -1E09
	.BYTE	$00,$00,$00,$00		; +1E08
	.BYTE	$FF,$FF,$FF,$FF		; -1E07
	.BYTE	$00,$00,$00,$00		; +1E06
	.BYTE	$FF,$FF,$FF,$FF		; -1E05

; this portion is used by routine that convert 16 bits integer to decimal
dec1e4:
	.BYTE	$00,$00,$00,$00		; +1E04
	.BYTE	$FF,$FF,$FF,$FF		; -1E03
	.BYTE	$00,$00,$00,$00		; +1E02
	.BYTE	$FF,$FF,$FF,$FF		; -1E01
	.BYTE	$00,$00,$00,$00		; +1E00

DTBLSIZ	=	$-dectbl3
I16IDX	=	dec1e4-dectbl3

; limits for conversion float-to-decimal
fce37:	.BYTE	$00,$00,$00,$00,$00,$D4,$86,$1E,$20
	.BYTE	$DB,$48,$BB,$1A,$C2,$BD,$F0,$79,$40	; 1e37
	
fce38:	.BYTE	$00,$00,$00,$00,$80,$44,$14,$13,$F4
	.BYTE	$88,$0D,$B5,$50,$99,$76,$96,$7D,$40	; 1e38

; table of constant for scaling (not rounded, 128 bits mantissa)
; used by scale10 routine (scaling by a power of ten)
fce0:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$80,$FF,$3F	; 1
fce1:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$A0,$02,$40	; 10
fce2:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$C8,$05,$40	; 100
fce3:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$FA,$08,$40 	; 1E3
fce4:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$40,$9C,$0C,$40	; 1E4
fce5:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$50,$C3,$0F,$40	; 1E5
fce6:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$24,$F4,$12,$40	; 1E6
fce7:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$80,$96,$98,$16,$40	; 1E7

fce8:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$20,$BC,$BE,$19,$40	; 1E8

	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$04,$BF,$C9,$1B,$8E,$34,$40	; 1E16

fce32:	.BYTE	$00,$00,$00,$00,$00,$00,$20,$F0,$9D
	.BYTE	$B5,$70,$2B,$A8,$AD,$C5,$9D,$69,$40	; 1E32

fce64:	.BYTE	$FA,$25,$6B,$C7,$71,$6B,$BF,$3C,$D5
	.BYTE	$A6,$CF,$FF,$49,$1F,$78,$C2,$D3,$40	; 1E64

	.BYTE	$35,$01,$B1,$36,$6C,$33,$6F,$C6,$DF
	.BYTE	$8C,$E9,$80,$C9,$47,$BA,$93,$A8,$41	; 1E128

	.BYTE	$B2,$EA,$FE,$98,$1B,$90,$BB,$DD,$8D
	.BYTE	$DE,$F9,$9D,$FB,$EB,$7E,$AA,$51,$43	; 1E256
	
	.BYTE	$E8,$58,$50,$BC,$54,$5C,$65,$CC,$C6
	.BYTE	$91,$0E,$A6,$AE,$A0,$19,$E3,$A3,$46	; 1E512

	.BYTE	$B0,$50,$8B,$F1,$28,$3D,$0D,$65,$17
	.BYTE	$0C,$75,$81,$86,$75,$76,$C9,$48,$4D	; 1E1024

	.BYTE	$22,$CE,$9A,$32,$CE,$28,$4D,$A7,$E4
	.BYTE	$5D,$3D,$C5,$5D,$3B,$8B,$9E,$92,$5A	; 1E2048

fce4096:
	.BYTE	$1A,$4A,$4A,$80,$3F,$15,$4C,$C9,$9A
	.BYTE	$97,$20,$8A,$02,$52,$60,$C4,$25,$75	; 1E4096

FCSIZ	=	$-fce4096

; constants address used by scxale10 routine
fcaddr:	
	.WORD	fce0, fce1, fce2, fce3, fce4, fce5, fce6, fce7

;----------------------------------------------------------------------------
; square root & cube root
;----------------------------------------------------------------------------
	
; fsqrt - return the square root of the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = sqrt(x)
;		CF = 1 if invalid result (nan, inf)
;
; strategy:
;	range reduction involves isolating the power of two of the
;	argument and using a rational approximation to obtain
;	a rough value for the square root;  then Heron's (Newton) iteration
;	is used four times to converge to an accurate value.
;
;	1) range reduction is accomplished by separating the argument x
;	   into an integer M and fraction z such that:
;
;			 2*M
;		x = z * 2	with: 0.25 <= z < 1
;
;	2) obtain a rough value w for the square root of z by a
;	   rational approximation:
;
;		w = A*z + B - C/(z + D)  (accuracy: 10/12 bits)
;
;	3) the estimate w is used as initial seed for Heron's iteration:
;
;		y[n+1] = 0.5*(y[n] + z/y[n])	where y[0] = w, n = 3
;
;	4) finally, the square root of the x is obtained scaling back y:
;
;				     M	      M
;		sqrt(x) = sqrt(z) * 2  = y * 2 
;
;	computation mean time: 30ms at 4MHz
;
;-----
fsqrt:
;-----
	bit	facst		; fac is valid?
	bpl	?fv		; yes
	bvs	?er		; fac=nan so return nan
	bit	facsgn		; fac=inf so check sign
	bpl	?er		; fac=+inf so return +inf
?nan:	jmp	fldnan		; fac=-inf so return nan
?er:	sec
	rts
?fv:	bvc	?xp		; fac is not zero
	stz	facsgn		; fac=+/-0 return always +0
	clc
	rts
?xp:	bit	facsgn		; check if fac>0
	bmi	?nan		; fac<0 so return nan
	jsr	frexp		; reduce argument to range [0.5,1)
	CPU16
	lda	scexp		; the true 2 exponent
	tax
	lsr	a		; CF=0 if exponent is divisible by 2
	txa			; C=exponent
	bcc	?sgn		; divisible by 2
	dec	facexp		; reduce argument to range [0.25, 0.5)
	inc	a		; increment the exponent (now divisible by 2)
?sgn:	asl	a		; CF=exponent sign
	bcc	?sgn2		; positive
	inc	a		; negative: put sign in bit 0
?sgn2:	ror	a		; restore exponent
	ror	a		; divide by 2 with sign extension
	sta	scexp		; scexp = M, fac = z
	CPU08
	
	; approximate sqrt(z) in range [0.25,1) with rational function:
	; w = A*z + B - C/(z + D)  (accuracy: 10/12 bits)
	jsr	mvf_t0		; tfr0 = z
	jsr	faddhalf	; z + D (D=0.5)	
	lda	#<sqc		; C
	ldy	#>sqc
	jsr	fcdiv		; C/(z + D)
	lda	#<sqb		; B
	ldy	#>sqb
	jsr	fcsub		; B - C/(z + D)
	jsr	mvf_t1
	jsr	mvt0_f		; z
	lda	#<sqa		; A
	ldy	#>sqa
	jsr	fcmult		; A*z
	jsr	mvt1_a
	jsr	fpadd		; A*z + B - C/(z + D)

	; Hero's iteration four times	
	jsr	?nit
	jsr	?nit
	jsr	?nit
	jsr	?nit		; fac=sqrt(z)

	jmp	fscale		; fac=sqrt(z)*(2^M)=sqrt(x)

	; newton iteration for sqrt
	; y[n+1] = 0.5*(y[n] + z/y[n])
	; where y[0]=w is the initial seed value
	; note that is safe, when fac is normal and limited,
	; to multiplies by 2 simply incrementing the exponent
?nit:	jsr	mvf_t1		; tfr1 = y[n]
	jsr	mvt0_a		; arg = z
	jsr	fpdiv		; x/y[n]
	jsr	mvt1_a		; arg = y[n]
	jsr	fpadd		; y[n] + z/y[n]
	ACC16
	dec	facexp		; y[n+1] = 0.5*(y[n] + z/y[n])
	ACC08
	rts

; fcbrt - return the cube root of the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = cbrt(x)
;		CF = 1 if invalid result (nan, inf)
;
; strategy:
;	range reduction involves isolating the power of two of the
;	argument and using a rational approximation to obtain
;	a rough value for the cube root;  then one Newton iteration followed
;	by one Halley iteration is used to converge to an accurate value.
;
;	1) range reduction is accomplished by separating the argument x
;	   into an integer M and fraction z such that:
;
;			 3*M
;		x = z * 2	with: 0.125 <= z < 1
;
;	2) obtain a rough value w for the square root of z by a
;	   rational approximation of 8th degree:
;
;		w = N(z)/D(z)  (accuracy: 22/24 bits)
;
;	3) the estimate w is used as initial seed for Newton's iteration:
;
;		p = (1/3)*((z/w*w)) + 2*w)
;
;	4) the estimate p is used as seed for final Halley's iteration:
;
;		y = p*((p*p*p+2*z)/(2*p*p*p+z))
;
;	5) finally, the cube root of the x is obtained scaling back y:
;
;				     M	      M
;		cbrt(x) = cbrt(z) * 2  = y * 2 
;
;	computation mean time: 75/80ms at 4MHz
;
;-----
fcbrt:
;-----
	bit	facst		; if fac is not valid return nan if fac=nan...
	bmi	?er		; ...or return inf if fac=inf (same fac sign)
	bvc	?ok		; fac is not zero
	clc			; return fac=0
	rts
?er:	sec
	rts
?ok:	lda	facsgn		; save fac sign...
	sta	dsgn
	stz	facsgn		; ...and work with absolute value
	jsr	frexp		; reduce argument to range [0.5,1)
	CPU16
	ldx	#3
	lda	dexp		; absolute value of the exponent
	jsr	udiv		; C=quotient, Y=remainder (unsigned)
	tyx
	beq	?go		; remainder=0, exponent is divisible by 3
	tya			; C=remainder	
	ldy	scexp		; check exponent sign
	bmi	?ne		; handle negative exponent
	sec			; C=remainder, compute remainder such that...
	sbc	#3		; ...(exponent-C) is divisible by 3
	bra	?ne2
?ne:	eor	#$FFFF		; exponent is negative...
	inc	a		; ...so change sign to remainder
?ne2:	sta	wftmp		; save for later use	
	clc
	adc	facexp		; reduce argument to range [0.125,1)
	sta	facexp
	sec
	lda	scexp		; find the new exponent after reduction
	sbc	wftmp
	beq	?go2		; exponent=0
	sta	scexp
	bpl	?pe
	eor	#$FFFF
	inc	a
?pe:	ldx	#3		; now exponent is divisible by 3
	jsr	udiv		; C=new exponent	
?go:	ldx	scexp		; change sign if negative
	bpl	?go2
	eor	#$FFFF
	inc	a
?go2:	sta	scexp		; scexp=M=exponent of cube root
	CPU08			; fac=z, range: [1/8, 1)

	; approximate cbrt(z) in range [0.125,1) with rational function:
	; w = N(z)/D(z)  (accuracy: 22/24 bits)
	jsr	mvf_t0		; tfr0 = z		
	lda	#<cbrn		; evaluate numerator
	ldy	#>cbrn
	ldx	#4		; degree=4
	jsr	peval
	jsr	mvf_t1		; tfr1=N(z)
	lda	#<cbrd		; evaluate denominator
	ldy	#>cbrd
	ldx	#4		; degree=4
	jsr	peval
	jsr	mvt1_a		; arg=N(z)
	jsr	fpdiv		; w=N(z)/D(z)

	jsr	?nit		; Newton's iteration (evaluate p) 
	jsr	?hit		; Halley's iteration (evaluate y)
	
	jsr	fscale		; fac=cbrtt(z)*(2^M)=sqrt(x)
	lda	dsgn		; restore original argument sign
	sta	facsgn
	rts
	
?nit:	; Newton's iteration
	; p = (1/3)*((z/w*w)) + 2*w)
	jsr	mvf_t1		; tfr1 = w (initial seed)
	jsr	fsquare		; w*w
	jsr	mvt0_a		; arg=z
	jsr	fpdiv		; z/(w*w)
	jsr	mvt1_a		; arg=w
	ACC16			; is safe here simply increment exponent
	inc	argexp		; arg=2*w
	ACC08
	jsr	fpadd		; 2*w + z/(w*w)
	lda	#<c13		; 1/3
	ldy	#>c13
	jmp	fcmult		; p = (1/3)*((x/(w*w)) + 2*w)

?hit:	; Halley's iteration
	; y = p*((p*p*p+2*z)/(2*p*p*p+z))
	jsr	mvf_t1		; tfr1=p
	jsr	fsquare		; p*p
	jsr	mvt1_a
	jsr	fpmult		; p*p*p
	jsr	mvf_t2		; tfr2=p*p*p
	jsr	mvt0_a		; z
	ACC16			; is safe here simply increment exponent
	inc	argexp		; 2*z
	ACC08
	jsr	fpadd
	jsr	mvf_t3		; tfr3=p*p*p+2*X
	jsr	mvt2_a		; p*p*p
	ACC16			; is safe here simply increment exponent
	inc	argexp		; 2*p*p*p
	ACC08
	jsr	mvt0_f		; z
	jsr	fpadd		; 2*p*p*p+z
	jsr	mvt3_a		; p*p*p+2*z
	jsr	fpdiv		; (p*p*p+2*z)/(2*p*p*p+z)
	jsr	mvt1_a		; p
	jmp	fpmult		; p*((p*p*p+2*z)/(2*p*p*p+z))

; coefficients for initial rational approximation to square root
; R(x) = Ax + B - C/(x + D) 10 bit (0.25 <= x < 1, D=0.5)
sqa:	.BYTE	$62,$47,$23,$98,$80,$52,$B7,$9F,$F7
	.BYTE	$6F,$60,$5B,$7C,$8C,$BA,$AF,$FD,$3F	; A=0.343220129185
sqb:	.BYTE	$9E,$BA,$E5,$B7,$91,$09,$68,$DF,$B2
	.BYTE	$76,$6E,$E6,$E6,$13,$52,$E6,$FE,$3F	; B=0.899689906952
sqc:	.BYTE	$4C,$28,$D6,$5D,$7A,$85,$E9,$00,$81
	.BYTE	$17,$23,$D0,$C7,$70,$63,$BA,$FD,$3F	; C=0.364039921180

c13:	.BYTE	$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
	.BYTE	$AA,$AA,$AA,$AA,$AA,$AA,$AA,$FD,$3F	; 1/3

; coefficients for initial rational approximation to cube root (0.125 <= x < 1)
cbrn:	; numerator coefficients (degree 4)
; N[4] = 45.2548339756803022511987494
	.BYTE	$3C,$10,$33,$78,$FE,$76,$9E,$89,$D0
	.BYTE	$83,$D3,$9D,$32,$F3,$04,$B5,$04,$40
; N[3] = 192.2798368355061050458134625
	.BYTE	$08,$E3,$5B,$8C,$F2,$49,$06,$80,$97
	.BYTE	$00,$B7,$08,$63,$A3,$47,$C0,$06,$40
; N[2] = 119.1654824285581628956914143
	.BYTE	$42,$D8,$BC,$63,$FD,$2F,$EF,$90,$64
	.BYTE	$9F,$70,$E5,$1C,$BA,$54,$EE,$05,$40
; N[1] = 13.43250139086239872172837314
	.BYTE	$AA,$47,$0C,$1F,$85,$FF,$A0,$76,$20
	.BYTE	$00,$A8,$13,$94,$86,$EB,$D6,$02,$40
; N[0] = 0.1636161226585754240958355063
	.BYTE	$7B,$C3,$D8,$3A,$B4,$CC,$8B,$32,$6D
	.BYTE	$69,$E9,$AA,$1F,$FC,$8A,$A7,$FC,$3F

cbrd:	; denominator coefficients (degree 4)	
; D[4] = 14.80884093219134573786480845
	.BYTE	$1A,$8E,$1C,$AB,$2F,$1C,$FF,$A5,$49
	.BYTE	$05,$D9,$76,$30,$03,$F1,$EC,$02,$40
; D[3] = 151.9714051044435648658557668
	.BYTE	$7A,$6B,$6B,$1C,$FD,$4E,$DD,$A5,$C7
	.BYTE	$A8,$C0,$42,$01,$AE,$F8,$97,$06,$40
; D[2] = 168.5254414101568283957668343
	.BYTE	$F6,$AE,$F6,$BD,$0C,$B1,$C7,$0B,$85
	.BYTE	$73,$96,$08,$54,$83,$86,$A8,$06,$40
; D[1] = 33.9905941350215598754191872
	.BYTE	$9C,$0A,$30,$D2,$E7,$F9,$A1,$D1,$F6
	.BYTE	$A7,$1B,$16,$4F,$5E,$F6,$87,$04,$40
; D[0] = 1
	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$80,$FF,$3F

;----------------------------------------------------------------------------
; logarithmic family functions
;----------------------------------------------------------------------------

; flogep1 - return natural logarithm (base e) of x + 1
;
;	entry:
;		fac = x
;
;	exit:
;		fac = loge(1 + x)
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 75/125ms at 4MHz
;
;-------
flogep1:
;-------
	jsr	cmnlogp1	; return the logarithm of the fractional part
	lda	scexp		; if exponent M of the argument is zero...
	ora	scexp+1		; ...we finish here...
	bne	lgem		; ...otherwise we add the loge(M)
	clc			; return valid flag
	rts

; floge - return natural logarithm (base e) of x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = loge(x)
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 75/125ms at 4MHz
;
;-----
floge:
;-----
	jsr	cmnlog		; return the logarithm of the fractional part
	lda	scexp		; if exponent M of the argument is zero...
	ora	scexp+1		; ...we finish here...
	bne	lgem		; ...otherwise we add the loge(M)
	clc			; return valid flag
	rts

; lgem - evaluate loge(2)*M and add to logarithm of fractional part
;
;		     M
; log(x) = loge(f * 2 ) = loge(f) + M * loge(2)
;
;----	
lgem:
;----
	jsr	mvf_t2		; tfr2=loge(f)
	lda	scexp
	ldy	scexp+1
	jsr	fldu16		; convert exponent M to float
	lda	scsgn
	sta	facsgn		; sign of the exponent M
	jsr	mvf_t0
	lda	#<ln2c1		; now evaluate M * loge(2)... 
	ldy	#>ln2c1
	jsr	fcmult
	jsr	mvf_t1		; ...splitted in two
	jsr	mvt0_f
	lda	#<ln2c2
	ldy	#>ln2c2
	jsr	fcmult
	jsr	mvt2_a
	jsr	fpadd
	jsr	mvt1_a
	jmp	fpadd
	
; flog10p1 - return decimal logarithm (base 10) of x + 1
;
;	entry:
;		fac = x
;
;	exit:
;		fac = log10(1 + x)
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 85/140ms at 4MHz
;
;--------
flog10p1:
;--------
	jsr	cmnlogp1	; return the loge of the fractional part
	jsr	lg10		; return the log10 of the fractional part	
	lda	scexp		; if exponent M of the argument is zero...
	ora	scexp+1		; ...we finish here...
	bne	lg10m		; ...otherwise we add the loge(M)
	clc			; return valid flag
	rts

; flog10 - return decimal logarithm (base 10) of x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = log10(x)
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 85/140ms at 4MHz
;
;------
flog10:
;------
	jsr	cmnlog		; return the loge of the fractional part
	jsr	lg10		; return the log10 of the fractional part		
	lda	scexp		; if exponent M of the argument is zero...
	ora	scexp+1		; ...we finish here...
	bne	lg10m		; ...otherwise we add the loge(M)
	clc			; return valid flag
	rts

; lg10m - evaluate log10(2)*M and add to logarithm of fractional part
;
;		    M
; log(x) = log(f * 2 ) = log10(f) + M * log10(2)
;
;-----	
lg10m:
;-----
	jsr	mvf_t2		; tfr2=log10(f)
	lda	scexp
	ldy	scexp+1
	jsr	fldu16		; convert exponent M to float
	lda	scsgn
	sta	facsgn		; sign of the exponent M
	jsr	mvf_t0
	lda	#<l102a		; now evaluate M * log10(2)... 
	ldy	#>l102a
	jsr	fcmult
	jsr	mvf_t1		; ...splitted in two
	jsr	mvt0_f
	lda	#<l102b
	ldy	#>l102b
	jsr	fcmult
	jsr	mvt2_a
	jsr	fpadd
	jsr	mvt1_a
	jmp	fpadd

; lg10 - convert the natural logarithm into decimal logarithm
;
;	multiplies the log of the fraction by log10(e)
;
;----
lg10:
;----
	jsr	mvf_t0		; tfr0=loge(f)
	lda	#<l10ea
	ldy	#>l10ea
	jsr	fcmult
	jsr	mvf_t1
	jsr	mvt0_f
	lda	#<l10eb
	ldy	#>l10eb
	jsr	fcmult
	jsr	mvt1_a
	jmp	fpadd		

; flog2p1 - return the base 2 logarithm of x + 1
;
;	entry:
;		fac = x
;
;	exit:
;		fac = log2(1 + x)
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 80/130ms at 4MHz
;
;-------
flog2p1:
;-------
	jsr	cmnlogp1	; return the loge of the fractional part
	lda	#<lg2e		; return the log2 of the fractional part
	ldy	#>lg2e
	jsr	fcmult
	lda	scexp		; if exponent M of the argument is zero...
	ora	scexp+1		; ...we finish here...
	bne	lg2m		; ...otherwise we add M
	clc			; return valid flag
	rts

; flog2 - return the base 2 logarithm of x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = log2(x)
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 80/130ms at 4MHz
;
;-----
flog2:
;-----
	jsr	cmnlog		; return the loge of the fractional part
	lda	#<lg2e		; return the log2 of the fractional part
	ldy	#>lg2e
	jsr	fcmult
	lda	scexp		; if exponent M of the argument is zero...
	ora	scexp+1		; ...we finish here...
	bne	lg2m		; ...otherwise we add M
	clc			; return valid flag
	rts

; lg2m - add exponent M to base 2 logarithm of fractional part
;
;		    M
; log(x) = log(f * 2 ) = log2(f) + M
;
;----	
lg2m:
;----
	jsr	mvf_t2		; tfr2=log2(f)
	lda	scexp
	ldy	scexp+1
	jsr	fldu16		; convert exponent M to float
	lda	scsgn
	sta	facsgn		; sign of the exponent M
	jsr	mvt2_a
	jmp	fpadd
	
; cmnlogp1 - common logarithm evaluation
; return the natural logarithm (base e) of the fraction of x + 1
;
; Note that when evaluate log(x) with x very close to one, cancellation
; caused by computation of x - 1 can give a degrated result (precision loss).
; To avoid this negative effect is better evaluate log(1+x) when argument
; is very closed to one.
;
;	entry:
;		fac = xm1 (xm1 = x - 1)
;
;	exit:
;		fac = loge(f), f = fraction of xm1 + 1
;		scexp = M = exponent of the argument
;
; 	where:
;			     M
;		1 + x = f * 2	sqrt(2)/2 <= f < sqrt(2)
;
; strategy:
;	The argument is separated into its exponent and fractional parts.
;	If the exponent is between -2 and +2, the logarithm of the fraction,
;	setting y = f - 1, is approximated by:
;
;			       2    3
;	loge(1+y) = y - 0.5 * y  + y * P(y)/Q(y) 
;
;	otherwise, setting y = 2(f - 1)/(f + 1), is approximated by:
;
;		       3			2
;	loge(f) = y + y * R(z)/S(z), where z = y
;
;--------
cmnlogp1:
;--------
	bit	facst
	bmi	?nv		; invalid xm1
	clc
	bvs	?ex		; xm1=0 so return 0
	jsr	mvf_t1		; tfr1=xm1
	jsr	faddone		; x=1+xm1
	bcs	?ex		; x=+inf so return +inf
	bit	facsgn
	bmi	?nan		; x<0 so return -nan
	bit	facst
	bvc	?ok		; ok, x > 0
	jsr	fldinf		; x=0 so return -inf
	lda	#$FF
	sta	facsgn
	bra	?er
?nv:	bvs	?er		; xm1=nan so return nan
	bit	facsgn
	bpl	?er		; xm1=+inf so return +inf
?nan:	jsr	fldnan		; xm1=-inf so return -nan
?er:	sec			; invalid fac
?ex:	pla			; skip return address
	pla
	rts
?ok:	jsr	logscl		; argument reduction & exponent extraction
	bcc	?tiny		; |M| < 3
	jsr	mvf_t0		; tfr0=x
	jsr	fsubone		; x-1	
	bra	lge		; evaluation for |M| > 2	
?tiny:	lda	scexp		; if M=0... 
	ora	scexp+1
	beq	?xm1		; ...use argument xm1
	jsr	fsubone		; ...otherwise use x - 1 
	jmp	lgep1
?xm1:	jsr	mvt1_f		; use xm1
	bra	lgep1

; cmnlog - common logarithm evaluation
; return the natural logarithm (base e) of the fraction of the argument
;
;	entry:
;		fac = x
;
;	exit:
;		fac = loge(f)
;		scexp = M = exponent of the argument
;
; 	where:
;			 M
;		x = f * 2	sqrt(2)/2 <= f < sqrt(2)
;
; strategy:
;	The argument is separated into its exponent and fractional parts.
;	If the exponent is between -2 and +2, the logarithm of the fraction,
;	setting y = f - 1, is approximated by:
;
;			       2    3
;	loge(1+y) = y - 0.5 * y  + y * P(y)/Q(y) 
;
;	otherwise, setting y = 2(f - 1)/(f + 1), is approximated by:
;
;		       3			2
;	loge(f) = y + y * R(z)/S(z), where z = y
;
;------
cmnlog:
;------
	bit	facst		; fac must be valid and > 0
	bpl	?ckz
	bvs	?er		; fac=nan so return nan
	bit	facsgn		; if fac=+inf...
	bpl	?er		; ...return +inf...
	bmi	?nan		; ...else return nan
?ckz:	bvs	?inf		; if fac=0 return -inf
	bit	facsgn		; if fac>0 go to evaluation...
	bpl	?go		; ...else return nan
?nan:	jsr	fldnan		; return nan
	bra	?er
?inf:	lda	#$FF		; return -inf
	sta	facsgn
	jsr	fldinf
?er:	pla			; skip return address
	pla
	sec			; return invalid result
	rts
?go:	jsr	logscl		; argument reduction & exponent extraction
	php			; save carry (cf=0 if |exponent| < 3)
	jsr	mvf_t0		; tfr0=f
	jsr	fsubone		; fac=y=f-1
	plp
	bcc	lgep1		; if |exponent| < 3 evaluate for (1+f)

; lge - approximate loge(f)
;
;		       3			2
;	loge(f) = y + y * R(z)/S(z), where z = y
;
;	y = 2(f - 1)/(f + 1)
;
;---
lge:
;---
	jsr	mvf_t1		; tfr1=y=f-1
	jsr	mvt0_f		; fac=f
	jsr	faddone		; fac=f+1
	jsr	mvt1_a		; arg=f-1
	jsr	fpdiv		; (f-1)/(f+1)
	ACC16
	lda	facexp
	beq	?isz		; y=0
	inc	a		; note that here y is always normal
	inc	facexp		; y=2*(x-1)/(x+1)
?isz:	ACC08
	jsr	mvf_t1		; tfr1=y
	jsr	fsquare		; z=y*y
	jsr	mvf_t0		; tfr0=z
	lda	#<clnr
	ldy	#>clnr
	ldx	#5
	jsr	peval		; evaluate R(z)
	jsr	mvf_t2		; tfr2=R(z)
	lda	#<clns
	ldy	#>clns
	ldx	#5
	jsr	pevalp1		; evaluate S(z)
	jsr	mvt2_a		; arg=R(z)
	jsr	fpdiv		; R(z)/S(z)
	jsr	mvt0_a		; arg=z
	jsr	fpmult		; z*R(z)/S(z)
	jsr	mvt1_a		; arg=y
	jsr	fpmult		; y*z*R(z)/S(z)
	jsr	mvt1_a		; arg=y
	jmp	fpadd		; loge(f)=y+y*z*R(z)/S(z)
	
; lgep1 - approximate loge(1+y)
;
;			       2    3
;	loge(1+y) = y - 0.5 * y  + y * P(y)/Q(y) 
;
;	y = f - 1
;
;-----
lgep1:
;-----
	jsr	mvf_t0		; tfr0=y=x-1		
	jsr	fsquare		; z=y*y
	jsr	mvf_t1		; tfr1=z
	lda	#<clnp
	ldy	#>clnp
	ldx	#12
	jsr	peval		; evaluate P(y)
	jsr	mvf_t2		; tfr2=P(y)
	lda	#<clnq
	ldy	#>clnq
	ldx	#11
	jsr	pevalp1		; evaluate Q(y)
	jsr	mvt2_a		; P(y)
	jsr	fpdiv		; P(y)/Q(y)
	jsr	mvt1_a		; z
	jsr	fpmult		; z*P(y)/Q(y)
	jsr	mvt0_a		; y
	jsr	fpmult		; y*z*P(y)/Q(y)
	jsr	mvt1_a		; z
	ACC16
	lda	argexp
	beq	?isz		; z=0
	dec	a
	sta	argexp		; z/2
?isz:	ACC08
	lda	#$FF
	sta	argsgn		; arg=-z/2
	jsr	fpadd		; y*z*(P(y)/Q(y)) - z/2 
	jsr	mvt0_a		; arg=y
	jmp	fpadd		; loge(1+y)=y-z/2+y*z*(P(y)/Q(y))

; logscl - argument reduction for logarithm evaluation
;
;	entry:
;		fac = x, valid float
;
;	exit:
;		fac = f, reduced argument
;		scexp = |M|, exponent
;		scsgn = sign of M
;		CF = 0 if |M| < 3
;
;			 M
;		x = f * 2	sqrt(2)/2 <= f < sqrt(2)
;
;------
logscl:
;------
	jsr	frexp		; now 0.5 <= fac < 1
	lda	#<rsqrt2h	; now compare fac vs. 1/sqrt(2)
	ldy	#>rsqrt2h
	jsr	fccmp
	ACC16
	beq	?gte		; fac=1/sqrt(2)
	bpl	?gte		; fac>1/sqrt(2)
	inc	facexp		; fac=fac*2, now 1 <= fac < sqrt(2)
	dec	scexp		; decrement exponent
?gte:	ldx	#0		; assume positive scaling exponent
	lda	scexp
	bpl	?mp		; positive or null scaling
	dex			; negative scaling
	eor	#$FFFF		; complement
	inc	a
	sta	scexp		; unsigned scaling exponent
?mp:	stx	scsgn		; sign of scaling exponent
	cmp	#3		; return CF = 0 if |exponent| < 3
	ACC08
	rts

; unrounded 1/sqrt(2) - $B504F333F9DE6484597D89B3754ABE9FP3FFE
sqrth:	.BYTE	$9F,$BE,$4A,$75,$B3,$89,$7D,$59,$84
	.BYTE	$64,$DE,$F9,$33,$F3,$04,$B5,$FE,$3F

; 1/sqrt(2) rounded to 113 bits
rsqrt2h:
	.BYTE	$00,$80,$4A,$75,$B3,$89,$7D,$59,$84
	.BYTE	$64,$DE,$F9,$33,$F3,$04,$B5,$FE,$3F

; coefficients for log(x), rational function R()/S()
clnr:
; R[5] = -8.828896441624934385266096344596648080902E-1
	.BYTE	$8E,$15,$84,$6B,$67,$72,$AA,$CE,$23
	.BYTE	$34,$AD,$A7,$43,$0E,$05,$E2,$FE,$BF
; R[4] =  8.057002716646055371965756206836056074715E1
	.BYTE	$14,$20,$14,$FB,$86,$D1,$08,$AB,$2D
	.BYTE	$2B,$8F,$CB,$99,$DA,$23,$A1,$05,$40
; R[3] = -2.024301798136027039250415126250455056397E3
	.BYTE	$BC,$EF,$D7,$01,$BF,$A2,$EE,$76,$48
	.BYTE	$5B,$87,$90,$54,$A8,$09,$FD,$09,$C0
; R[2] =  2.048819892795278657810231591630928516206E4
	.BYTE	$1C,$CC,$E3,$20,$15,$6E,$6A,$18,$09
	.BYTE	$F5,$76,$E2,$D9,$65,$10,$A0,$0D,$40
; R[1] = -8.977257995689735303686582344659576526998E4
	.BYTE	$37,$36,$95,$61,$03,$74,$9D,$2E,$47
	.BYTE	$9C,$11,$07,$3C,$4A,$56,$AF,$0F,$C0
; R[0] = 1.418134209872192732479751274970992665513E5
	.BYTE	$A8,$4A,$7E,$5A,$28,$99,$7D,$53,$01
	.BYTE	$B4,$60,$74,$F1,$5A,$7D,$8A,$10,$40

clns:
; S[5] = -1.186359407982897997337150403816839480438E2
	.BYTE	$3A,$6E,$31,$96,$EA,$56,$BE,$E6,$BA
	.BYTE	$92,$B1,$45,$08,$9A,$45,$ED,$05,$C0
; S[4] =  3.998526750980007367835804959888064681098E3
	.BYTE	$C4,$2A,$76,$05,$E9,$F4,$A8,$5F,$11
	.BYTE	$48,$84,$6F,$92,$6D,$E8,$F9,$0A,$40
; S[3] = -5.748542087379434595104154610899551484314E4
	.BYTE	$36,$79,$3E,$93,$5D,$19,$08,$FE,$93
	.BYTE	$75,$8E,$62,$BE,$6B,$8D,$E0,$0E,$C0
; S[2] =  4.001557694070773974936904547424676279307E5
	.BYTE	$36,$7C,$5E,$8E,$90,$52,$EB,$2D,$76
	.BYTE	$57,$97,$FB,$9E,$78,$63,$C3,$11,$40
; S[1] = -1.332535117259762928288745111081235577029E6
	.BYTE	$E8,$C3,$BB,$00,$81,$59,$F2,$48,$4F
	.BYTE	$F7,$E2,$25,$F0,$B8,$A9,$A2,$13,$C0
; S[0] =  1.701761051846631278975701529965589676574E6
	.BYTE	$68,$05,$98,$8B,$BC,$65,$3C,$FD,$01
	.BYTE	$0E,$91,$2E,$6A,$08,$BC,$CF,$13,$40

; coefficients for log(1+x), rational function P()/Q()
clnp:	
; P[12] =  1.538612243596254322971797716843006400388E-6
	.BYTE	$2A,$C3,$7D,$B0,$42,$00,$91,$A4,$A1
	.BYTE	$4A,$C1,$76,$6B,$50,$82,$CE,$EB,$3F
; P[11] =  4.998469661968096229986658302195402690910E-1
	.BYTE	$6C,$FE,$CF,$17,$46,$8D,$F4,$5A,$4E
	.BYTE	$17,$E6,$A3,$09,$F1,$EB,$FF,$FD,$3F
; P[10] =  2.321125933898420063925789532045674660756E1
	.BYTE	$DD,$55,$73,$C9,$52,$31,$F5,$21,$A6
	.BYTE	$33,$4B,$7F,$BC,$A8,$B0,$B9,$03,$40
; P[09] =  4.114517881637811823002128927449878962058E2
	.BYTE	$62,$F5,$AF,$82,$FE,$EA,$8A,$CB,$29
	.BYTE	$7D,$14,$CE,$31,$D4,$B9,$CD,$07,$40
; P[08] =  3.824952356185897735160588078446136783779E3
	.BYTE	$98,$15,$15,$FD,$5B,$9C,$06,$E3,$62
	.BYTE	$2F,$09,$D7,$D9,$3C,$0F,$EF,$0A,$40
; P[07] =  2.128857716871515081352991964243375186031E4
	.BYTE	$61,$2D,$76,$77,$32,$6D,$65,$F8,$B4
	.BYTE	$B1,$67,$A8,$82,$27,$51,$A6,$0D,$40
; P[06] =  7.594356839258970405033155585486712125861E4
	.BYTE	$F5,$CF,$31,$FA,$60,$22,$5B,$82,$A8
	.BYTE	$08,$A0,$16,$C1,$C8,$53,$94,$0F,$40
; P[05] =  1.797628303815655343403735250238293741397E5
	.BYTE	$D2,$08,$FC,$D7,$90,$40,$A4,$21,$F6
	.BYTE	$CA,$B8,$F8,$24,$B5,$8C,$AF,$10,$40
; P[04] =  2.854829159639697837788887080758954924001E5
	.BYTE	$98,$EA,$19,$A8,$D5,$B8,$B8,$25,$24
	.BYTE	$D1,$AB,$93,$4F,$5D,$65,$8B,$11,$40
; P[03] =  3.007007295140399532324943111654767187848E5
	.BYTE	$96,$EF,$0E,$45,$35,$32,$FC,$95,$4D
	.BYTE	$F2,$D3,$2D,$58,$97,$D3,$92,$11,$40
; P[02] =  2.014652742082537582487669938141683759923E5
	.BYTE	$5E,$E2,$69,$C5,$8D,$BE,$39,$2E,$D6
	.BYTE	$8B,$C6,$A0,$8C,$51,$BE,$C4,$10,$40
; P[01] =  7.771154681358524243729929227226708890930E4
	.BYTE	$AE,$E9,$03,$6A,$3B,$ED,$92,$AC,$F8
	.BYTE	$CF,$D0,$FC,$FD,$C5,$C7,$97,$0F,$40
; P[00] =  1.313572404063446165910279910527789794488E4
	.BYTE	$35,$07,$BE,$83,$BC,$26,$2A,$5C,$A0
	.BYTE	$F3,$77,$E8,$6A,$E5,$3E,$CD,$0C,$40
		
clnq:
; Q[11] =  4.839208193348159620282142911143429644326E1
	.BYTE	$19,$97,$D2,$BF,$46,$56,$ED,$89,$10
	.BYTE	$A5,$9F,$26,$ED,$7D,$91,$C1,$04,$40
; Q[10] =  9.104928120962988414618126155557301584078E2
	.BYTE	$C0,$4E,$B7,$7A,$BC,$63,$F1,$97,$7D
	.BYTE	$4F,$2B,$BF,$3B,$8A,$9F,$E3,$08,$40
; Q[09] =  9.147150349299596453976674231612674085381E3
	.BYTE	$E1,$52,$82,$D3,$69,$1A,$6A,$4C,$1D
	.BYTE	$F9,$B2,$2A,$F5,$99,$EC,$8E,$0C,$40
; Q[08] =  5.605842085972455027590989944010492125825E4
	.BYTE	$B8,$65,$30,$7A,$BB,$1D,$CD,$02,$A2
	.BYTE	$25,$81,$76,$BD,$6B,$FA,$DA,$0E,$40
; Q[07] =  2.248234257620569139969141618556349415120E5
	.BYTE	$A2,$CA,$5D,$F8,$7F,$A4,$A6,$11,$B1
	.BYTE	$94,$7F,$AF,$3F,$DB,$8D,$DB,$10,$40
; Q[06] =  6.132189329546557743179177159925690841200E5
	.BYTE	$7A,$44,$71,$27,$79,$DE,$89,$E3,$39
	.BYTE	$73,$DC,$61,$ED,$2E,$B6,$95,$12,$40
; Q[05] =  1.158019977462989115839826904108208787040E6
	.BYTE	$2A,$BB,$38,$BE,$F1,$46,$B7,$69,$6C
	.BYTE	$9A,$1D,$D8,$D1,$1F,$5C,$8D,$13,$40
; Q[04] =  1.514882452993549494932585972882995548426E6
	.BYTE	$C0,$3A,$8A,$D9,$4A,$87,$5D,$9C,$09
	.BYTE	$03,$15,$BB,$9F,$13,$EC,$B8,$13,$40
; Q[03] =  1.347518538384329112529391120390701166528E6
	.BYTE	$70,$CA,$B9,$8E,$83,$73,$EC,$DA,$BC
	.BYTE	$71,$71,$9C,$4E,$F4,$7D,$A4,$13,$40
; Q[02] =  7.777690340007566932935753241556479363645E5
	.BYTE	$10,$A8,$3B,$99,$11,$F5,$D7,$57,$97
	.BYTE	$A0,$60,$44,$8B,$90,$E2,$BD,$12,$40
; Q[01] =  2.626900195321832660448791748036714883242E5
	.BYTE	$97,$4B,$94,$D0,$A5,$28,$E9,$C7,$1B
	.BYTE	$0B,$F5,$01,$A0,$40,$44,$80,$11,$40
; Q[00] =  3.940717212190338497730839731583397586124E4
	.BYTE	$95,$DD,$E4,$62,$0D,$9D,$1F,$45,$B8
	.BYTE	$F6,$59,$2E,$10,$2C,$EF,$99,$0E,$40

; C1 + C2 = loge(2) (splitted in two)
; C1 = 6.93145751953125E-1
ln2c1:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$72,$B1,$FE,$3F

; C2 = 1.428606820309417232121458176568075500134E-6
ln2c2:	.BYTE	$98,$07,$7A,$B5,$97,$1F,$C0,$9C,$1D
	.BYTE	$4F,$5E,$CD,$7B,$8E,$BE,$BF,$EB,$3F

; ln(2) = 0.6931471805599453094172321214581765680755001
cln2:	.BYTE	$AF,$F6,$F2,$03,$98,$B3,$E3,$C9,$AB
	.BYTE	$79,$CF,$D1,$F7,$17,$72,$B1,$FE,$3F

; log10(2) = l102a + l102b (splitted in two)
; l102a = 0.3125
l102a:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$A0,$FD,$3F

; l102b = -1.14700043360188047862611052755069732318101185E-2
l102b:	.BYTE	$F8,$D0,$6D,$90,$7E,$CA,$D4,$0E,$EE
	.BYTE	$0C,$01,$86,$60,$AF,$EC,$BB,$F8,$BF

; log10(e) = l10ea + l10eb (splitted in two)
; l10ea = 0.5
l10ea:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$80,$FE,$3F
; l10eb = -6.570551809674817234887108108339491770560299E-2
l10eb:	.BYTE	$36,$8F,$30,$4B,$41,$55,$91,$2A,$AB
	.BYTE	$39,$5E,$23,$5B,$9D,$90,$86,$FB,$BF

; log2(e) = 1/loge(2)
; lg2e = 1.442695040888963407359924681001892137426646
lg2e:	.BYTE	$86,$3E,$1D,$69,$D0,$FE,$87,$BE,$BB
	.BYTE	$F0,$17,$5C,$29,$3B,$AA,$B8,$FF,$3F

;----------------------------------------------------------------------------
; exponential family functions
;----------------------------------------------------------------------------

; fexp2 - return 2 raised to the x power
;
;	entry:
;		fac = x
;
;	exit:          x
;		fac = 2
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 50ms at 4MHz (4ms for integer argument)
;
;-----
fexp2:
;-----
	bit	facst
	bpl	?fv		; fac is valid
	bvc	?er		; fac=nan so return nan
	bit	facsgn
	bpl	?er		; fac=+inf so return +inf
?zz:	stz	facsgn		; fac=-inf so return 0
	jmp	fldz
?er:	sec
	rts
?fv:	jsr	frndm
	bit	facsgn
	bmi	?xn		; x is negative
	lda	#<maxl2		; check if argument can cause overflow
	ldy	#>maxl2
	jsr	fccmp
	bmi	?ok		; if x < maxl2 then no overflow
	beq	?ok
	jmp	fldinf		; overflow so return +inf
?xn:	lda	#<minl2		; check if argument can cause underflow
	ldy	#>minl2
	jsr	fccmp
	bmi	?zz		; if x < minl2 then underflow
?ok:	ACC16
	stz	fcpc0		; log2(2) = 1
	stz	fcpc1
	stz	fcpc2
	lda	#ce2p		; P coefficients
	sta	fcpp
	lda	#ce2q		; Q coefficients
	sta	fcpq
	ldx	#4		; P: degree 4
	stx	fcpd
	stx	fcqd		; Q: degree 4
	ACC08
	lda	#$FF		; Q polynomial N+1
	jmp	expev

; fexp - return e raised to the x power
;
;	entry:
;		fac = x
;
;	exit:          x
;		fac = e
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 60ms at 4MHz
;
;----
fexp:
;----
	bit	facst
	bit	facst
	bpl	?fv		; fac is valid
	bvc	?er		; fac=nan so return nan
	bit	facsgn
	bpl	?er		; fac=+inf so return +inf
?zz:	stz	facsgn		; fac=-inf so return 0
	jmp	fldz
?er:	sec
	rts
?fv:	jsr	frndm
	bit	facsgn
	bmi	?xn		; x is negative
	lda	#<maxln		; check if argument can cause overflow
	ldy	#>maxln
	jsr	fccmp
	bmi	?ok		; if x <= maxln then no overflow
	beq	?ok
	jmp	fldinf		; overflow so return +inf
?xn:	lda	#<minln		; check if argument can cause underflow
	ldy	#>minln
	jsr	fccmp
	bmi	?zz		; if x < minln then underflow
?ok:	ACC16
	lda	#lg2e		; log2(e)
	sta	fcpc0
	lda	#ln2c1		; loge(2) first piece
	sta	fcpc1
	lda	#ln2c2		; loge(2) 2nd piece
	sta	fcpc2
	lda	#ceep		; P coefficients
	sta	fcpp
	lda	#ceeq		; Q coefficients
	sta	fcpq
	ldx	#4		; P: degree 4
	stx	fcpd
	inx
	stx	fcqd		; Q: degree 5
	ACC08
	lda	#$00		; Q polynomial N
	bra	expev

; fexp10 - return 10 raised to the x power
;
;	entry:
;		fac = x
;
;	exit:           x
;		fac = 10
;		CF = 1 if invalid result (nan, inf)
;
;	computation mean time: 65ms at 4MHz
;
;------
fexp10:
;------
	bit	facst
	bpl	?fv		; fac is valid
	bvc	?er		; fac=nan so return nan
	bit	facsgn
	bpl	?er		; fac=+inf so return +inf
?zz:	stz	facsgn		; fac=-inf so return 0
	jmp	fldz
?er:	sec
	rts
?fv:	jsr	frndm
	bit	facsgn
	bmi	?xn		; x is negative
	lda	#<maxl10	; check if argument can cause overflow
	ldy	#>maxl10
	jsr	fccmp
	bmi	?ok		; if x <= maxl10 then no overflow
	beq	?ok
	jmp	fldinf		; overflow so return +inf
?xn:	lda	#<minl10	; check if argument can cause underflow
	ldy	#>minl10
	jsr	fccmp
	bmi	?zz		; if x < minl10 then underflow
?ok:	ACC16
	lda	#lg210		; log2(10)
	sta	fcpc0
	lda	#lg102a		; log10(2) first piece
	sta	fcpc1
	lda	#lg102b		; log10(2) 2nd piece
	sta	fcpc2
	lda	#ce10p		; P coefficients
	sta	fcpp
	lda	#ce10q		; Q coefficients
	sta	fcpq
	ldx	#5		; degree
	stx	fcpd
	stx	fcqd
	ACC08
	lda	#$FF		; Q polynomial N+1
	
; expev - common exponential function evaluation
;
;	entry:
;		fac = x, valid argument
;		A = $00 if exp(x), otherwise A = $FF
;		fcpc0 = pointer to a constant = log2(b)
;		fcpc1 = pointer to a splitted constant = logb(2)
;		fcpc2 = pointer to a splitted constant = logb(2)
;		fcpp = pointer to P polynomial coefficients
;		fcpq = pointer to Q polynomial coefficients
;		fcpd = P polynomial degree
;		fcqd = Q polynomial degree
;
;	exit:	       x	       
;		fac = b   , where b=e or b=10 or b=2
;
; strategy:
;
;	Range reduction is accomplished by separating the argument x into
;	an integer M and a fraction f such that:
;
;		 x     f    M
;		b   = b  * 2    where |f| < 0.5 * log (2)
;						     b
;                                                                     f 
;	A rational function (Pade' form) is then used to approximate b   in
;	the basic range [-0.5 * log (2), +0.5 * log (2)]:
;				   b		   b
;
;		 f               P(z)                    2
;		b   = 1 + 2f -------------    where z = f
;			      Q(z) - fP(Z)	
;
;	Finally, get the result scaling the approximate exponential of the
;	fraction by a power of two:
;
;		 x     f    M
;		b   = b  * 2  
;
; Note:
; Error amplification in the exponential function can be a serious matter.
; The error propagation involves exp(x(1+delta)) = exp(x)(1 + x*delta + ...),
; which shows that a 1 lsb error in representing x produces a relative error
; of x times 1 lsb in the function.
; While the routine gives an accurate result for arguments that are exactly 
; represented by a long double precision number, the result contains amplified 
; roundoff error for large arguments not exactly represented.
;
;-----
expev:
;-----
	sta	fcpolf		; Q polynomial flag degree N+1
	jsr	mvf_t1		; tfr1=x (save argument)
	lda	fcpc0		; x * log2(b) (logarithm base 2 of b)
	tax
	ora	fcpc0+1		; if b=2 skip this multiplication
	beq	?no2
	txa
	ldy	fcpc0+1
	jsr	fcmult		; x*log2(b)
?no2:	jsr	faddhalf	; x*log2(b) + 0.5 (floor truncate toward -inf)
	jsr	floor		; get integral part w = floor(x*log2(b) + 0.5)
	jsr	mvf_t0		; tfr0=w
	jsr	uitrunc		; convert w to integer 16 bit
	ACC16
	lda	tm
	ldx	facsgn		; sign of M
	bpl	?mp
	eor	#$FFFF
	inc	a
?mp:	sta	scexp		; scexp=M (for final scaling)
	ACC08
	
	; now compute x - logb(2)*w, the remainder of x/w 
	jsr	mvt0_f		; fac=w
	lda	fcpc1		; pointer to first piece of splitted -logb(2)
	tax
	ora	fcpc1+1		; if b=2 skip this multiplication
	beq	?skp		; if b=2 the remainder is: x-w
	txa
	ldy	fcpc1+1		; logb(2) is splitted in two pieces
	jsr	fcmult		; first piece
	jsr	mvt1_a		; arg=x
	jsr	fpsub
	jsr	mvf_t1		; tfr1=x-c1
	jsr	mvt0_f		; fac=w	
	lda	fcpc2
	ldy	fcpc2+1
	jsr	fcmult		; 2nd piece
?skp:	jsr	mvt1_a		; arg=x-c1
	jsr	fpsub		; x-c1-c2 = x - logb(2)*w
	
	; now we have fac = f = x - logb(2)*w, the fraction part
	; where: |f| < 0.5*logb(2), and we approximate exponential of fraction
	jsr	mvf_t1		; tfr1=f
	jsr	fsquare		; z=f*f
	jsr	mvf_t0		; tfr0=z
	lda	fcpp		; pointer to P(z) coefficients
	ldy	fcpp+1
	ldx	fcpd		; P(z) degree
	jsr	peval		; evaluate P(z)
	jsr	mvt1_a		; arg=f
	jsr	fpmult		; f*P(z)
	jsr	mvf_t2		; tfr2=f*P(z)
	lda	fcpq		; pointer to Q(z) coefficients
	ldy	fcpq+1
	ldx	fcqd		; Q(z) dregree
	bit	fcpolf
	bpl	?dn		; exp(x)
	jsr	pevalp1		; evaluate Q(z) for exp10(x) & exp2(x)	
	bra	?dn2
?dn:	jsr	peval		; evaluate Q(z) for exp(x)	
?dn2:	jsr	mvt2_a
	lda	argsgn
	eor	#$FF
	sta	argsgn		; arg=-f*P(z)
	jsr	fpadd		; fac = Q(z) - f*P(z)
	jsr	mvt2_a		; arg = f*P(z)
	jsr	fpdiv		; y=f*P(z)/(Q(z) - f*P(z))
	jsr	mvf_t0		; tfr0=y
	jsr	faddone		; 1+y
	jsr	mvt0_a
	jsr	fpadd		; 1+y+y=1+2*y = 1 + 2*f*P(z)/(Q(z) - f*P(z))
	jmp	fscale		; scale by M, return exponential

; fexpm1 - return e raised to the x power, minus 1
;
;	entry:
;		fac = x
;
;	exit:          x
;		fac = e  - 1
;		CF = 1 if invalid result (nan, inf)
;
; For small magnitude values of x, expm1 may be more accurate than exp(x) - 1
;
; strategy:
;
;	Range reduction is accomplished by separating the argument x into
;	an integer M and a fraction f such that:
;
;		 x     f    M
;		e   = e  * 2    where |f| < 0.5 * log (2)
;						     e
;							 f
;	A rational function is then used to approximate e  - 1 in
;	the basic range [-0.5 * log (2), +0.5 * log (2)]:
;				   e		   e
;
;		 f               2    3  P(f)	     f
;		e  - 1 = f + 0.5f  + f  ------ = y, e  = y + 1
;			                 Q(f)	
;
;	Finally, get the result scaling the approximate exponential of the
;	fraction by a power of two:
;
;		 x    f    M		 M
;		e  = e  * 2   = (y + 1)*2	so:
;
;		 x             M    M
;		e  - 1 =  y * 2  + 2  - 1
;
;	computation mean time: 90ms at 4MHz
;
;------
fexpm1:
;------
	bit	facst
	bpl	?fv		; fac is valid
	bvs	?er		; fac=nan so return nan
	bit	facsgn
	bpl	?er		; fac=+inf so return +inf
?m1:	jmp	fldm1		; fac=-inf so return -1
?er:	sec
	rts
?fv:	jsr	frndm
	bit	facsgn
	bmi	?xn		; x is negative
	lda	#<maxln		; check if argument can cause overflow
	ldy	#>maxln
	jsr	fccmp
	bmi	?ok		; if x <= maxln then no overflow
	beq	?ok
	jmp	fldinf		; overflow so return +inf
?xn:	lda	#<mxm1		; check if argument can cause underflow
	ldy	#>mxm1
	jsr	fccmp
	bmi	?m1		; if x < mxm1 then underflow, return -1
?ok:	jsr	mvf_t0		; tfr0=x
	lda	#<lg2e		; x*log2(e)
	ldy	#>lg2e
	jsr	fcmult
	jsr	faddhalf	; express x = ln 2 (M + remainder)...
	jsr	floor		; ...remainder not exceeding 1/2.
	jsr	mvf_t1		; tfr1=w=integral part
	jsr	uitrunc		; convert to integer
	ACC16
	lda	tm
	ldx	facsgn		; sign of M
	bpl	?mp
	eor	#$FFFF
	inc	a
?mp:	sta	scexp		; scexp=M (for final scaling)
	ACC08
	jsr	mvt1_f		
	lda	#<ln2c1		; remainder times loge(2) 
	ldy	#>ln2c1
	jsr	fcmult
	jsr	mvt0_a
	jsr	fpsub
	jsr	mvf_t0
	jsr	mvt1_f	
	lda	#<ln2c2
	ldy	#>ln2c2
	jsr	fcmult
	jsr	mvt0_a
	jsr	fpsub
	jsr	mvf_t0		; tfr0=f=fraction
	jsr	fsquare
	jsr	mvf_t1		; tfr1=f*f
	lda	#<cem1p
	ldy	#>cem1p
	ldx	#7
	jsr	peval		; evaluate P(f)
	jsr	mvt1_a
	jsr	fpmult		; f*f*P(f)
	jsr	mvt0_a
	jsr	fpmult		; f*f*f*P(f)
	jsr	mvf_t2		; tfr2=f*f*f*P(f)
	lda	#<cem1q
	ldy	#>cem1q
	ldx	#7
	jsr	pevalp1		; evaluate Q(f)
	jsr	mvt2_a
	jsr	fpdiv		; f*f*f*P(f)/Q(f)
	jsr	mvt1_a		; f*f
	ACC16
	lda	argexp
	beq	?isz
	dec	a
	sta	argexp		; f*f/2
?isz:	ACC08
	jsr	fpadd
	jsr	mvt0_a		; arg=f
	jsr	fpadd
	jsr	mvf_t0		; tfr0=y=f + 0.5*f*f + f*f*f*P(f)/Q(f)
	jsr	fldp1		; fac=+1
	jsr	fscale		; 2^M	
	jsr	mvf_t1		; tfr1=2^M
	jsr	mvt0_a		; tfr0=y
	jsr	fpmult		; y*2^M
	jsr	mvf_t0
	jsr	mvt1_f		; 2^M
	jsr	fsubone		; 2^M - 1
	jsr	mvt0_a
	jmp	fpadd		; y*2^M + 2^M - 1

; fpown - return the argument x raised to the nth power
;
;	entry:
;		fac = x
;		C = N (signed integer)
;
;	exit:          N
;		fac = x
;		CF = 1 if invalid result (nan, inf)
;
; The routine decomposes N as a sum of powers of two.
; The desired power is a product of two-to-the-kth powers of x.
; Max. multiplications number (if N=32767) = 28
;
;	computation mean time: max. 30ms at 4MHz
;
;-----
fpown:
;-----
	stz	scsgn		; assume positive N
	ACC16
	bit	#$8000
	beq	?np		; N>=0
	eor	#$FFFF		; two's complement
	inc	a
	ldx	#$80
	stx	scsgn		; N<0
?np:	sta	scexp		; store N
	ora	#0
	ACC08
	bne	?nz
	lda	#$40
	tsb	scsgn		; flag: N=0
?nz:	bit	facst		; fac test
	bpl	?fv		; fac is valid
	bvs	?er		; fac=nan, so return nan
	bit	scsgn
	bvs	?p1		; fac=inf: if N=0 return 1
	bmi	?zz		; fac=inf, N<0, so return zero
	bit	facsgn
	bpl	?er		; +inf raised to +n, so return +inf
	lda	scexp		; test if N is odd
	lsr	a
	bcs	?er		; fac=-inf, N is odd, so return -inf
	stz	facsgn		; fac=-inf, N is even, so return +inf
?er:	sec			; exit with invalid flag (nar or inf)
?rts:	rts
?zz:	jmp	fldz		; set fac=0 and exit
?p1:	jmp	fldp1		; set fac=1 and exit
?fv:	bit	scsgn
	bvs	?p1		; fac is valid, N=0, so return 1
	lda	facsgn
	sta	dsgn		; save fac sign and result sign
	stz	facsgn		; fac=|x|
	jsr	mvf_t0		; tfr0=w=|x|
	lda	scexp
	lsr	a
	bcs	?go		; N is odd, set y=|x|
	jsr	fldp1		; N is even so set y=1
	stz	dsgn		; N is even so result is positive 
?go:	jsr	mvf_t1		; tfro=y
?ll:	ACC16
	lsr	scexp		; shift N
	ACC08
	beq	?eol		; end of loop
	php
	jsr	mvt0_f		; w
	jsr	fsquare		; w=w*w, arg to the 2-to-the-kth power
	bcs	?of		; overflow
	jsr	mvf_t0		; tfr0=w
	plp
	bcc	?ll		; loop
	jsr	mvt1_a		; y (include in product if N odd)
	jsr	fpmult
	bcs	?of		; overflow
	jsr	mvf_t1		; tfr1=y
	bra	?ll		; loop
?of:	plp
?eol:	lda	dsgn		; set fac sign
	sta	facsgn
	clc
	bit	facst
	bpl	?ok
	sec			; fac=inf
?ok:	bit	scsgn
	bpl	?rts		; done if N>0
	bcs	?zz		; y=inf so return 0
	jsr	ldaone
	jmp	fpdiv		; y=1/y

; frootn - return the nth root of the argument
;
;	entry:
;		fac = x
;		C = N (integer, N>0)
;
;	exit:          		    1/N
;		fac = nthroot(x) = x
;		CF = 1 if invalid result (nan, inf)
;
; method:
;
;	 1/N      log2(x)/N
;	x     =  2
; 
;	computation mean time: 140ms at 4MHz
;
;------
frootn:
;------
	stz	scsgn		; assume N even
	ACC16
	bit	#$8000
	beq	?pos		; N>=0
	eor	#$FFFF		; two's complement
	inc	a
	ldx	#$FF		; N<0
?pos:	sta	scexp		; store N
	ora	#0
	ACC08
	beq	?nan		; return nan if N=0
	inx			; return nan if N<0
	bne	?ok
?nan:	jmp	fldnan		
?ok:	lsr	a		; N odd?
	bcc	?ev		; no
	lda	#$FF
	sta	scsgn		; flag N odd
?ev:	bit	facst		; fac test
	bpl	?fv		; fac is valid
	bvs	?er		; fac=nan, so return nan
	bit	facsgn
	bpl	?er		; fac=+inf so return +inf
	bit	scsgn		; if N is even and fac=-inf...
	bvc	?nan		; ...return nan
?er:	sec			; exit with invalid flag (nar or inf)
	rts
?fv:	bvc	?nz		; fac <> 0
?z:	jmp	fldz		; if fac=0 return 0	
?nz:	lda	facsgn
	bpl	?gte0
	bit	scsgn		; if fac<0 and N is even...
	bvc	?nan		; ...return nan		
?gte0:	sta	dsgn
	ACC16
	lda	scexp
	cmp	#1
	ACC08
	clc
	beq	?rts	
	stz	facsgn		; fac=|x|
	lda	dsgn
	pha			; save fac sign and result sign
	lda	scexp+1
	pha
	lda	scexp
	pha
	jsr	flog2		; log2(x)
	bcc	?ok2
	bit	facsgn
	bpl	?rts
	bmi	?z		; returns zero
?ok2:	jsr	mvf_t2
	pla			; scexp low
	ply			; scexp high
	jsr	fldu16		; convert N to float
	pla
	sta	dsgn		; sign of the result
	jsr	mvt2_a		; log2(x)
	jsr	fpdiv		; log2(x)/N
	jsr	fexp2		; exp2(...)
	lda	dsgn
	sta	facsgn
?rts:	rts	

; fpowxy - return x raised to the yth power
;
;	entry:
;		fac = y
;		arg = x
;
;	exit:          y
;		fac = x
;		CF = 1 if invalid result (nan, inf)
;
; method:
;	1) for noninteger y or |y|>32767
;
;		 y	  y*log2(x)
;		x     =  2
;
;	2) for integer y, |y|<32768:
;
;		 y
;		x     = fpown(x, y)
;
;	computation mean time: max 200ms at 4MHz
;
;------
fpowxy:
;------
	lda	#$C0		; if x=nan or y=nan, return nan
	cmp	argst
	beq	?nan
	cmp	facst
	beq	?nan
	stz	powfg
	bit	facst
	bmi	?yinf		; y=+/-inf
	bvs	?1		; if y=0 return +1
	
	; here y is valid and not zero
	jsr	?yint		; check if y is integer -- fac=w=floor(y)
	bne	?rst		; y is not integer, restore arg&fac
	lda	#$80
	sta	powfg		; powfg<7>: y is integer
	jsr	uitrunc		; get w as 128 bit integer
	ACC16
	lda	tm+14
	ora	tm+12
	ora	tm+10
	ora	tm+8
	ora	tm+6
	ora	tm+4
	ora	tm+2
	bne	?ibig		; y is a big integer
	lda	tm
	cmp	#32768
	bcs	?ibig		; |w|>=32768, is a big integer
	ldx	facsgn		; w sign
	bpl	?pp		; w>0
	eor	#$FFFF		; two's complement
	inc	a
?pp:	sta	dexp
	ACC08
	jsr	mvt0_f		; fac=x
	lda	dexp+1		; y is integer and |y|<32768...
	xba
	lda	dexp
	jmp	fpown		; ...so call fpown
?nan:	jmp	fldnan		; return nan
?1:	jmp	fldp1		; return +1
?z:	jmp	fldz		; return 0
?ibig:	ACC08			; y is a big integer and we check if... 
				; ...is odd or even
	jsr	mvt1_f		; restore fac=y
	lda	#$FF
	sta	scexp
	sta	scexp+1		; scexp=-1
	jsr	fscale		; w=y/2
	jsr	floor		; w=floor(y/2)
	lda	#1
	sta	scexp
	stz	scexp+1		; scexp=1
	jsr	fscale		; w*2 = 2*floor(y/2)
	
	; if 2*floor(y/2) != y then y is an odd integer
	jsr	?cpy		; compare y vs. 2*floor(y/2)
	beq	?rst		; y is an even integer
	lda	#$40
	tsb	powfg		; powfg<6>: odd integer flag
?rst:	jsr	mvt0_a		; restore arg=x
	jsr	mvt1_f		; restore fac=y
	bra	?xtst		; go to check x

?yinf:	; y=+/-inf so check x
	bit	argst
	bpl	?xv		; x is valid
	bit	argsgn
	bmi	?nan		; if x=-inf and y=+-inf return nan
	bit	facsgn
	bmi	?z		; if x=+inf and y=-inf return 0
				; if x=+inf and y=inf return +inf
?pi:	stz	facsgn		; return +inf
	jmp	fldinf

?xv:	; y=+/-inf and valid x
	bvc	?nz		; x<>0
	bit	facsgn
	bpl	?z		; if x=0 and y=+inf return zero	
	bmi	?pi		; if x=0 and y=-inf return zero	

?nz:	; y=+/-inf and x<>0
	bit	argsgn
	bmi	?nan		; if x<0 and y=+-inf return nan
	jsr	?is1		; check if |x|=1
	beq	?nan		; if |x|=1 and y=+/-inf return nan
	bcc	?xm		; |x|<1
	bit	facsgn
	bpl	?pi		; if |x|>1 and y=+inf return +inf
	bmi	?z		; if |x|>1 and y=-inf return 0
?xm:	bit	facsgn
	bpl	?z		; if |x|<1 and y=+inf return 0
	bmi	?pi		; if |x|<1 and y=-inf return +inf

?xtst:	; here y is valid and y <> 0 so we check x
	bit	argst
	bpl	?xv2		; x is valid
	bit	argsgn
	bmi	?xmi		; x=-inf
	bit	facsgn
	bpl	?pi		; if x=+inf and y>0 return +inf
	bmi	?z		; if x=+inf and y<0 return 0

?xmi:	; x=-inf -- check if y is odd integer
	lda	powfg
	cmp	#$C0		; y must be odd integer
	bne	?nan
	lda	#$FF		; x=-inf and y is an odd integer...
	sta	facsgn
	jmp	fldinf		; ...so return -inf
	
?xv2:	; now both x and y are valid
	bvc	?xv3		; x<>0
	bit	facsgn
	bpl	?z		; if x=0 and y>0 return 0
	bmi	?pi		; if x=0 and y<0 return +inf
?xv3:	bit	argsgn
	bpl	?xv4		; x>0
	lda	powfg
	cmp	#$C0		; if x<0, y must be odd integer
	beq	?xv30
	jmp	fldnan
?xv30:	lda	#1
	tsb	powfg		; powfg<0>: x change sign
	stz	argsgn		; |x|
?xv4:	jsr	mvf_t3		; tfr3=y
	jsr	mvatof		; fac=x
	jsr	flog2		; log2(x)
	bcs	?end
	jsr	mvt3_a		; arg=y
	jsr	fpmult		; y*log2(x)
	bcs	?end
	jsr	fexp2		; 2^(y*log2(x))
?end:	lsr	powfg
	bcc	?e2
	lda	facsgn		; change sign to result
	eor	#$FF
	sta	facsgn
?e2:	rts

?is1:	; check if |arg|=1
	ACC16
	lda	argexp
	cmp	#EBIAS
	bne	?is0		; is not 1 (CF=1 if |arg|>=1)
	lda	argm+14
	cmp	#$8000
	bne	?is0		; is not 1
	lda	argm
	ora	argm+2
	ora	argm+4
	ora	argm+6
	ora	argm+8
	ora	argm+10
	ora	argm+12
?is0:	ACC08
	rts			; ZF=1 if |arg|=1, CF=1 if |arg|>=1

?yint:	jsr	mva_t0		; tfr0=x
	jsr	mvf_t1		; tfr1=y
	jsr	floor		; get the integral part of y
	
?cpy:	; compare fac vs. y/tfr1 (just for equality)
	ACC16
	lda	facm
	cmp	tfr1
	bne	?cp0
	lda	facm+2
	cmp	tfr1+2
	bne	?cp0
	lda	facm+4
	cmp	tfr1+4
	bne	?cp0
	lda	facm+6
	cmp	tfr1+6
	bne	?cp0
	lda	facm+8
	cmp	tfr1+8
	bne	?cp0
	lda	facm+10
	cmp	tfr1+10
	bne	?cp0
	lda	facm+12
	cmp	tfr1+12
	bne	?cp0
	lda	facm+14
	cmp	tfr1+14
	bne	?cp0
	lda	facm+16
	cmp	tfr1+16
	bne	?cp0
	lda	facm+18
	cmp	tfr1+18
?cp0:	ACC08
	rts			; ZF=1 if equal

; coefficients for exp() evaluation
ceep:
; P[4] = 3.279723985560247033712687707263393506266E-10
	.BYTE	$44,$59,$3A,$65,$81,$28,$53,$8A,$47
	.BYTE	$FE,$AA,$B3,$F9,$02,$4E,$B4,$DF,$3F
; P[3] =  6.141506007208645008909088812338454698548E-7
	.BYTE	$B0,$71,$8E,$FB,$B2,$D2,$28,$E7,$FF
	.BYTE	$4A,$4C,$8E,$A0,$1B,$DC,$A4,$EA,$3F
; P[2] =  2.708775201978218837374512615596512792224E-4
	.BYTE	$B6,$9E,$58,$BA,$61,$BA,$82,$D8,$A0
	.BYTE	$31,$FA,$48,$B9,$90,$04,$8E,$F3,$3F
; P[1] =  3.508710990737834361215404761139478627390E-2
	.BYTE	$D4,$0F,$B2,$5C,$74,$7D,$79,$81,$28
	.BYTE	$BF,$78,$03,$59,$80,$B7,$8F,$FA,$3F
; P[0] =  1 
	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$80,$FF,$3F

ceeq:
; Q[5] =  2.980756652081995192255342779918052538681E-12
	.BYTE	$AA,$EB,$58,$3C,$C8,$65,$82,$7C,$65
	.BYTE	$FB,$7E,$D8,$C6,$89,$C0,$D1,$D8,$3F
; Q[4] =  1.771372078166251484503904874657985291164E-8
	.BYTE	$F5,$58,$96,$76,$83,$9C,$A6,$21,$0D
	.BYTE	$1B,$F5,$F8,$49,$E2,$28,$98,$E5,$3F
; Q[3] =  1.504792651814944826817779302637284053660E-5
	.BYTE	$AE,$5F,$82,$3D,$77,$DC,$F3,$E4,$70
	.BYTE	$24,$62,$3D,$2E,$5A,$76,$FC,$EE,$3F
; Q[2] =  3.611828913847589925056132680618007270344E-3
	.BYTE	$68,$61,$9E,$E9,$6E,$9C,$AE,$2E,$1E
	.BYTE	$D4,$1F,$50,$10,$6F,$B4,$EC,$F6,$3F
; Q[1] =  2.368408864814233538909747618894558968880E-1
	.BYTE	$76,$96,$FC,$D8,$64,$69,$67,$EB,$3E
	.BYTE	$0A,$67,$2C,$D7,$6A,$86,$F2,$FC,$3F
; Q[0] =  2
	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$80,$00,$40

; coefficients for expm1() evaluation
cem1p:
; MP[7] = -4.888737542888633647784737721812546636240E-1
	.BYTE	$52,$E5,$66,$71,$85,$3C,$04,$05,$0D
	.BYTE	$8F,$39,$16,$25,$A9,$4D,$FA,$FD,$BF
; MP[6] = 4.401308817383362136048032038528753151144E1
	.BYTE	$84,$22,$38,$E7,$E0,$BC,$D7,$D9,$5B
	.BYTE	$AE,$51,$7A,$FC,$66,$0D,$B0,$04,$40
; MP[5] = -1.716772506388927649032068540558788106762E3
	.BYTE	$44,$3A,$92,$A3,$59,$97,$98,$46,$5F
	.BYTE	$A6,$8C,$51,$5F,$B8,$98,$D6,$09,$C0
; MP[4] = 4.578962475841642634225390068461943438441E4
	.BYTE	$C3,$21,$E0,$44,$63,$32,$45,$02,$AF
	.BYTE	$73,$E6,$2A,$F0,$9F,$DD,$B2,$0E,$40
; MP[3] = -7.212432713558031519943281748462837065308E5
	.BYTE	$12,$EA,$50,$4A,$6C,$00,$52,$CF,$E1
	.BYTE	$C1,$2E,$79,$57,$B4,$15,$B0,$12,$C0
; MP[2] = 8.944630806357575461578107295909719817253E6
	.BYTE	$20,$48,$52,$E0,$BA,$5E,$BC,$44,$7D
	.BYTE	$37,$73,$6D,$CE,$F6,$7B,$88,$16,$40
; MP[1] = -5.722847283900608941516165725053359168840E7
	.BYTE	$7C,$BD,$E1,$4B,$F3,$59,$CC,$B5,$CB
	.BYTE	$98,$46,$B2,$35,$2E,$4F,$DA,$18,$C0
; MP[0] = 2.943520915569954073888921213330863757240E8
	.BYTE	$12,$F3,$2E,$3D,$05,$16,$56,$0F,$16
	.BYTE	$02,$BA,$74,$DC,$A6,$5B,$8C,$1B,$40

cem1q:
; MQ[7] = -8.802340681794263968892934703309274564037E1
	.BYTE	$5B,$7E,$65,$0F,$E1,$0C,$75,$92,$24
	.BYTE	$56,$22,$7B,$FA,$FB,$0B,$B0,$05,$C0
; MQ[6] = 3.697714952261803935521187272204485251835E3
	.BYTE	$FE,$14,$1F,$B8,$5A,$2E,$44,$50,$D9
	.BYTE	$62,$6A,$C8,$71,$70,$1B,$E7,$0A,$40
; MQ[5] = -9.615511549171441430850103489315371768998E4
	.BYTE	$D6,$13,$D7,$2D,$65,$3A,$0E,$9C,$28
	.BYTE	$2F,$B8,$6E,$C8,$8E,$CD,$BB,$0F,$C0
; MQ[4] = 1.682912729190313538934190635536631941751E6
	.BYTE	$02,$77,$B9,$68,$7D,$29,$95,$7B,$AD
	.BYTE	$29,$BB,$61,$D5,$05,$6F,$CD,$13,$40
; MQ[3] = -2.019684072836541751428967854947019415698E7
	.BYTE	$CB,$B8,$14,$C8,$CF,$E5,$F5,$70,$E1
	.BYTE	$F7,$13,$3B,$5D,$F4,$16,$9A,$17,$C0
; MQ[2] = 1.615869009634292424463780387327037251069E8
	.BYTE	$1C,$14,$94,$07,$23,$62,$73,$13,$05
	.BYTE	$C8,$34,$6A,$4F,$ED,$19,$9A,$1A,$40
; MQ[1] = -7.848989743695296475743081255027098295771E8
	.BYTE	$DC,$5E,$0D,$28,$3F,$32,$AD,$EF,$DC
	.BYTE	$FA,$65,$7A,$79,$6E,$22,$BB,$1C,$C0
; MQ[0] = 1.766112549341972444333352727998584753865E9
	.BYTE	$D0,$35,$67,$DC,$07,$21,$01,$17,$21
	.BYTE	$03,$17,$AF,$4A,$7A,$89,$D2,$1D,$40

; maxln = 11356.523406294143949491931077970764
; above this value, exp(x) overflow
maxln:	.BYTE	$00,$80,$F2,$03,$98,$B3,$E3,$C9,$AB
	.BYTE	$79,$CF,$D1,$F7,$17,$72,$B1,$0C,$40

; minln = -1.143276959615573793352782661133116431383730e4
; below this value, exp(x) underflow
minln:	.BYTE	$45,$C0,$39,$B1,$F4,$B2,$26,$E9,$44
	.BYTE	$16,$C0,$03,$11,$14,$A3,$B2,$0C,$C0

; min. argument for expm1() -- below this value expm1() = -1 
; mxm1 = loge(2^-114) = -7.9018778583833765273564461846232128760607E1
mxm1:	.BYTE	$00,$80,$84,$63,$F3,$CB,$CE,$FF,$5C
	.BYTE	$C8,$DC,$B6,$58,$9D,$09,$9E,$05,$C0

; e = 2.7182818284590452353602874713526623  (35 digits)
ceul:	.BYTE	$00,$00,$3D,$27,$20,$56,$DC,$AF,$9A
	.BYTE	$4A,$BB,$A2,$58,$54,$F8,$AD,$00,$40

; coefficients for exp10() evaluation
ce10p:
; P[5] = 6.781965388610215141646963666801877147888E1
	.BYTE	$45,$E4,$3F,$51,$CF,$31,$82,$DB,$82
	.BYTE	$33,$B2,$95,$AC,$A9,$A3,$87,$05,$40
; P[4] = 4.930988843306627886355612005613845141123E4
	.BYTE	$D5,$25,$84,$99,$5A,$EB,$62,$D1,$4B
	.BYTE	$5A,$74,$59,$70,$E3,$9D,$C0,$0E,$40
; P[3] = 9.112966716416345527154611203937593471620E6
	.BYTE	$36,$62,$7E,$7C,$7A,$40,$20,$E5,$5B
	.BYTE	$C6,$0F,$67,$B7,$86,$0D,$8B,$16,$40
; P[2] = 5.880306836049276068401249115246879608067E8
	.BYTE	$2E,$0E,$F8,$F9,$5C,$1D,$B4,$4D,$7F
	.BYTE	$24,$72,$6B,$6E,$8B,$32,$8C,$1C,$40
; P[1] = 1.294143447497151402129871056524193102276E10
	.BYTE	$63,$CA,$AF,$6C,$10,$94,$56,$45,$25
	.BYTE	$49,$2D,$BE,$9A,$A7,$D7,$C0,$20,$40
; P[0] = 6.737236378815985929063482575381049393067E10
	.BYTE	$DC,$96,$E7,$F7,$15,$39,$D0,$93,$9D
	.BYTE	$C8,$8E,$C2,$00,$4B,$FB,$FA,$22,$40

ce10q:
; Q[5] = 2.269602544366008200564158516293459788943E3
	.BYTE	$58,$5C,$11,$75,$0B,$63,$2E,$D1,$F3
	.BYTE	$4E,$A6,$8F,$05,$A4,$D9,$8D,$0A,$40
; Q[4] = 7.712352920905011963059413773034169405418E5
	.BYTE	$18,$FC,$B0,$15,$D1,$8B,$DA,$20,$C4
	.BYTE	$E1,$16,$67,$AC,$34,$4A,$BC,$12,$40
; Q[3] = 8.312829542416079818945631366865677745737E7
	.BYTE	$22,$3B,$86,$E2,$A1,$37,$CF,$01,$8F
	.BYTE	$AA,$B9,$92,$ED,$FC,$8D,$9E,$19,$40
; Q[2] = 3.192530874297321568824835872165913128965E9
	.BYTE	$58,$36,$A6,$B4,$D3,$61,$82,$7F,$2E
	.BYTE	$44,$1D,$4C,$BA,$27,$4A,$BE,$1E,$40
; Q[1] = 3.709588725051672862074295071447979432510E10
	.BYTE	$D8,$CE,$E2,$0B,$30,$77,$F8,$EF,$3A
	.BYTE	$85,$44,$28,$19,$65,$31,$8A,$22,$40
; Q[0] = 5.851889165195258152098281616369230806944E10
	.BYTE	$58,$7C,$65,$00,$31,$77,$52,$F6,$1E
	.BYTE	$C6,$3D,$3F,$C8,$F6,$FF,$D9,$22,$40

; log10(2) = lg102a + lg102b = 3.0102999566398119521373889e-1
; lg102a = 3.01025390625e-1
lg102a:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$20,$9A,$FD,$3F
; lg102b = 4.6050389811952137388947244930267681898814621E-6
lg102b:	.BYTE	$AC,$26,$78,$91,$7C,$0B,$AC,$59,$89
	.BYTE	$8F,$98,$F7,$CF,$FB,$84,$9A,$ED,$3F

; log2(10) = 3.321928094887362347870319429489390175864831
lg210:	.BYTE	$4C,$DB,$AF,$4D,$FF,$F6,$2B,$49,$FE
	.BYTE	$8A,$1B,$CD,$4B,$78,$9A,$D4,$00,$40

; maxl10 = 4.9320754489586679023818980511660936429E3
maxl10:	.BYTE	$00,$80,$7C,$0B,$AC,$59,$89,$8F,$98
	.BYTE	$F7,$CF,$FB,$84,$9A,$20,$9A,$0B,$40
; minl10 = -4.932075448958667902381898051166093750570023E3
minl10:	.BYTE	$77,$91,$7C,$0B,$AC,$59,$89,$8F,$98
	.BYTE	$F7,$CF,$FB,$84,$9A,$20,$9A,$0B,$C0

; coefficients for exp2() evaluation
ce2p:
; P[4] = 1.587171580015525194694938306936721666031E2
	.BYTE	$72,$92,$38,$9A,$50,$06,$08,$65,$04
	.BYTE	$98,$BB,$B2,$AA,$97,$B7,$9E,$06,$40
; P[3] = 6.185032670011643762127954396427045467506E5
	.BYTE	$D2,$BC,$B4,$93,$EB,$21,$7F,$08,$D6
	.BYTE	$4F,$03,$A3,$45,$74,$00,$97,$12,$40
; P[2] = 5.677513871931844661829755443994214173883E8
	.BYTE	$42,$4D,$E3,$47,$3D,$36,$86,$67,$11
	.BYTE	$26,$D2,$C5,$6C,$CB,$5C,$87,$1C,$40
; P[1] = 1.530625323728429161131811299626419117557E11
	.BYTE	$7D,$20,$45,$D0,$EE,$9C,$89,$CD,$66
	.BYTE	$25,$5F,$53,$94,$F3,$8C,$8E,$24,$40
; P[0] = 9.079594442980146270952372234833529694788E12
	.BYTE	$FF,$EB,$3C,$5D,$44,$B2,$CC,$35,$20
	.BYTE	$57,$42,$0E,$06,$20,$20,$84,$2A,$40

ce2q:
; Q[4] = 1.236602014442099053716561665053645270207E4
	.BYTE	$5F,$7D,$C4,$10,$CE,$91,$ED,$64,$A4
	.BYTE	$67,$35,$BD,$A0,$14,$38,$C1,$0C,$40
; Q[3] = 2.186249607051644894762167991800811827835E7
	.BYTE	$15,$9B,$5C,$BC,$E3,$D1,$FC,$B0,$07
	.BYTE	$D9,$AE,$06,$09,$30,$CC,$A6,$17,$40
; Q[2] = 1.092141473886177435056423606755843616331E10
	.BYTE	$C8,$3E,$E7,$04,$F9,$42,$1F,$0D,$9B
	.BYTE	$4F,$27,$B7,$14,$E4,$BD,$A2,$20,$40
; Q[1] = 1.490560994263653042761789432690793026977E12
	.BYTE	$64,$87,$EE,$32,$85,$37,$63,$BC,$E7
	.BYTE	$96,$D3,$EB,$E5,$2D,$86,$AD,$27,$40
; Q[0] = 2.619817175234089411411070339065679229869E13
	.BYTE	$68,$99,$1A,$49,$CE,$E7,$82,$4C,$25
	.BYTE	$27,$A7,$BC,$C4,$E5,$9D,$BE,$2B,$40

; maxl2 = 16384
maxl2:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$80,$0D,$40
; minl2 = -16494
minl2:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$DC,$80,$0D,$C0


;---------------------------------------------------------------------------
; circular functions & inverse circular functions
;---------------------------------------------------------------------------

; fcos - returns the circular cosine of the radian argument x
;
;	entry:
;		fac = x (|x| < 2^56)
;
;	exit:
;		fac = cos(x)
;		CF = 1 if invalid result (nan, if x is too large)
;
;	computation mean time: 70ms at 4MHz
;
;----
fcos:
;----
	stz	fpcsgn		; positive sign
	stz	facsgn		; make argument positive
	jsr	modpi4		; reduce argument: z = x - k*(pi/4)
	lda	fpoct		; octant
	cmp	#4
	bcc	?ok		; no change
	tax
	lda	fpcsgn		; invert sign
	eor	#$FF
	sta	fpcsgn
	txa
	sbc	#4		; reflect in x axis
?ok:	cmp	#2
	bcc	?ok2
	tax
	lda	fpcsgn		; invert sign
	eor	#$FF
	sta	fpcsgn
	txa
	cmp	#2
?ok2:	beq	?s0		; octant = 2
	cmp	#1
	bne	?s1
?s0:	jsr	sinz		; 1 & 2nd octant: sinz
	bra	sincos
?s1:	jsr	cosz		; 0 & 3nd octant: cosz 
	bra	sincos

; fsin - returns the circular sine of the radian argument x
;
;	entry:
;		fac = x (|x| < 2^56)
;
;	exit:
;		fac = sin(x)
;		CF = 1 if invalid result (nan, if x is too large)
;
;	computation mean time: 70ms at 4MHz
;
;----
fsin:
;----
	lda	facsgn		; save sign...
	sta	fpcsgn
	stz	facsgn		; ...and make argument positive
	jsr	modpi4		; reduce argument: z = x - k*(pi/4)
	lda	fpoct		; octant
	cmp	#4
	bcc	?ok		; no change
	tax
	lda	fpcsgn		; invert sign
	eor	#$FF
	sta	fpcsgn
	txa
	sbc	#4		; reflect in x axis
?ok:	cmp	#1
	beq	?s0
	cmp	#2
	bne	?s1
?s0:	jsr	cosz		; 1 & 2nd octant: cosz 
	bra	sincos
?s1:	jsr	sinz		; 0 & 3nd octant: sinz

sincos:
	bit	fpcsgn
	bpl	?end
	lda	facsgn		; sign inversion
	eor	#$FF
	sta	facsgn
?end:	clc	
	rts

; sinz - evaluates the sine of the reduced argument
;
;                     3      2
;	sin(z) = z + z  * P(z )
;
;----
sinz:
;----
	lda	#<psin
	ldy	#>psin
	ldx	#11
	jsr	peval		; fac=P(z*z) 
	jsr	mvt0_a		; z*z
	jsr	fpmult
	jsr	mvt1_a		; z
	jsr	fpmult		; (z^3) * P(z*z)
	jsr	mvt1_a		; z
	jmp	fpadd		; z + (z^3) * P(z*z)

; cosz - evaluates cosine of reduced argument
;
;                     1     2     4     2
;	cos(z) = 1 - --- * z   + z * P(z )
;                     2
;
;----
cosz:
;----
	lda	#<pcos
	ldy	#>pcos
	ldx	#10
	jsr	peval		; fac=P(z*z)
	jsr	mvt0_a		; z*z
	jsr	fpmult
	jsr	mvt0_a		; z*z
	jsr	fpmult
	jsr	faddone		; 1 + (z^4) * P(z*z)
	jsr	mvftoa		; move to arg
	jsr	mvt0_f		; z*z
	lda	#$FF
	sta	scexp
	sta	scexp+1
	jsr	fscale		; z*z/2
	jmp	fpsub		; 1 - (z*z/2) + (z^4) * P(z*z)

; modpi4 - argument reduction modulo pi/4
;
;	entry:
;		fac = x
;
;	exit:
;		tfr1 = z, reduced argument in interval [0, pi/4]
;		fac = tfr0 = z*z
;		fpoct = octant modulo 360 degrees (0..7)
;
;	If argument is invalid this function return CF=1 and skip the
;	return address.
;
;	If |x| >= 2^56 the reduction fail due to a large precision loss
;	computing the modulo pi/4 of the argument (returns nan)
;
;	The reduction error is nearly eliminated by contriving an extended 
;	precision modular arithmetic
;
;------
modpi4:
;------
	bit	facst
	bmi	?er		; fac=nan or inf
	ACC16
	lda	facexp
	cmp	#BIAS56		; compare vs. 2^56
	ACC08
	bcc	?ok		; if too large returns nan
?er:	jsr	fldnan
	lda	fpcsgn
	sta	facsgn
	pla			; skip return address
	pla
	sec
	rts
?ok:	jsr	mvf_t1		; tfr1=x
	lda	#<cpio4
	ldy	#>cpio4
	jsr	fcrdiv		; y=x/(pi/4)
	jsr	floor		; integral part
	jsr	uitrunc		; convert to integer in tm
				; just 8 bit value we need here
	lda	tm		; map zeros to origin
	lsr	a
	bcc	?no
	inc	tm
	jsr	faddone		; y=y+1
?no:	lda	tm
	and	#$07		; octant modulo 360 degrees...
	sta	fpoct		; ...for tests on the phase angle
	jsr	mvf_t2		; tfr2=y
	
	; computes z = x - y*(pi/4) with extended precision modular arithmetic
	lda	#<cdp1
	ldy	#>cdp1
	jsr	fcmult		; y*cdp1
	jsr	mvt1_a		; arg=x
	jsr	fpsub		; x=x-y*cdp1
	jsr	mvf_t1		; tfr1=x
	jsr	mvt2_f		; fac=y
	lda	#<cdp2
	ldy	#>cdp2
	jsr	fcmult		; y*cdp2
	jsr	mvt1_a		; arg=x
	jsr	fpsub		; x=x-y*cdp1-y*cdp2
	jsr	mvf_t1		; tfr1=x
	jsr	mvt2_f		; fac=y
	lda	#<cdp3
	ldy	#>cdp3
	jsr	fcmult		; y*cdp3
	jsr	mvt1_a		; arg=x	
	jsr	fpsub		; z=x-y*cdp3-y*cdp2-y*cdp1
	jsr	mvf_t1		; tfr1=z=x-k*(pi/4)
	jsr	fsquare		; z*z
	jmp	mvf_t0		; tfr0=z*z

; ftan - returns the circular tangent of the radian argument x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = tan(x)
;		CF = 1 if invalid result (nan or inf)
;
; strategy
;
; Range reduction is modulo pi/4. A rational function
;	x + x^3 P(x^2)/Q(x^2)
; is employed in the basic interval [0, pi/4].
;
;	computation mean time: 70/80ms at 4MHz
;
;----
ftan:
;----
	lda	#0
	jsr	tancot		; computes tan(x)
	bcs	?end		; returns nan
	bpl	?end		; returns finite value (CF=0)
	sec
?end:	rts

; fcotan - returns the circular cotangent of the radian argument x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = cotan(x)
;		CF = 1 if invalid result (nan or inf)
;
; strategy
;
; Range reduction is modulo pi/4. A rational function
;	x + x^3 P(x^2)/Q(x^2)
; is employed in the basic interval [0, pi/4].
;
;	computation mean time: 70/80ms at 4MHz
;
;------
fcotan:
;------
	bit	facst
	bmi	?nan
	bvs	?inf		; x = 0
	lda	#$FF
	jsr	tancot		; computes cotan(x)
	bcs	?end		; return nan
	bpl	?end		; returns finite value (CF=0)
	sec
?end:	rts
?nan:	jmp	fldnan		; returns nan
?inf:	jmp	fldinf		; returns inf
	
; tancot - common routine used computing tan(x) & cotan(x)
;
;	entry:
;		fac = x
;		A = cotangent flag
;
;	exit:
;		fac = tan(x) or cotan(x)
;		CF = 1 if returns nan
;		NF = 1 if returns inf
;
;------
tancot:
;------
	sta	fpcot		; cotangent flag
	lda	facsgn		; save sign...
	sta	fpcsgn
	stz	facsgn		; ...and make argument positive
	jsr	modpi4		; argument reduction: z = x - k*(pi/4)
				; fac=tfr0=z*z=w
	lda	#<ptan
	ldy	#>ptan
	ldx	#5
	jsr	peval		; evaluate P(w)
	jsr	mvt0_a
	jsr	fpmult		; w*P(w)
	jsr	mvf_t2		; tfr2=w*P(w)
	lda	#<qtan
	ldy	#>qtan
	ldx	#5
	jsr	pevalp1		; evaluate Q(w)
	jsr	mvt2_a		; arg=w*P(w)
	jsr	fpdiv		; w*P(w)/Q(w)
	jsr	mvt1_a		; arg=z
	jsr	fpmult		; z*w*R(w)
	jsr	mvt1_a		; arg=z
	jsr	fpadd		; z + z*w*R(w)
?done:	lda	fpoct		; octant
	and	#$02
	beq	?cot
	lda	facsgn
	eor	#$FF
	sta	facsgn		; sign inversion
	bit	fpcot
	bmi	?end		; cotan(x)
	bra	?rec		; tan(x)
?cot:	bit	fpcot
	bpl	?end		; tan(x)
?rec:	jsr	frecip
?end:	bit	fpcsgn
	bpl	?end2
	lda	facsgn		; sign inversion
	eor	#$FF
	sta	facsgn
?end2:	clc
	bit	facst		; return N=1 if invalid
	rts

; fasin - inverse circular sine: returns radian angle 
; between -pi/2 and +pi/2 whose sine is x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = asin(x) in domain [-p1/2,+pi/2]
;		CF = 1 if returns nan (|x| > 1)
;
; strategy
;
; A rational function of the form x + x^3 P(x^2)/Q(x^2)
; is used for |x| in the interval [0, 0.5]. If |x| > 0.5 it is
; transformed by the identity
;
;	asin(x) = pi/2 - 2*asin(sqrt((1-x)/2))
;
;	computation mean time: 100/130ms at 4MHz
;
;-----
fasin:
;-----
	bit	facst
	bmi	?nan		; if argument is invalid return nan
	bvs	?ok		; if x=0 return 0
	jsr	cmpx1		; compare |x| vs. 1
	bcs	?nan		; if |x|>1 return nan
	php
	lda	facsgn
	sta	fpcsgn		; save sign(x)
	plp
	bne	?do		; |x|<1
	lda	#<cpio2		; |x|=1 so return sgn(x)*pi/2
	ldy	#>cpio2
	jsr	ldfac		; x=pi/2
	lda	fpcsgn
	sta	facsgn
?ok:	clc
	rts
?nan:	jmp	fldnan
?do:	stz	facsgn		; |x|
	stz	fpasin		; asin flag
	jsr	cmpxh		; compare |x| vs. 0.5
	bcs	?gt		; |x|>0.5
	jsr	mvf_t1		; tfr1=z=|x|
	jsr	fsquare		; w=z*z
	bra	?pp
?gt:	lda	#$FF
	sta	fpasin		; |x| > 0.5 flag
	jsr	ldahalf		; arg=0.5
	jsr	fpsub		; w=0.5-|x|
	jsr	faddhalf	; w=1-|x|
	lda	#$FF
	sta	scexp
	sta	scexp+1		; divive dy 2
	jsr	fscale		; w=0.5*(1-|x|)
	jsr	mvf_t2		; tfr2=w
	jsr	fsqrt		; z=sqrt(w)
	jsr	mvf_t1		; tfr1=z
	jsr	mvt2_f		; fac=w
?pp:	jsr	mvf_t0		; tfr0=w
	lda	#<casp
	ldy	#>casp
	ldx	#9
	jsr	peval		; P(w)
	jsr	mvt0_a		; w
	jsr	fpmult		; w*P(w)
	jsr	mvf_t2		; tfr2=w*P(w)
	lda	#<casq
	ldy	#>casq
	ldx	#9
	jsr	pevalp1		; Q(w)
	jsr	mvt2_a		; arg=w*P(w)
	jsr	fpdiv		; w*P(w)/Q(w)=w*R(w)
	jsr	mvt1_a		; arg=z
	jsr	fpmult		; z*w*R(w)
	jsr	mvt1_a		; arg=z
	jsr	fpadd		; y=z+z*w*R(w)
	bit	fpasin
	bpl	?done		; |x| <= 0.5
	jsr	mvftoa
	jsr	fpadd		; y+y
	lda	#<cpio2
	ldy	#>cpio2
	jsr	ldarg		; arg=pi/2
	jsr	fpsub		; pi/2-2*asin(z)
?done:	bit	fpcsgn
	bpl	?end
	lda	facsgn		; sign inversion
	eor	#$FF
	sta	facsgn
?end:	clc
	rts

; facos - inverse circular cosine: returns radian angle 
; between 0 and +pi whose cosine is x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = acos(x) in domain [0,pi]
;		CF = 1 if returns nan (|x| > 1)
;
; strategy
;
; Analytically, acos(x) = pi/2 - asin(x).  However if |x| is
; near 1, there is cancellation error in subtracting asin(x)
; from pi/2.  Hence if x < -0.5,
;
; 	acos(x) = pi - 2.0 * asin(sqrt((1+x)/2))
;
; or if x > +0.5,
;
;	acos(x) = 2.0 * asin(sqrt((1-x)/2))
;
;	computation mean time: 100/140ms at 4MHz
;
;-----
facos:
;-----
	bit	facst
	bmi	?nan		; if argument is invalid return nan
	bvs	?pi2		; if x=0 return pi/2
	jsr	cmpx1		; compare |x| vs. 1
	bcs	?nan		; if |x|>1 return nan
	php
	lda	facsgn
	sta	fpcsgn		; save sign(x)
	plp
	bne	?do		; |x|<1
	stz	facsgn		; |x|=1
	bit	fpcsgn
	bpl	?z		; x=1 so return 0
	lda	#<cpi		; x=-1 so return pi
	ldy	#>cpi
	jsr	ldfac		; x=pi
	clc
	rts
?z:	jmp	fldz
?nan:	jmp	fldnan
?pi2:	lda	#<cpio2		; |x|=0 so return pi/2
	ldy	#>cpio2
	jsr	ldfac		; x=pi/2
	stz	facsgn
?ok:	clc
	rts
?do:	jsr	cmpxh		; compare |x| vs. 0.5
	bcs	?gt		; |x|>0.5
	jsr	fasin		; |x|<=0.5
	lda	#<cpio2
	ldy	#>cpio2
	jsr	ldarg		; arg=pi/2
	jmp	fpsub		; pi/2-asin(x) if |x|<=0.5
?gt:	lda	fpcsgn
	bmi	?neg
	ldx	#$FF	
	stx	facsgn		; x<-0.5 or x>0.5
?neg:	pha			; save sign
	jsr	faddone		; y=1+x or y=1-x
	lda	#$FF
	sta	scexp
	sta	scexp+1
	jsr	fscale		; divide by 2
	jsr	fsqrt		; w=sqrt(y/2)
	jsr	fasin
	lda	#1
	sta	scexp
	stz	scexp+1
	jsr	fscale		; multiplies by 2
	pla			; original sign
	bpl	?ok		; done: acos(x)=2*asin(w)
	lda	#<cpi
	ldy	#>cpi
	jsr	ldarg		; arg=pi
	jmp	fpsub		; acos(x)=pi-2*asin(w)
	

; compare |x| vs. 0.5 - flag's affected
;
;	CF=0, ZF=0 if |x| < 0.5
;	CF=0, ZF=1 if |x| = 0.5
;	CF=1, ZF=0 if |x| > 0.5
cmpxh:
	ACC16
	lda	facexp
	cmp	#EBIAS-1
	bra	cmpx1h
	
; compare |x| vs. 1 - flag's affected
;
;	CF=0, ZF=0 if |x| < 1
;	CF=0, ZF=1 if |x| = 1
;	CF=1, ZF=0 if |x| > 1
cmpx1:
	ACC16
	lda	facexp
	cmp	#EBIAS
cmpx1h:
	bcc	?done		; |x|<1, CF=0, ZF=0
	beq	?tst
	bcs	?done		; |x|>1, CF=1, ZF=0
?tst:	lda	facm+14		; should be $8000
	cmp	#$8000		; here always CF=1
	bne	?done		; |x|>1, CF=1, ZF=0
	lda	facm+12
	ora	facm+10
	ora	facm+8
	ora	facm+6
	ora	facm+4
	ora	facm+2
	ora	facm
	bne	?done		; |x|>1, CF=1, ZF=0		
	clc			; |x|=1, CF=0, ZF=1
?done:	ACC08
	rts

; fatan - inverse circular tangent, returns radian angle
; between -pi/2 and +pi/2 whose tangent is x
;
;	entry:
;		fac = x
;
;	exit:
;		fac = atan(x) in domain [-pi/2,pi/2]
;		CF = 1 if returns nan
;
; strategy
;
; Range reduction is from four intervals into the interval
; from zero to tan(pi/8). The approximant uses a rational
; function of the form x + x^3 P(x)/Q(x).
;
;	computation mean time: 100ms at 4MHz
;
;-----
fatan:
;-----
	bit	facst
	bpl	?fv		; valid fac
	bvc	?er		; fac=nan so return nan
	lda	facsgn
	pha
	lda	#<cpio2
	ldy	#>cpio2
	jsr	ldfac		; x=pi/2
	pla
	sta	facsgn		; return +/-pi/2
?ok:	clc
	rts
?er:	sec
	rts
?fv:	bvs	?ok		; if fac=0 return 0
	lda	facsgn		; save sign...
	sta	fpcsgn
	stz	facsgn		; ...and make argument positive
	lda	#<ct3p8
	ldy	#>ct3p8
	jsr	fccmp		; cmpare x vs. tan(3*pi/8)
	bpl	?gt38		; fac > tan(3*pi/8)
	lda	#<ctp8
	ldy	#>ctp8
	jsr	fccmp		; cmpare x vs. tan(pi/8)
	bpl	?gt8		; fac > tan(pi/8)
	jsr	mvf_t1		; tfr1=w=x
	jsr	fldz
	jsr	mvf_t2		; tfr2=y=0
	bra	?do
?gt8:	jsr	mvf_t0		; tfr0=x
	jsr	mvftoa		; arg=x
	jsr	fldm1		; fac=-1
	jsr	fpadd		; x-1
	jsr	mvf_t1		; tfr1=x-1
	jsr	mvt0_f		; fac=x
	jsr	faddone		; x+1
	jsr	mvt1_a		; arg=x-1
	jsr	fpdiv		; w=(x-1)/(x+1)
	jsr	mvf_t1		; tfr1=w
	lda	#<cpio4
	ldy	#>cpio4
	jsr	ldfac		; pi/4
	jsr	mvf_t2		; tfr2=y=pi/4
	bra	?do
?gt38:	jsr	frecip
	lda	#$FF
	sta	facsgn		; w=-1/x
	jsr	mvf_t1		; tfr1=w=-1/x
	lda	#<cpio2
	ldy	#>cpio2
	jsr	ldfac		; pi/2
	jsr	mvf_t2		; tfr2=y=pi/2
?do:	jsr	mvt1_f		; fac=w
	jsr	fsquare		; z=w*w
	jsr	mvf_t0		; tfr0=z
	lda	#<catp
	ldy	#>catp
	ldx	#8
	jsr	peval		; P(z)
	jsr	mvf_t3		; tfr3=P(z)
	lda	#<catq
	ldy	#>catq
	ldx	#7
	jsr	pevalp1		; Q(z)
	jsr	mvt3_a		; arg=P(z)
	jsr	fpdiv		; R(z)=P(z)/Q(z)
	jsr	mvt0_a		; arg=z
	jsr	fpmult		; z*R(z)
	jsr	mvt1_a		; arg=w
	jsr	fpmult		; z*w*R(z)
	jsr	mvt1_a		; arg=w
	jsr	fpadd		; w+z*w*R(z)
	jsr	mvt2_a		; arg=y
	jsr	fpadd		; y+w+z*w*R(z)
	bit	fpcsgn
	bpl	?end
	lda	facsgn
	eor	#$FF
	sta	facsgn
?end:	clc
	rts

; fatanyx - inverse circular tangent, returns radian angle
; between 0 and 2*pi whose tangent is y/x (computes the phase angle)
;
;	entry:
;		fac = x
;		arg = y
;
;	exit:
;		fac = z = atan(y/x) in domain [0, 2pi]
;		CF = 1 if returns nan
;
;	computation mean time: 100ms at 4MHz
;
;-------
fatanyx:
;-------
	ldx	#0
	bit	facsgn
	bpl	?xp		; x >= 0
	ldx	#2
?xp:	bit	argsgn
	bpl	?yp		; y >= 0
	inx
?yp:	stx	atncode
	lda	facst
	and	#$C0
	cmp	#$80
	beq	?nan		; if x=nan return nan
	tax
	lda	argst
	and	#$C0
	cmp	#$80
	beq	?nan		; if y=nan return nan
	tay
	and	facst
	cmp	#$C0		; if x=inf and y=inf return nan
	bne	?x0
?nan:	jmp	fldnan	
?x0:	cpx	#$40
	bne	?xx		; x != 0
	cpy	#$40		; y = 0?
	beq	?zz		; yes, return zero (x = 0, y = 0) 
?pi2:	lda	#<cpio2
	ldy	#>cpio2
	jsr	ldfac		; z = pi/2 
	lsr	atncode
	bcc	?ret		; return z = pi/2
	jsr	ldaone
	ACC16
	inc	argexp
	lda	#$C000
	sta	argm+14		; arg = 3
	ACC08
	stz	argsgn
	jmp	fpmult		; return z = 3*pi/2
?zz:	jmp	fldz		; z = 0
?xx:	cpy	#$40
	bne	?yy		; y != 0
?pi:	lda	atncode
	beq	?zz		; return z = 0
	lda	#<cpi
	ldy	#>cpi
	jsr	ldfac		; z = pi 
	lda	#$02
	bit	atncode
	bne	?ret		; return z = pi
	ACC16
	inc	facexp		; return z = 2*pi
	ACC08
?ret:	clc
	rts
?yy:	cpy	#$C0
	beq	?pi2		; if y = inf, x != 0, is like x = 0
	cpx	#$C0
	beq	?pi		; if x = inf, y != 0, is like y = 0
	jsr	fpdiv		; w = y/x (both x and y finite and not null)
	jsr	fatan		; z = atan(y/x)
	lda	atncode
	beq	?ret		; return z = atan(y/x) (first quadrant)
	jsr	mvftoa		; arg = z
	lda	#<cpi
	ldy	#>cpi
	jsr	ldfac		; fac = pi 
	lda	atncode
	cmp	#$02
	beq	?done		; 2nd quadrant: add pi (atan < 0)
	cmp	#$03
	beq	?done		; 3th quadrant: add pi (atan > 0)
	ACC16
	inc	facexp		; 4th quadrant: add 2*pi (atan < 0)
	ACC08
?done:	jmp	fpadd	
	

; sin(x) coefficients
psin:
; PSIN[11] =  6.410290407010279602425714995528976754871E-26 
	.BYTE	$35,$40,$EA,$6E,$20,$61,$06,$26,$A1
	.BYTE	$83,$C3,$68,$DB,$0A,$B6,$9E,$AB,$3F

; PSIN[10] = -3.868105354403065333804959405965295962871E-23  
	.BYTE	$D1,$C3,$E7,$80,$C9,$32,$07,$3B,$A4
	.BYTE	$87,$F3,$85,$2F,$D3,$0C,$BB,$B4,$BF

; PSIN[09] =  1.957294039628045847156851410307133941611E-20 
	.BYTE	$44,$DE,$C1,$98,$E0,$53,$C7,$8F,$BC
	.BYTE	$E5,$70,$32,$4D,$77,$DC,$B8,$BD,$3F

; PSIN[08] = -8.220635246181818130416407184286068307901E-18  
	.BYTE	$88,$ED,$DD,$EC,$5C,$DF,$55,$07,$A1
	.BYTE	$85,$FB,$E6,$33,$DA,$A4,$97,$C6,$BF

; PSIN[07] =  2.811457254345322887443598804951004537784E-15  
	.BYTE	$22,$B2,$7C,$77,$2A,$20,$77,$86,$F3
	.BYTE	$A5,$5A,$85,$81,$3B,$96,$CA,$CE,$3F

; PSIN[06] = -7.647163731819815869711749952353081768709E-13 
	.BYTE	$72,$92,$40,$E9,$65,$9C,$A5,$43,$C1
	.BYTE	$F3,$C0,$9D,$39,$9F,$3F,$D7,$D6,$BF

; PSIN[05] =  1.605904383682161459812515654720205050216E-10  
	.BYTE	$80,$06,$BE,$F2,$47,$B3,$13,$1B,$E4
	.BYTE	$4B,$68,$43,$9D,$30,$92,$B0,$DE,$3F

; PSIN[04] = -2.505210838544171877505034150892770940116E-8  
	.BYTE	$EC,$90,$66,$4A,$76,$79,$F7,$39,$7F
	.BYTE	$1C,$27,$AA,$3F,$2B,$32,$D7,$E5,$BF

; PSIN[03] =  2.755731922398589065255731765498970284004E-6  
	.BYTE	$84,$F7,$94,$D2,$B7,$37,$0E,$56,$7D
	.BYTE	$9C,$39,$B6,$2A,$1D,$EF,$B8,$EC,$3F

; PSIN[02] = -1.984126984126984126984126984045294307281E-4  
	.BYTE	$7D,$F8,$65,$29,$FE,$0C,$D0,$00,$0D
	.BYTE	$D0,$00,$0D,$D0,$00,$0D,$D0,$F2,$BF

; PSIN[01] =  8.333333333333333333333333333333119885283E-3 
	.BYTE	$62,$9A,$41,$88,$88,$88,$88,$88,$88
	.BYTE	$88,$88,$88,$88,$88,$88,$88,$F8,$3F

; PSIN[00] = -1.666666666666666666666666666666666647199E-1 
	.BYTE	$51,$A0,$AA,$AA,$AA,$AA,$AA,$AA,$AA
	.BYTE	$AA,$AA,$AA,$AA,$AA,$AA,$AA,$FC,$BF

; cos(x) coefficients 
pcos:
; PCOS[10] =  1.601961934248327059668321782499768648351E-24  
	.BYTE	$6F,$42,$59,$D2,$8A,$EF,$37,$CD,$48
	.BYTE	$C3,$50,$58,$0F,$40,$E4,$F7,$AF,$3F

; PCOS[09] = -8.896621117922334603659240022184527001401E-22  
	.BYTE	$EF,$E7,$87,$4A,$0E,$94,$D9,$B3,$11
	.BYTE	$C8,$08,$07,$CC,$22,$71,$86,$B9,$BF

; PCOS[08] =  4.110317451243694098169570731967589555498E-19 
	.BYTE	$94,$20,$CD,$9C,$D6,$21,$68,$81,$A8
	.BYTE	$E7,$86,$A7,$75,$5C,$A1,$F2,$C1,$3F

; PCOS[07] = -1.561920696747074515985647487260202922160E-16  
	.BYTE	$4C,$88,$FF,$5A,$9D,$63,$B8,$94,$13
	.BYTE	$54,$B0,$94,$1D,$C3,$13,$B4,$CA,$BF

; PCOS[06] =  4.779477332386900932514186378501779328195E-14  
	.BYTE	$2B,$3C,$A9,$FD,$E8,$BA,$6D,$B7,$80
	.BYTE	$FC,$A8,$9D,$39,$9F,$3F,$D7,$D2,$3F

; PCOS[05] = -1.147074559772972328629102981460088437917E-11  
	.BYTE	$C1,$7C,$8A,$0F,$0E,$46,$0C,$31,$F4
	.BYTE	$E1,$E4,$03,$46,$A5,$CB,$C9,$DA,$BF

; PCOS[04] =  2.087675698786809897637922200570559726116E-9  
	.BYTE	$93,$84,$CC,$C1,$FA,$D5,$F9,$BF,$A8
	.BYTE	$BD,$C4,$C6,$7F,$C7,$76,$8F,$E2,$3F

; PCOS[03] = -2.755731922398589065255365968070684102298E-7 
	.BYTE	$0E,$2B,$2E,$FA,$29,$A2,$AE,$77,$97
	.BYTE	$E3,$FA,$C4,$BB,$7D,$F2,$93,$E9,$BF

; PCOS[02] =  2.480158730158730158730158440896461945271E-5 
	.BYTE	$69,$8F,$86,$22,$AB,$EF,$CF,$00,$0D
	.BYTE	$D0,$00,$0D,$D0,$00,$0D,$D0,$EF,$3F

; PCOS[01] = -1.388888888888888888888888888765724370132E-3 
	.BYTE	$C8,$EC,$07,$B7,$5B,$0B,$B6,$60,$0B
	.BYTE	$B6,$60,$0B,$B6,$60,$0B,$B6,$F5,$BF

; PCOS[00] =  4.166666666666666666666666666666459301466E-2  
	.BYTE	$F7,$64,$FE,$A9,$AA,$AA,$AA,$AA,$AA
	.BYTE	$AA,$AA,$AA,$AA,$AA,$AA,$AA,$FA,$3F

; DP1 + DP2 + DP3 = PI/4
; DP1 =  7.853981633974483067550664827649598009884357452392578125E-1 
cdp1:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$C2,$68,$21,$A2,$DA,$0F,$C9,$FE,$3F

; DP2 =  2.8605943630549158983813312792950660807511260829685741796657E-18 
cdp2:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$70,$03,$2E,$8A,$19,$13,$D3,$C4,$3F

; DP3 =  2.1679525325309452561992610065108379921905808E-35 
cdp3:	.BYTE	$00,$00,$32,$F5,$5D,$10,$A0,$63,$3E
	.BYTE	$53,$44,$70,$12,$48,$89,$E6,$8B,$3F

; PI/4 = 0.7853981633974483096156608458198757210492923
cpio4:	.BYTE	$D1,$1C,$DC,$80,$8B,$62,$C6,$C4,$34
	.BYTE	$C2,$68,$21,$A2,$DA,$0F,$C9,$FE,$3F

; PI/2
cpio2:	.BYTE	$D1,$1C,$DC,$80,$8B,$62,$C6,$C4,$34
	.BYTE	$C2,$68,$21,$A2,$DA,$0F,$C9,$FF,$3F

; PI
cpi:	.BYTE	$D1,$1C,$DC,$80,$8B,$62,$C6,$C4,$34
	.BYTE	$C2,$68,$21,$A2,$DA,$0F,$C9,$00,$40

; tan(3*pi/8) = sqrt(2)+1 
ct3p8:	.BYTE	$4F,$5F,$A5,$BA,$D9,$C4,$BE,$2C,$42
	.BYTE	$32,$EF,$FC,$99,$79,$82,$9A,$00,$40
  
; tan(pi/8) = sqrt(2)-1 
ctp8:	.BYTE	$7C,$FA,$2A,$D5,$CD,$26,$F6,$65,$11
	.BYTE	$92,$79,$E7,$CF,$CC,$13,$D4,$FD,$3F


; tan(x) coefficients 
ptan:
; TP[5] = -9.889929415807650724957118893791829849557E-1 
	.BYTE	$58,$BB,$A5,$17,$15,$D7,$E3,$C6,$CB
	.BYTE	$04,$71,$10,$34,$A4,$2E,$FD,$FE,$BF

; TP[4] =  1.272297782199996882828849455156962260810E3 
	.BYTE	$D1,$56,$CC,$23,$3E,$E5,$D8,$0B,$50
	.BYTE	$29,$4A,$89,$6E,$87,$09,$9F,$09,$40

; TP[3] = -4.249691853501233575668486667664718192660E5 
	.BYTE	$94,$A5,$29,$9E,$C5,$9C,$0D,$8B,$2B
	.BYTE	$C4,$61,$63,$EE,$25,$81,$CF,$11,$C0

; TP[2] =  5.160188250214037865511600561074819366815E7 
	.BYTE	$B4,$52,$C1,$B5,$30,$D3,$30,$C9,$14
	.BYTE	$66,$11,$23,$A0,$76,$D8,$C4,$18,$40

; TP[1] = -2.307030822693734879744223131873392503321E9 
	.BYTE	$55,$27,$82,$DF,$66,$F2,$8E,$98,$EC
	.BYTE	$9B,$98,$B1,$26,$7F,$82,$89,$1E,$C0

; TP[0] =  2.883414728874239697964612246732416606301E10 
	.BYTE	$16,$C6,$4C,$C5,$B1,$35,$56,$87,$4F
	.BYTE	$B7,$C1,$17,$7B,$C5,$D4,$D6,$21,$40

qtan:
; TQ[5] = -1.317243702830553658702531997959756728291E3 
	.BYTE	$FA,$D3,$81,$DD,$E9,$7B,$94,$EB,$80
	.BYTE	$75,$E5,$E0,$69,$CC,$A7,$A4,$09,$C0

; TQ[4] =  4.529422062441341616231663543669583527923E5 
	.BYTE	$E6,$99,$66,$53,$23,$56,$5A,$89,$E9
	.BYTE	$66,$4C,$8D,$99,$C6,$29,$DD,$11,$40

; TQ[3] = -5.733709132766856723608447733926138506824E7 
	.BYTE	$69,$45,$D0,$B9,$5E,$77,$B9,$31,$0D
	.BYTE	$95,$85,$F8,$D4,$40,$B9,$DA,$18,$C0

; TQ[2] =  2.758476078803232151774723646710890525496E9 
	.BYTE	$25,$48,$F2,$7D,$A4,$71,$D8,$F7,$4E
	.BYTE	$9F,$A0,$CD,$2E,$01,$6B,$A4,$1E,$40

; TQ[1] = -4.152206921457208101480801635640958361612E10 
	.BYTE	$45,$68,$68,$C0,$AA,$ED,$34,$14,$6C
	.BYTE	$3E,$27,$E9,$ED,$87,$AE,$9A,$22,$C0

; TQ[0] =  8.650244186622719093893836740197250197602E10 
	.BYTE	$30,$B9,$F9,$53,$45,$A8,$80,$A5,$7B
	.BYTE	$49,$D1,$51,$1C,$94,$1F,$A1,$23,$40

; asin(x) coefficients
casp:
; ASP[9] = -8.067112765482705313585175280952515549833E-1  
	.BYTE	$73,$27,$C0,$8D,$2C,$37,$96,$A8,$04
	.BYTE	$05,$D8,$16,$56,$A1,$84,$CE,$FE,$BF

; ASP[8] =  4.845649797786849136525020822000172350977E1 
	.BYTE	$10,$4E,$72,$84,$A0,$F4,$1C,$1D,$A9
	.BYTE	$8C,$8A,$B6,$34,$74,$D3,$C1,$04,$40

; ASP[7] = -8.510195404865297879959793548843395926847E2 
	.BYTE	$EB,$4D,$4D,$8F,$C3,$B1,$24,$A9,$BD
	.BYTE	$F9,$A5,$BD,$26,$40,$C1,$D4,$08,$C0

; ASP[6] =  6.815196841370292688574521445731895826485E3 
	.BYTE	$AA,$5E,$2D,$43,$AA,$66,$ED,$0A,$61
	.BYTE	$41,$7F,$91,$21,$93,$F9,$D4,$0B,$40

; ASP[5] = -2.967135182120339728996157454994675519735E4 
	.BYTE	$F2,$CA,$89,$AC,$E2,$B3,$AC,$51,$EE
	.BYTE	$42,$A5,$E8,$21,$B4,$CE,$E7,$0D,$C0

; ASP[4] =  7.612250656518818109652985996692466409670E4 
	.BYTE	$4D,$89,$09,$49,$F6,$5B,$21,$9C,$D3
	.BYTE	$43,$CA,$20,$D7,$40,$AD,$94,$0F,$40

; ASP[3] = -1.183360579752620455689557157684221905030E5 
	.BYTE	$C8,$84,$21,$34,$4B,$51,$AB,$59,$3B
	.BYTE	$3B,$BF,$BB,$6B,$07,$20,$E7,$0F,$C0

; ASP[2] =  1.095432262510413338755837156377401348063E5 
	.BYTE	$5C,$D5,$0E,$A4,$53,$03,$23,$26,$83
	.BYTE	$9B,$4B,$CB,$F5,$9C,$F3,$D5,$0F,$40

; ASP[1] = -5.554124580991113991999636773382495788705E4 
	.BYTE	$A8,$77,$07,$20,$6B,$5E,$DE,$66,$ED
	.BYTE	$60,$F9,$65,$ED,$3E,$F5,$D8,$0E,$C0

; ASP[0] =  1.187132626694762543537732514905488896985E4 
	.BYTE	$14,$17,$24,$62,$E1,$9B,$9A,$F9,$98
	.BYTE	$44,$37,$EC,$18,$4E,$7D,$B9,$0C,$40

casq: 
; ASQ[9] = -8.005471061732009595694099899234272342478E1 
	.BYTE	$AB,$CB,$99,$42,$E0,$53,$D9,$98,$3E
	.BYTE	$7F,$44,$B0,$07,$03,$1C,$A0,$05,$C0

; ASQ[8] =  1.817324228942812880965069608562483918025E3 
	.BYTE	$74,$B0,$9D,$55,$FC,$EE,$98,$24,$09
	.BYTE	$89,$39,$60,$15,$60,$2A,$E3,$09,$40

; ASQ[7] = -1.867017317425756524289537002141956583706E4 
	.BYTE	$CA,$11,$F0,$E5,$FC,$8D,$72,$C6,$EB
	.BYTE	$80,$D9,$4B,$AA,$58,$DC,$91,$0D,$C0

; ASQ[6] =  1.048196619402464497478959760337779705622E5 
	.BYTE	$EA,$F9,$4B,$5E,$82,$00,$4C,$57,$34
	.BYTE	$34,$3F,$75,$BA,$D4,$B9,$CC,$0F,$40

; ASQ[5] = -3.527040897897253459022458866536165564103E5 
	.BYTE	$9E,$F0,$E3,$86,$B9,$BB,$11,$41,$14
	.BYTE	$BC,$B3,$8E,$DF,$02,$38,$AC,$11,$C0

; ASQ[4] =  7.426302422018858001691440351763370029242E5 
	.BYTE	$72,$C6,$78,$BF,$89,$F9,$2E,$F9,$A8
	.BYTE	$A8,$15,$0F,$E0,$63,$4E,$B5,$12,$40

; ASQ[3] = -9.863068411558756277454631976667880674474E5 
	.BYTE	$FF,$38,$2A,$9B,$42,$07,$BF,$F1,$8C
	.BYTE	$0A,$DD,$5F,$75,$2D,$CC,$F0,$12,$C0

; ASQ[2] =  8.025654653926121907774766642393757364326E5 
	.BYTE	$C1,$3C,$5A,$DF,$8E,$AF,$32,$E7,$8C
	.BYTE	$12,$86,$3F,$72,$57,$F0,$C3,$12,$40

; ASQ[1] = -3.653000557802254281954969843055623398839E5 
	.BYTE	$CA,$1B,$43,$FC,$90,$05,$03,$8F,$48
	.BYTE	$7F,$9C,$F3,$C8,$81,$5E,$B2,$11,$C0

; ASQ[0] =  7.122795760168575261226395089432959614179E4 
	.BYTE	$93,$75,$A5,$09,$E9,$F4,$33,$BB,$72
	.BYTE	$73,$29,$B1,$92,$FA,$1D,$8B,$0F,$40

; atan(x) coefficients
catp:
; ATP[08] = -6.635810778635296712545011270011752799963E-4 
	.BYTE	$F1,$6B,$5F,$23,$D7,$8E,$2D,$08,$F8
	.BYTE	$79,$13,$55,$1C,$2C,$F4,$AD,$F4,$BF

; ATP[07] = -8.768423468036849091777415076702113400070E-1 
	.BYTE	$0C,$62,$A5,$C3,$8A,$2F,$F9,$15,$4D
	.BYTE	$29,$0C,$45,$73,$BD,$78,$E0,$FE,$BF

; ATP[06] = -2.548067867495502632615671450650071218995E1 
	.BYTE	$EA,$FC,$2D,$13,$27,$8A,$73,$51,$2A
	.BYTE	$18,$88,$A6,$0F,$6E,$D8,$CB,$03,$C0

; ATP[05] = -2.497759878476618348858065206895055957104E2 
	.BYTE	$F8,$A0,$32,$CF,$E6,$62,$5C,$EB,$0C
	.BYTE	$0F,$CD,$BB,$23,$A7,$C6,$F9,$06,$C0

; ATP[04] = -1.148164399808514330375280133523543970854E3 
	.BYTE	$F0,$5F,$EE,$9D,$20,$0D,$F2,$58,$EE
	.BYTE	$34,$21,$63,$C3,$42,$85,$8F,$09,$C0

; ATP[03] = -2.792272753241044941703278827346430350236E3 
	.BYTE	$9A,$CD,$A1,$B3,$A8,$AB,$A8,$87,$0E
	.BYTE	$A8,$A2,$80,$32,$5D,$84,$AE,$0A,$C0

; ATP[02] = -3.696264445691821235400930243493001671932E3 
	.BYTE	$76,$73,$C3,$5C,$DA,$FA,$F9,$C5,$78
	.BYTE	$0B,$DF,$67,$2B,$3B,$04,$E7,$0A,$C0

; ATP[01] = -2.514829758941713674909996882101723647996E3 
	.BYTE	$FF,$23,$4B,$CB,$5F,$46,$30,$6F,$B3
	.BYTE	$94,$E3,$4F,$B1,$46,$2D,$9D,$0A,$C0

; ATP[00] = -6.880597774405940432145577545328795037141E2 
	.BYTE	$02,$27,$91,$66,$97,$AB,$B4,$ED,$BB
	.BYTE	$F5,$18,$C2,$64,$D3,$03,$AC,$08,$C0

catq:
; ATQ[07] =  3.566239794444800849656497338030115886153E1  
	.BYTE	$C0,$AA,$A1,$BA,$09,$B0,$53,$CA,$64
	.BYTE	$06,$5E,$91,$A5,$4B,$A6,$8E,$04,$40

; ATQ[06] =  4.308348370818927353321556740027020068897E2  
	.BYTE	$F3,$26,$2F,$03,$B5,$85,$60,$C3,$D8
	.BYTE	$D2,$1B,$06,$F1,$DB,$6A,$D7,$07,$40

; ATQ[05] =  2.494680540950601626662048893678584497900E3  
	.BYTE	$37,$5A,$94,$B0,$14,$01,$F9,$F5,$88
	.BYTE	$C3,$66,$E8,$7E,$E3,$EA,$9B,$0A,$40

; ATQ[04] =  7.928572347062145288093560392463784743935E3 
	.BYTE	$E8,$83,$10,$77,$27,$F7,$9C,$C9,$6A
	.BYTE	$01,$4F,$B2,$2A,$94,$C4,$F7,$0B,$40

; ATQ[03] =  1.458510242529987155225086911411015961174E4  
	.BYTE	$F4,$89,$D9,$F7,$87,$4A,$D8,$81,$DC
	.BYTE	$EC,$84,$2D,$E2,$68,$E4,$E3,$0C,$40

; ATQ[02] =  1.547394317752562611786521896296215170819E4  
	.BYTE	$D6,$33,$A9,$9B,$41,$D7,$06,$B7,$A6
	.BYTE	$8B,$4B,$54,$D0,$C5,$C7,$F1,$0C,$40

; ATQ[01] =  8.782996876218210302516194604424986107121E3 
	.BYTE	$F6,$15,$46,$E3,$7B,$EE,$EE,$EA,$5E
	.BYTE	$7E,$8D,$1E,$CD,$FC,$3B,$89,$0C,$40

; ATQ[00] =  2.064179332321782129643673263598686441900E3 
	.BYTE	$AD,$9F,$29,$8D,$B1,$80,$47,$F2,$4C
	.BYTE	$B8,$92,$91,$8B,$DE,$02,$81,$0A,$40

;---------------------------------------------------------------------------
; hyperbolics functions & inverse hyperbolics functions
;---------------------------------------------------------------------------

; fsinh - returns the hyperbolic sin of the argument
;
;	entry:
;		fac = x (argument)
;
;	exit:
;		fac = sinh(x)
;		CF = 1 if invalid result(inf or nan)
;
; strategy		       x      -x
;			      e   -  e
; Mathematically sinh(x)  =  -----------
;				  2
;
;	1) if |x| <=1 sinh(x) is approximated by a rational function:
;
;			       3	        P(z)	    2
;		sinh(x) = x + x * R(z), R(z) = ------, z = x
;					        Q(z)
;
;					        E          |x|
;	2) |x| > 1: sinh(x) = sgn(x)*0.5*(E + -----), E = e   - 1 = expm1(|x|)
;					       E+1
;
;	computation mean time: 65/100ms at 4MHz
;
;	Note: overflow if |x| >= 11356.25
;
;-----
fsinh:
;-----
	sec
	bit	facst
	bmi	?rts		; fac=inf or inf
	bvc	?nz		; if fac=0 returns zero
	clc
?rts:	rts
?nz:	jsr	cmpx1		; compare |x| vs. 1.0
	beq	rsinh		; |x|=1
	bcc	rsinh		; |x|<1
	lda	facsgn		; sinh(-x)=-sinh(x)
	sta	fpcsgn		; save sign
	stz	facsgn		; |x|
	jsr	fexpm1		; E=exp(|x|)-1
	bcs	?done		; overflow
	jsr	mvf_t0
	jsr	faddone		; E+1
	bcs	?done		; overflow
	jsr	mvt0_a		; arg=E
	jsr	fpdiv		; E/(E+1)
	jsr	mvt0_a		; arg=E
	jsr	fpadd		; E+E/(E+1)
	bcs	?done		; overflow
	ACC16			; for sure here fac is normal
	dec	facexp		; divide by 2
	ACC08
?done:	lda	fpcsgn
	sta	facsgn		; set sign
	rts

; returns sinh(x) when |x|<=1 (approximated by rational function)	
rsinh:	
	jsr	mvf_t1		; tfr1=x
	jsr	fsquare		; z=x*x
	jsr	mvf_t0		; tfr0=z
	lda	#<cshp
	ldy	#>cshp
	ldx	#5
	jsr	peval		; evaluates P(z)
	jsr	mvf_t2		; tfr2=P(z)
	lda	#<cshq
	ldy	#>cshq
	ldx	#5
	jsr	pevalp1		; evaluates Q(z)
	jsr	mvt2_a		; arg=P(z)
	jsr	fpdiv
	jsr	mvt0_a		; arg=z
	jsr	fpmult		; z*R(z)
	jsr	mvt1_a		; arg=x
	jsr	fpmult		; x*z*R(z)
	jsr	mvt1_a		; arg=x
	jmp	fpadd		; returns sinh(x)=x + x*z*R(z)

; fcosh - returns the hyperbolic cosin of the argument
;
;	entry:
;		fac = x (argument)
;
;	exit:
;		fac = cosh(x)
;		CF = 1 if invalid result(inf or nan)
;
; strategy		       x      -x
;			      e   +  e
; Mathematically cosh(x)  =  -----------
;				  2
;
;	1) if |x| <=1 cosh(x) is approximated by a rational function
;	   that evaluates sinh(|x|):
;
;			       3	        P(z)	    2
;		sinh(x) = x + x * R(z), R(z) = ------, z = x
;					        Q(z)
;					   2
;	   then: cosh(x) = sqrt(1 + sinh(x) )
;
;				       0.5	  |x|
;	2) |x| > 1: cosh(x) = 0.5*E + -----, E = e    = expm1(|x|) + 1
;					E
;
;	computation mean time: 100ms at 4MHz
;
;	Note: overflow if |x| >= 11356.25
;
;-----
fcosh:
;-----
	stz	facsgn		; cosh(-x) = cosh(x)
	sec
	bit	facst
	bmi	?rts		; fac=inf or nan
	bvc	?nz		; if fac=0 returns 1
	jmp	fldp1
?rts:	rts
?nz:	jsr	cmpx1		; compare |x| vs. 1.0
	beq	?le1		; |x|=1
	bcs	?gt1		; |x|>1
?le1:	jsr	rsinh		; sinh(|x|)
	jsr	fsquare		; sinh(|x|)^2
	jsr	faddone		; 1+sinh(|x|)^2
	jmp	fsqrt		; cosh(x) = sqrt(1+sinh(|x|)^2)
?gt1:	jsr	fexpm1		; E=expm1(|x|)
	bcs	?rts		; overflow
	jsr	faddone
	bcs	?rts		; overflow
	jsr	mvf_t0
	jsr	ldahalf
	jsr	fpdiv		; 0.5/E
	jsr	mvt0_a		; arg=E
	ACC16
	dec	argexp		; E/2
	ACC08	
	jmp	fpadd

; ftanh - returns the hyperbolic tangent of the argument
;
;	entry:
;		fac = x (argument)
;
;	exit:
;		fac = tanh(x)
;		CF = 1 if invalid result(inf or nan)
;
; strategy		       x      -x
;			      e   -  e
; Mathematically cosh(x)  =  -----------
; 			       x      -x
;			      e   +  e
;
; strategy
;
;	1) if |x| < 0.625 tanh(x) is approximated by a rational function:
;
;			       3	        P(z)	    2
;		tanh(x) = x + x * R(z), R(z) = ------, z = x
;					        Q(z)
;
;				         2	      2|x|
;	2) |x| > 0.625: tanh(x) = 1 - -------,   E = e 
;				       E + 1
;
;	computation mean time: 60/100ms at 4MHz
;
;	Note: if |x| >= 40 tanh(x) = +/-1
;
;-----
ftanh:
;-----
	bit	facst
	bpl	?fv		; valid
	bvc	?er		; fac=nan so returns nan
	jmp	fld1		; if fac =+/-inf returns +/-1
?er:	sec
	rts
?fv:	bvs	?ok		; if fac=0 returns zero	
	ACC16			; compare |x| vs. 0.625
	lda	facexp
	cmp	#$3FFE
	beq	?tst
	bcs	?cc		; |x| > 0.625
?tst:	lda	facm+14
	cmp	#$A000
?cc:	ACC08
	bcc	?pp		; |x| < 0.625
	lda	facsgn
	sta	fpcsgn		; save sign
	stz	facsgn		; |x|
	ACC16
	lda	facexp
	cmp	#MAXEXP
	bcs	?cc2
	inc	a
	sta	facexp
?cc2:	ACC08
	bcs	?th1		; overflow: return +1	
	jsr	fexp		; exp(|2x|)
	bcs	?th1		; overflow
	jsr	faddone
	jsr	ldatwo		; arg=2.0
	jsr	fpdiv		; 2/(exp(|2x|)+1)
	jsr	ldaone
	jsr	fpsub		; 1 - 2/(exp(|2x|)+1)	
	bra	?done
?th1:	jsr	fld1		; set fac=1
?done:	lda	fpcsgn
	sta	facsgn		; set sign
?ok:	clc
	rts
?pp:	jsr	mvf_t1		; tfr1=x
	jsr	fsquare		; z=x*x
	jsr	mvf_t0		; tfr0=z
	lda	#<cthp
	ldy	#>cthp
	ldx	#5
	jsr	peval		; evaluates P(z)
	jsr	mvf_t2		; tfr2=P(z)
	lda	#<cthq
	ldy	#>cthq
	ldx	#4
	jsr	pevalp1		; evaluates Q(z)
	jsr	mvt2_a		; arg=P(z)
	jsr	fpdiv		; R(z)
	jsr	mvt0_a		; arg=z
	jsr	fpmult		; z*R(z)
	jsr	mvt1_a		; arg=x
	jsr	fpmult		; x*z*R(z)
	jsr	mvt1_a		; arg=x
	jmp	fpadd		; returns tanh(x)=x + x*z*R(z)

; fasinh - returns the inverse hyperbolic sine of the argument
;
;	entry:
;		fac=x
;
;	exit:
;		fac=asinh(x)
;		CF = 1 if invalid result(inf or nan)
;
; strategy
;
; Mathematically asinh(x) = sgn(x)*ln[|x| + sqrt(x*x + 1)]
;
;	1) if |x| < 0.5 asinh(x) is approximated by a rational function:
;
;			        3	        P(z)	     2
;		asinh(x) = x + x * R(z), R(z) = ------, z = x
;					        Q(z)
;
; 	2) if |x| >= 0.5: asinh(x) = sgn(x)*ln[|x| + sqrt(x*x + 1)]
;	   overflow will be avoided computing x*x or |x| + sqrt(...)
; 	   approximating asinh(x) with:
;
;		asinh(x) = sgn(x)*ln(2*|x|) if x*x overflow
;
;	   or:
;
;		asinh(x) = sgn(x)*[ln(|x|) + ln(2)]  if 2*|x| overflow
;
;	computation mean time: 100/150ms at 4MHz
;
;------
fasinh:
;------
	sec
	bit	facst		; if fac=nan or fac=inf returns nan or inf
	bmi	?rts
	bvc	?fv
	clc			; if fac=0 returns zero
?rts:	rts
?fv:	lda	facsgn		; asinh(-x) = -asinh(x)
	sta	fpcsgn		; save sign
	stz	facsgn		; |x|
	ACC16
	lda	facexp
	cmp	#$3FFE		; 0.5
	ACC08
	php
	jsr	mvf_t2		; tfr2=|x|
	jsr	fsquare		; z=x*x
	plp
	bcc	?lt05		; |x| < 0.5
	jsr	faddone		; z+1
	bcs	?big		; x*x overflow
	jsr	fsqrt		; sqrt(z+1)
	jsr	mvt2_a		; arg=x
	jsr	fpadd		; x+sqrt(z+1)	
	bcs	?big		; overflow
	jsr	floge		; ln(x+sqrt(z+1))
	bra	?done
?big:	jsr	mvt2_f
	jsr	mvftoa
	jsr	fpadd		; try 2*|x|
	bcs	?big1		; overflow
	jsr	floge		; asinh(x) = sgn(x)*(ln(2*|x|))
	bra	?done
?big1:	jsr	mvt2_f
	jsr	floge
	lda	#<cln2		; asinh(x) = sgn(x)*(ln(|x|) + ln(2))
	ldy	#>cln2
	jsr	fcadd
	bra	?done
?lt05:	jsr	mvf_t0		; tfr0=z
	lda	#<cashp
	ldy	#>cashp
	ldx	#8
	jsr	peval		; evaluates P(z)
	jsr	mvf_t1		; tfr2=P(z)
	lda	#<cashq
	ldy	#>cashq
	ldx	#8
	jsr	pevalp1		; evaluates Q(z)
	jsr	mvt1_a		; arg=P(z)
	jsr	fpdiv		; R(z)
	jsr	mvt0_a		; arg=z
	jsr	fpmult		; z*R(z)
	jsr	mvt2_a		; arg=x
	jsr	fpmult		; x*z*R(z)
	jsr	mvt2_a		; arg=x
	jsr	fpadd		; asinh(x)=x + x*z*R(z)
?done:	lda	fpcsgn		; set sign
	sta	facsgn
	rts

; facosh - returns the inverse hyperbolic cosine of the argument
;
;	entry:
;		fac=x
;
;	exit:
;		fac=acosh(x)
;		CF = 1 if invalid result(inf or nan)
;
; strategy
;
; Mathematically acosh(x) = ln[x + sqrt(x*x - 1)], x >= 1
;
;	1) if 1 <= x < 1.5 acosh(x) is approximated by a rational function:
;
;			                	     P(z)	
;		acosh(x) = sqrt(2*z) * R(z), R(z) = ------, z = x - 1
;					             Q(z)
;
; 	2) if |x| >= 1.5: acosh(x) = ln[x + sqrt(x*x - 1)]
;	   overflow will be avoided computing x*x or x + sqrt(...)
; 	   approximating acosh(x) with:
;
;		acosh(x) = ln(2*x) if x*x overflow
;
;	   or:
;
;		acosh(x) = ln(x) + ln(2)  if 2*x overflow
;
;	computation mean time: 75/150ms at 4MHz
;
;------
facosh:
;------
	lda	facsgn		; acosh(x) defined only if x>=1
	bmi	?nan
	bit	facst
	bmi	?er		; nan or inf; returns nan or inf
	jsr	cmpx1		; compare x with 1.0
	beq	?z		; acosh(1) = 0
	bcs	?ok		; returns nan if |x|<1
?nan:	jmp	fldnan
?er:	sec
	rts
?z:	jmp	fldz
?ok:	lda	#<c1h5
	ldy	#>c1h5
	jsr	fccmp		; compare x vs. 1.5
	beq	?gt		; x = 1.5
	bpl	?gt		; x > 1.5
	jsr	fsubone		; z = x - 1 (x < 1.5)
	jsr	mvf_t0		; tfr0=z
	jsr	mvftoa
	jsr	fpadd		; 2*z
	jsr	mvf_t2		; tfr2 = 2*z
	lda	#<cachp
	ldy	#>cachp
	ldx	#9
	jsr	peval		; evaluates P(z)
	jsr	mvf_t1		; tfr1=P(z)
	lda	#<cachq
	ldy	#>cachq
	ldx	#8
	jsr	pevalp1		; evaluates Q(z)
	jsr	mvt1_a		; arg=P(z)
	jsr	fpdiv		; R(z)
	jsr	mvf_t3		; tfr3 = R(z)
	jsr	mvt2_f		; fac=2*z
	jsr	fsqrt		; sqrt(2*z)
	jsr	mvt3_a		; R(z)
	jmp	fpmult		; acosh(x) = sqrt(2*z)*R(z)	
?gt:	jsr	mvf_t2		; tfr2 = x
	jsr	fsquare
	bcs	?big		; x*x overflow
	jsr	fsubone		; x*x - 1
	jsr	fsqrt
	jsr	mvt2_a		; x
	jsr	fpadd
	bcs	?big		; overflow
	jmp	floge		; acosh(x) = ln[x + sqrt(x*x - 1)]
?big:	jsr	mvt2_f		; x
	jsr	mvftoa
	jsr	fpadd		; try 2*x
	bcs	?big1		; overflow
	jmp	floge		; acosh(x) = ln(2*x)
?big1:	jsr	mvt2_f		; x
	jsr	floge
	lda	#<cln2		; acosh(x) = ln(x) + ln(2)
	ldy	#>cln2
	jmp	fcadd

; fatanh - returns the inverse hyperbolic tangent of the argument
;
;	entry:
;		fac=x
;
;	exit:
;		fac=atanh(x)
;		CF = 1 if invalid result(inf or nan)
;
; strategy
;			      1	       1 + x	
; Mathematically atanh(x) =  --- * ln(-------)  , -1 < x < 1
;			      2	       1 - x
;
;	1) if |x| < 0.5 atanh(x) is approximated by a rational function:
;
;			        3	        P(z)	     2
;		atanh(x) = x + x * R(z), R(z) = ------, z = x
;					        Q(z)
;
; 	2) if |x| >= 0.5:
;
;			     1	   	       1 + |x|
; 		atanh(x) =  --- * sgn(x) * ln(---------)
;			     2		       1 - |x|
;
;	computation mean time: 80/100ms at 4MHz
;
;------
fatanh:
;------
	bit	facst		; if fac=nan or fac=inf returns nan
	bmi	?nan
	bvc	?fv
	clc			; if fac=0 returns zero
	rts
?inf:	jmp	fldinf
?nan:	jmp	fldnan		; if |x| > 1 returns nan
?fv:	jsr	cmpx1		; compare x vs. 1.0
	beq	?inf		; atanh(+/-1) = +/-inf
	bcs	?nan		; if |x| > 1 returns nan
	ACC16
	lda	facexp
	cmp	#$3FFE		; compare x vs. 0.5
	ACC08
	bcs	?gt		; |x| >= 0.5
	jsr	mvf_t2		; tfr2 = x
	jsr	fsquare		; z=x*x
	jsr	mvf_t0		; tfr0=z
	lda	#<cathp
	ldy	#>cathp
	ldx	#9
	jsr	peval		; evaluates P(z)
	jsr	mvf_t1		; tfr2=P(z)
	lda	#<cathq
	ldy	#>cathq
	ldx	#9
	jsr	pevalp1		; evaluates Q(z)
	jsr	mvt1_a		; arg=P(z)
	jsr	fpdiv		; R(z)
	jsr	mvt0_a		; arg=z
	jsr	fpmult		; z*R(z)
	jsr	mvt2_a		; arg=x
	jsr	fpmult		; x*z*R(z)
	jsr	mvt2_a		; arg=x
	jmp	fpadd		; atanh(x)=x + x*z*R(z)
?gt:	lda	facsgn
	sta	fpcsgn		; save x sign
	stz	facsgn		; |x|
	jsr	mvf_t0		; tfr0 = |x|
	jsr	faddone		; y = 1 + |x|
	jsr	mvf_t1		; tfr1 = y
	jsr	mvt0_f		; |x|	
	lda	#<cthl
	ldy	#>cthl
	jsr	fccmp		; compare |x| vs. 0.9990234375
	bmi	?dom1		; if |x| <= 0.9990234375...
	beq	?dom1		; ...computes z = 1 - |x|	
	lda	#<fce32		; otherwisa scale by 1e32
	ldy	#>fce32
	jsr	fcmult
	lda	#<fce32		; computes z = 1e32 - |x|*1e32
	ldy	#>fce32
	jsr	fcsub
	lda	#<fce32		; scale back
	ldy	#>fce32
	jsr	fcrdiv		; z = 1 - |x|
	bra	?div
?dom1:	jsr	ldaone		; arg=1
	jsr	fpsub		; z = 1 - |x|
?div:	jsr	mvt1_a		; arg = y = 1 + |x|
	jsr	fpdiv		; w = y/z
	jsr	floge		; ln(w) = ln[(1 + |x|)/(1 - |x|)]
	ACC16
	dec	facexp		; divide by2
	ACC08
	lda	fpcsgn		; restore sign
	sta	facsgn
	rts

; 0.9990234375 = tanh(3.81206529283064476456228418624)
cthl:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$C0,$FF,$FE,$3F
; 1.5
c1h5:	.BYTE	$00,$00,$00,$00,$00,$00,$00,$00,$00
	.BYTE	$00,$00,$00,$00,$00,$00,$C0,$FF,$3F

; sinh(x) coefficients
cshp:
; SHP[5] =  1.622194395724068297909052717437740288268E3 
	.BYTE	$17,$69,$DD,$D3,$6C,$86,$A5,$72,$E8
	.BYTE	$60,$AB,$61,$7D,$38,$C6,$CA,$09,$40

; SHP[4] =  1.124862584587770079742188354390171794549E6 
	.BYTE	$1D,$93,$DF,$58,$C9,$1A,$0E,$8E,$12
	.BYTE	$51,$5A,$3C,$AD,$F4,$4F,$89,$13,$40

; SHP[3] =  3.047548980769660162696832999871894196102E8 
	.BYTE	$9E,$C2,$A9,$C6,$06,$9F,$E8,$40,$D6
	.BYTE	$5B,$A0,$9D,$90,$86,$51,$91,$1B,$40

; SHP[2] =  3.966215348072348368191433063260384329745E10 
	.BYTE	$2F,$3F,$63,$A6,$E4,$FD,$2F,$10,$A0
	.BYTE	$63,$93,$8B,$F0,$C6,$C0,$93,$22,$40

; SHP[1] =  2.375869584584371194838551715348965605295E12 
	.BYTE	$0E,$D1,$C3,$AC,$F2,$82,$01,$FF,$A7
	.BYTE	$C1,$17,$32,$35,$37,$4B,$8A,$28,$40

; SHP[0] =  6.482835792103233269752264509192030816323E13 
	.BYTE	$6C,$44,$21,$C8,$30,$E2,$CC,$A8,$AE
	.BYTE	$54,$21,$24,$FB,$1C,$D8,$EB,$2C,$40

cshq:
; SHQ[5] = -9.101683853129357776079049616394849086007E2 
	.BYTE	$E1,$53,$03,$04,$33,$F5,$4A,$94,$A1
	.BYTE	$E5,$0B,$31,$D3,$C6,$8A,$E3,$08,$C0

; SHQ[4] =  4.486400519836461218634448973793765123186E5 
	.BYTE	$1B,$10,$39,$12,$99,$3F,$E1,$CF,$A5
	.BYTE	$80,$9B,$D9,$A9,$01,$10,$DB,$11,$40

; SHQ[3] = -1.492531313030440305095318968983514314656E8 
	.BYTE	$E3,$FC,$9D,$E6,$6A,$12,$5D,$95,$84
	.BYTE	$B2,$44,$D9,$B4,$C0,$56,$8E,$1A,$C0

; SHQ[2] =  3.457771488856930054902696708717192082887E10 
	.BYTE	$36,$87,$1A,$50,$C3,$93,$A6,$7A,$E4
	.BYTE	$DA,$1B,$89,$EC,$E0,$CF,$80,$22,$40

; SHQ[1] = -5.193289868803472640225483235513427062460E12 
	.BYTE	$DF,$76,$FE,$54,$9D,$2F,$E7,$64,$DE
	.BYTE	$1F,$6F,$C0,$54,$06,$25,$97,$29,$C0

; SHQ[0] =  3.889701475261939961851358705515223019890E14 
	.BYTE	$F5,$20,$1D,$96,$A4,$A9,$99,$FE,$82
	.BYTE	$FF,$18,$5B,$BC,$15,$E2,$B0,$2F,$40

; tanh(x) coefficients
cthp:
; THP[5] = -6.505693197948351084912624750702492767503E-6  
	.BYTE	$A5,$DE,$0A,$CF,$2E,$1F,$25,$59,$90
	.BYTE	$92,$24,$C2,$A2,$7A,$4B,$DA,$ED,$BF

; THP[4] = -9.804083860188429726356968570322356183383E-1  
	.BYTE	$2F,$F3,$D5,$9C,$7D,$E3,$C3,$6C,$CA
	.BYTE	$A9,$D1,$AC,$42,$0B,$FC,$FA,$FE,$BF

; THP[3] = -5.055287638900473250703725789725376004355E2  
	.BYTE	$74,$6D,$2D,$35,$A2,$58,$08,$D8,$58
	.BYTE	$8D,$87,$FF,$88,$AE,$C3,$FC,$07,$C0

; THP[2] = -7.307477148073823966594990496301416814519E4  
	.BYTE	$96,$63,$D3,$D4,$55,$B8,$E3,$D5,$DC
	.BYTE	$1D,$7E,$E1,$BF,$62,$B9,$8E,$0F,$C0

; THP[1] = -3.531606586182691280701462523692471322688E6  
	.BYTE	$96,$14,$AC,$DD,$D7,$7B,$66,$A4,$20
	.BYTE	$82,$46,$40,$58,$5A,$8D,$D7,$14,$C0

; THP[0] = -4.551377146142783468144190926206842300707E7  
	.BYTE	$E4,$75,$8D,$86,$22,$74,$D2,$EF,$DA
	.BYTE	$9C,$08,$88,$DD,$0A,$9F,$AD,$18,$C0

cthq:
; THQ[4] =  5.334865598460027935735737253027154828002E2  
	.BYTE	$19,$BD,$0A,$16,$6E,$A3,$F1,$38,$2C
	.BYTE	$3E,$88,$E8,$CB,$23,$5F,$85,$08,$40

; THQ[3] =  8.058475607422391042912151298751537172870E4 
	.BYTE	$9F,$9E,$F9,$42,$21,$C6,$63,$AC,$9D
	.BYTE	$85,$48,$0A,$C7,$60,$64,$9D,$0F,$40

; THQ[2] =  4.197073523796142343374222405869721575491E6 
	.BYTE	$22,$53,$FB,$45,$7B,$BE,$6D,$81,$45
	.BYTE	$0A,$02,$2F,$0C,$A3,$15,$80,$15,$40

; THQ[1] =  6.521134551226147545983467868553677881771E7 
	.BYTE	$95,$2E,$27,$14,$95,$C2,$CF,$71,$06
	.BYTE	$5B,$E4,$C8,$60,$F4,$C2,$F8,$18,$40

; THQ[0] =  1.365413143842835040443257277862054198329E8 
	.BYTE	$34,$03,$ED,$E4,$19,$D7,$DD,$33,$A4
	.BYTE	$75,$06,$26,$26,$48,$37,$82,$1A,$40

; asinh(x) coefficients
cashp:
; ASHP[8] = -8.104404283317298189545629468767571317688E-1  
	.BYTE	$D4,$44,$8A,$29,$62,$9C,$61,$3B,$4F
	.BYTE	$B9,$7F,$0A,$1F,$06,$79,$CF,$FE,$BF

; ASHP[7] = -4.954206127425209147110732546633675599008E1  
	.BYTE	$4C,$2A,$14,$A7,$8C,$5D,$7A,$C6,$D8
	.BYTE	$FF,$5C,$55,$1C,$12,$2B,$C6,$04,$C0

; ASHP[6] = -8.438175619831548439550086251740438689853E2  
	.BYTE	$1F,$E6,$69,$54,$E9,$DD,$A7,$DA,$DB
	.BYTE	$96,$06,$7F,$EF,$52,$F4,$D2,$08,$C0

; ASHP[5] = -6.269710069245210459536983820505214648057E3  
	.BYTE	$4D,$94,$05,$70,$20,$FD,$0E,$76,$39
	.BYTE	$98,$D0,$C8,$38,$AE,$ED,$C3,$0B,$C0

; ASHP[4] = -2.418935474493501382372711518024193326434E4  
	.BYTE	$65,$46,$D1,$97,$6C,$45,$6A,$6B,$AE
	.BYTE	$9C,$CC,$20,$A1,$B5,$FA,$BC,$0D,$C0

; ASHP[3] = -5.208121780431312783866941311277024486498E4  
	.BYTE	$C1,$0A,$1C,$9F,$EE,$A5,$FC,$D0,$D2
	.BYTE	$CF,$01,$06,$C2,$37,$71,$CB,$0E,$C0

; ASHP[2] = -6.302755086521614763280617114866439227971E4  
	.BYTE	$27,$92,$3C,$F6,$A2,$88,$78,$6D,$A9
	.BYTE	$DB,$B7,$80,$05,$8D,$33,$F6,$0E,$C0

; ASHP[1] = -4.003566436224198252093684987323233921339E4  
	.BYTE	$3D,$57,$F5,$E9,$85,$D7,$5B,$49,$1D
	.BYTE	$03,$D6,$A4,$13,$AA,$63,$9C,$0E,$C0

; ASHP[0] = -1.037690841528359305134494613113086980551E4 
	.BYTE	$75,$93,$4B,$3D,$7C,$5E,$17,$5F,$F8
	.BYTE	$DF,$B8,$9D,$37,$A2,$23,$A2,$0C,$C0

cashq:
; ASHQ[8] =  8.175806439951395194771977809279448392548E1 
	.BYTE	$2D,$40,$15,$F1,$2B,$46,$3A,$A0,$19
	.BYTE	$3E,$59,$58,$04,$21,$84,$A3,$05,$40

; ASHQ[7] =  1.822215299975696008284027212745010251320E3 
	.BYTE	$FC,$15,$F8,$77,$03,$2B,$9A,$81,$D7
	.BYTE	$34,$4E,$C6,$BC,$E3,$C6,$E3,$09,$40

; ASHQ[6] =  1.772040003462901790853111853838978236828E4 
	.BYTE	$14,$67,$63,$D4,$3C,$7C,$F1,$6E,$7F
	.BYTE	$CC,$C1,$56,$D1,$CC,$70,$8A,$0D,$40

; ASHQ[5] =  9.077625379864046240143413577745818879353E4 
	.BYTE	$C1,$7C,$F0,$4C,$1A,$FC,$B2,$4C,$13
	.BYTE	$47,$4E,$79,$7C,$20,$4C,$B1,$0F,$40

; ASHQ[4] =  2.675554475070211205153169988669677418808E5 
	.BYTE	$F5,$4D,$22,$AF,$FB,$11,$EE,$02,$2D
	.BYTE	$8E,$3E,$FA,$51,$6E,$A4,$82,$11,$40

; ASHQ[3] =  4.689758557916492969463473819426544383586E5 
	.BYTE	$9B,$B8,$C0,$1B,$1D,$C9,$87,$FB,$72
	.BYTE	$3D,$2B,$A5,$62,$FB,$FD,$E4,$11,$40

; ASHQ[2] =  4.821923684550711724710891114802924039911E5 
	.BYTE	$77,$20,$49,$F1,$27,$60,$C2,$4C,$65
	.BYTE	$17,$4A,$62,$CA,$0B,$72,$EB,$11,$40

; ASHQ[1] =  2.682316388947175963642524537892687560973E5 
	.BYTE	$F4,$0E,$30,$16,$03,$74,$A4,$B8,$3B
	.BYTE	$B5,$55,$D3,$71,$F4,$F8,$82,$11,$40

; ASHQ[0] =  6.226145049170155830806967678679167550122E4 
	.BYTE	$F9,$E9,$F0,$5D,$BA,$0D,$A3,$8E,$F4
	.BYTE	$4F,$95,$6C,$53,$73,$35,$F3,$0E,$40

; acosh(x) coefficients
cachp:
; ACHP[9] =  1.895467874386341763387398084072833727168E-1  
	.BYTE	$66,$70,$8A,$32,$3A,$8B,$D0,$B4,$43
	.BYTE	$DF,$74,$71,$94,$8D,$18,$C2,$FC,$3F

; ACHP[8] =  6.443902084393244878979969557171256604767E1 
	.BYTE	$C5,$F1,$41,$7D,$6B,$5B,$C4,$95,$21
	.BYTE	$85,$E7,$0D,$57,$C7,$E0,$80,$05,$40

; ACHP[7] =  3.914593556594721458616408528941154205393E3 
	.BYTE	$8E,$E9,$6A,$AE,$1F,$EF,$B1,$89,$ED
	.BYTE	$75,$2A,$33,$35,$7F,$A9,$F4,$0A,$40

; ACHP[6] =  9.164040999602964494412169748897754668733E4 
	.BYTE	$17,$50,$27,$B4,$1E,$5D,$6C,$09,$4E
	.BYTE	$68,$F9,$BF,$7A,$34,$FC,$B2,$0F,$40

; ACHP[5] =  1.065909694792026382660307834723001543839E6 
	.BYTE	$33,$4B,$4E,$96,$02,$E5,$64,$46,$AE
	.BYTE	$36,$1F,$EF,$8E,$AD,$1D,$82,$13,$40

; ACHP[4] =  6.899169896709615182428217047370629406305E6 
	.BYTE	$84,$A4,$A5,$35,$34,$96,$92,$3E,$6F
	.BYTE	$CE,$85,$1D,$CB,$C3,$8B,$D2,$15,$40

; ACHP[3] =  2.599781868717579447900896150777162652518E7 
	.BYTE	$46,$B9,$30,$2C,$87,$69,$CA,$F0,$F1
	.BYTE	$5D,$60,$F5,$57,$FD,$58,$C6,$17,$40

; ACHP[2] =  5.663733059389964024656501196827345337766E7 
	.BYTE	$B6,$97,$B7,$46,$A7,$44,$37,$C5,$FD
	.BYTE	$A2,$73,$02,$A6,$E4,$0D,$D8,$18,$40

; ACHP[1] =  6.606302846870644033621560858582696134512E7 
	.BYTE	$3C,$C5,$80,$74,$46,$EC,$B0,$CA,$2A
	.BYTE	$4C,$49,$FF,$1D,$AD,$02,$FC,$18,$40

; ACHP[0] =  3.190482951215438078279772140481195200593E7 
	.BYTE	$10,$22,$D8,$A0,$1A,$7C,$37,$8D,$FB
	.BYTE	$55,$46,$8E,$C1,$1E,$6A,$F3,$17,$40

cachq:
; ACHQ[8] =  1.635418024331924674147953764918262009321E2 
	.BYTE	$5C,$C5,$F5,$4B,$8C,$8D,$25,$D8,$84
	.BYTE	$72,$74,$73,$90,$B3,$8A,$A3,$06,$40

; ACHQ[7] =  7.290983678312632723073455563799692165828E3 
	.BYTE	$C3,$9C,$13,$ED,$77,$C1,$6B,$F3,$08
	.BYTE	$56,$34,$BC,$92,$DE,$D7,$E3,$0B,$40

; ACHQ[6] =  1.418207894088607063257675159183397062114E5 
	.BYTE	$9E,$1E,$0F,$35,$24,$95,$08,$A2,$00
	.BYTE	$FA,$BD,$AC,$85,$32,$7F,$8A,$10,$40

; ACHQ[5] =  1.453154285419072886840913424715826321357E6 
	.BYTE	$A8,$C8,$CD,$DC,$85,$7E,$96,$04,$A1
	.BYTE	$7D,$CB,$89,$48,$12,$63,$B1,$13,$40

; ACHQ[4] =  8.566841438576725234955968880501739464425E6 
	.BYTE	$7A,$0D,$61,$29,$7E,$C7,$01,$C1,$AB
	.BYTE	$73,$90,$46,$70,$39,$B8,$82,$16,$40

; ACHQ[3] =  3.003448667795089562511136059766833630017E7 
	.BYTE	$5F,$BB,$CA,$91,$50,$67,$4C,$7B,$80
	.BYTE	$4E,$18,$C7,$56,$1B,$25,$E5,$17,$40

; ACHQ[2] =  6.176592872899557661256383958395266919654E7 
	.BYTE	$56,$19,$E7,$C9,$A7,$81,$29,$B2,$1E
	.BYTE	$10,$DD,$A7,$2E,$4A,$9E,$EB,$18,$40

; ACHQ[1] =  6.872176426138597206811541870289420510034E7 
	.BYTE	$9F,$AE,$34,$C8,$63,$F3,$9E,$4D,$35
	.BYTE	$1D,$46,$5D,$88,$8C,$13,$83,$19,$40

; ACHQ[0] =  3.190482951215438078279772140481195226621E7 
	.BYTE	$60,$2C,$D8,$A0,$1A,$7C,$37,$8D,$FB
	.BYTE	$55,$46,$8E,$C1,$1E,$6A,$F3,$17,$40

; atanh(x) coefficients
cathp:
; ATHP[9] = -9.217569843805850417698565442251656375681E-1 
	.BYTE	$56,$9C,$44,$93,$0B,$94,$F9,$5D,$55
	.BYTE	$AE,$31,$C6,$06,$44,$F8,$EB,$FE,$BF

; ATHP[8] =  5.321929116410615470118183794063211260728E1 
	.BYTE	$00,$73,$D2,$C8,$AD,$50,$DA,$62,$26
	.BYTE	$02,$8D,$E8,$DC,$8D,$E0,$D4,$04,$40

; ATHP[7] = -9.139522976807685333981548145417830690552E2 
	.BYTE	$FF,$0B,$FD,$2D,$D9,$80,$67,$44,$AA
	.BYTE	$47,$BD,$F8,$71,$F2,$7C,$E4,$08,$C0

; ATHP[6] =  7.204314536952949779101646454146682033772E3 
	.BYTE	$B7,$34,$20,$F1,$AE,$B4,$89,$32,$1E
	.BYTE	$6C,$32,$F3,$2B,$84,$22,$E1,$0B,$40

; ATHP[5] = -3.097809640165146436529075324081668598891E4 
	.BYTE	$AB,$05,$FB,$15,$54,$FB,$82,$FE,$C1
	.BYTE	$A3,$A8,$8E,$5B,$31,$04,$F2,$0D,$C0

; ATHP[4] =  7.865376554210973897486215630898496100534E4 
	.BYTE	$D8,$06,$5E,$71,$61,$54,$5E,$34,$16
	.BYTE	$85,$AA,$48,$FD,$E1,$9E,$99,$0F,$40

; ATHP[3] = -1.211716814094785128366087489224821937203E5 
	.BYTE	$4A,$97,$EA,$1A,$1E,$BF,$9D,$77,$D2
	.BYTE	$B2,$00,$6D,$38,$D7,$A9,$EC,$0F,$C0

; ATHP[2] =  1.112669508789123834670923967462068457013E5 
	.BYTE	$4A,$6F,$5C,$D9,$90,$61,$4B,$27,$4F
	.BYTE	$92,$73,$66,$B6,$79,$51,$D9,$0F,$40

; ATHP[1] = -5.600242872292477863751728708249167956542E4 
	.BYTE	$09,$D6,$41,$CF,$B4,$1F,$BF,$51,$3F
	.BYTE	$F8,$1C,$C9,$C0,$6D,$C2,$DA,$0E,$C0

; ATHP[0] =  1.188901082233997739779618679364295772810E4 
	.BYTE	$25,$9B,$90,$FA,$10,$5E,$5E,$62,$93
	.BYTE	$13,$F1,$02,$15,$0B,$C4,$B9,$0C,$40

cathq:
; ATHQ[9] = -6.807348436010016270202879229504392062418E1 
	.BYTE	$99,$2F,$A4,$39,$46,$E2,$E3,$D8,$82
	.BYTE	$9D,$CB,$F6,$BD,$9F,$25,$88,$05,$C0

; ATHQ[8] =  1.386763299649315831625106608182196351693E3 
	.BYTE	$85,$34,$75,$16,$4D,$4C,$65,$28,$33
	.BYTE	$83,$DB,$62,$F3,$6C,$58,$AD,$09,$40

; ATHQ[7] = -1.310805752656879543134785263832907269320E4 
	.BYTE	$10,$00,$DF,$D6,$BA,$52,$8D,$F4,$87
	.BYTE	$82,$AE,$3E,$E8,$3A,$D0,$CC,$0C,$C0

; ATHQ[6] =  6.872174720355764193772953852564737816928E4 
	.BYTE	$6E,$FA,$BF,$B3,$EC,$33,$80,$DD,$73
	.BYTE	$C3,$BD,$5D,$A4,$DF,$38,$86,$0F,$40

; ATHQ[5] = -2.181008360536226513009076189881617939380E5 
	.BYTE	$F5,$02,$E5,$97,$FF,$97,$2A,$A0,$56
	.BYTE	$BF,$0D,$E7,$81,$35,$FD,$D4,$10,$C0

; ATHQ[4] =  4.362736119602298592874941767284979857248E5 
	.BYTE	$61,$1A,$B8,$5B,$6C,$27,$7A,$54,$58
	.BYTE	$B6,$9E,$2D,$95,$33,$06,$D5,$11,$40

; ATHQ[3] = -5.535251007539393347687001489396152923502E5 
	.BYTE	$7F,$3B,$18,$F4,$58,$AC,$E0,$0D,$2D
	.BYTE	$A6,$29,$B0,$9C,$51,$23,$87,$12,$C0

; ATHQ[2] =  4.321594849688346708841188057241308805551E5 
	.BYTE	$4B,$52,$86,$98,$30,$13,$CC,$A2,$B3
	.BYTE	$8F,$5C,$DD,$84,$EF,$03,$D3,$11,$40

; ATHQ[1] = -1.894075056489862952285849974761239845873E5 
	.BYTE	$03,$9B,$EB,$F1,$8F,$F5,$F9,$11,$30
	.BYTE	$D9,$90,$8D,$5C,$E0,$F7,$B8,$10,$C0

; ATHQ[0] =  3.566703246701993219338856038092901974725E4 
	.BYTE	$02,$11,$F8,$BB,$8C,$C6,$C6,$89,$AE
	.BYTE	$CE,$34,$C2,$4F,$08,$53,$8B,$0E,$40

;---------------------------------------------------------------------------
; moving routines to/from fac/arg
;---------------------------------------------------------------------------

; temporary registers tfr0..tfr5 are 20-bytes-sized register that can hold the
; full size 128 bits mantissa, the exponent, the sign and the byte status

; move arg to fac
;------
mvatof:
;------
	INDEX16
	ldx	argm
	stx	facm
	ldx	argm+2
	stx	facm+2
	ldx	argm+4
	stx	facm+4
	ldx	argm+6
	stx	facm+6
	ldx	argm+8
	stx	facm+8
	ldx	argm+10
	stx	facm+10
	ldx	argm+12
	stx	facm+12
	ldx	argm+14
	stx	facm+14
	ldx	argexp
	stx	facexp
	ldx	argsgn
	stx	facsgn
	INDEX08
	rts

; move fac to arg
;------
mvftoa:
;------
	INDEX16
	ldx	facm
	stx	argm
	ldx	facm+2
	stx	argm+2
	ldx	facm+4
	stx	argm+4
	ldx	facm+6
	stx	argm+6
	ldx	facm+8
	stx	argm+8
	ldx	facm+10
	stx	argm+10
	ldx	facm+12
	stx	argm+12
	ldx	facm+14
	stx	argm+14
	ldx	facexp
	stx	argexp
	ldx	facsgn
	stx	argsgn
	INDEX08
	rts

; move fac to temp. reg. tfr0
;------
mvf_t0:
;------
	ACC16
	lda	facm
	sta	tfr0
	lda	facm+2
	sta	tfr0+2
	lda	facm+4
	sta	tfr0+4
	lda	facm+6
	sta	tfr0+6
	lda	facm+8
	sta	tfr0+8
	lda	facm+10
	sta	tfr0+10
	lda	facm+12
	sta	tfr0+12
	lda	facm+14
	sta	tfr0+14
	lda	facexp
	sta	tfr0+16
	lda	facsgn
	sta	tfr0+18
	ACC08
	rts

; move fac to temp. reg. tfr1
;------
mvf_t1:
;------
	ACC16
	lda	facm
	sta	tfr1
	lda	facm+2
	sta	tfr1+2
	lda	facm+4
	sta	tfr1+4
	lda	facm+6
	sta	tfr1+6
	lda	facm+8
	sta	tfr1+8
	lda	facm+10
	sta	tfr1+10
	lda	facm+12
	sta	tfr1+12
	lda	facm+14
	sta	tfr1+14
	lda	facexp
	sta	tfr1+16
	lda	facsgn
	sta	tfr1+18
	ACC08
	rts

; move fac to temp. reg. tfr2
;------
mvf_t2:
;------
	ACC16
	lda	facm
	sta	tfr2
	lda	facm+2
	sta	tfr2+2
	lda	facm+4
	sta	tfr2+4
	lda	facm+6
	sta	tfr2+6
	lda	facm+8
	sta	tfr2+8
	lda	facm+10
	sta	tfr2+10
	lda	facm+12
	sta	tfr2+12
	lda	facm+14
	sta	tfr2+14
	lda	facexp
	sta	tfr2+16
	lda	facsgn
	sta	tfr2+18
	ACC08
	rts

; move fac to temp. reg. tfr3
;------
mvf_t3:
;------
	ACC16
	lda	facm
	sta	tfr3
	lda	facm+2
	sta	tfr3+2
	lda	facm+4
	sta	tfr3+4
	lda	facm+6
	sta	tfr3+6
	lda	facm+8
	sta	tfr3+8
	lda	facm+10
	sta	tfr3+10
	lda	facm+12
	sta	tfr3+12
	lda	facm+14
	sta	tfr3+14
	lda	facexp
	sta	tfr3+16
	lda	facsgn
	sta	tfr3+18
	ACC08
	rts

; move arg to temp. reg. tfr0
;------
mva_t0:
;------
	ACC16
	lda	argm
	sta	tfr0
	lda	argm+2
	sta	tfr0+2
	lda	argm+4
	sta	tfr0+4
	lda	argm+6
	sta	tfr0+6
	lda	argm+8
	sta	tfr0+8
	lda	argm+10
	sta	tfr0+10
	lda	argm+12
	sta	tfr0+12
	lda	argm+14
	sta	tfr0+14
	lda	argexp
	sta	tfr0+16
	lda	argsgn
	sta	tfr0+18
	ACC08
	rts

; move temp. reg. tfr0 to fac
;------
mvt0_f:
;------
	ACC16
	lda	tfr0
	sta	facm
	lda	tfr0+2
	sta	facm+2
	lda	tfr0+4
	sta	facm+4
	lda	tfr0+6
	sta	facm+6
	lda	tfr0+8
	sta	facm+8
	lda	tfr0+10
	sta	facm+10
	lda	tfr0+12
	sta	facm+12
	lda	tfr0+14
	sta	facm+14
	lda	tfr0+16
	sta	facexp
	lda	tfr0+18
	sta	facsgn
	ACC08
	rts

; move temp. reg. tfr1 to fac
;------
mvt1_f:
;------
	ACC16
	lda	tfr1
	sta	facm
	lda	tfr1+2
	sta	facm+2
	lda	tfr1+4
	sta	facm+4
	lda	tfr1+6
	sta	facm+6
	lda	tfr1+8
	sta	facm+8
	lda	tfr1+10
	sta	facm+10
	lda	tfr1+12
	sta	facm+12
	lda	tfr1+14
	sta	facm+14
	lda	tfr1+16
	sta	facexp
	lda	tfr1+18
	sta	facsgn
	ACC08
	rts

; move temp. reg. tfr2 to fac
;------
mvt2_f:
;------
	ACC16
	lda	tfr2
	sta	facm
	lda	tfr2+2
	sta	facm+2
	lda	tfr2+4
	sta	facm+4
	lda	tfr2+6
	sta	facm+6
	lda	tfr2+8
	sta	facm+8
	lda	tfr2+10
	sta	facm+10
	lda	tfr2+12
	sta	facm+12
	lda	tfr2+14
	sta	facm+14
	lda	tfr2+16
	sta	facexp
	lda	tfr2+18
	sta	facsgn
	ACC08
	rts
	
; move temp. reg. tfr0 to arg
;------
mvt0_a:
;------
	ACC16
	lda	tfr0
	sta	argm
	lda	tfr0+2
	sta	argm+2
	lda	tfr0+4
	sta	argm+4
	lda	tfr0+6
	sta	argm+6
	lda	tfr0+8
	sta	argm+8
	lda	tfr0+10
	sta	argm+10
	lda	tfr0+12
	sta	argm+12
	lda	tfr0+14
	sta	argm+14
	lda	tfr0+16
	sta	argexp
	lda	tfr0+18
	sta	argsgn
	ACC08
	rts

; move temp. reg. tfr1 to arg
;------
mvt1_a:
;------
	ACC16
	lda	tfr1
	sta	argm
	lda	tfr1+2
	sta	argm+2
	lda	tfr1+4
	sta	argm+4
	lda	tfr1+6
	sta	argm+6
	lda	tfr1+8
	sta	argm+8
	lda	tfr1+10
	sta	argm+10
	lda	tfr1+12
	sta	argm+12
	lda	tfr1+14
	sta	argm+14
	lda	tfr1+16
	sta	argexp
	lda	tfr1+18
	sta	argsgn
	ACC08
	rts

; move temp. reg. tfr2 to arg
;------
mvt2_a:
;------
	ACC16
	lda	tfr2
	sta	argm
	lda	tfr2+2
	sta	argm+2
	lda	tfr2+4
	sta	argm+4
	lda	tfr2+6
	sta	argm+6
	lda	tfr2+8
	sta	argm+8
	lda	tfr2+10
	sta	argm+10
	lda	tfr2+12
	sta	argm+12
	lda	tfr2+14
	sta	argm+14
	lda	tfr2+16
	sta	argexp
	lda	tfr2+18
	sta	argsgn
	ACC08
	rts

; move temp. reg. tfr3 to arg
;------
mvt3_a:
;------
	ACC16
	lda	tfr3
	sta	argm
	lda	tfr3+2
	sta	argm+2
	lda	tfr3+4
	sta	argm+4
	lda	tfr3+6
	sta	argm+6
	lda	tfr3+8
	sta	argm+8
	lda	tfr3+10
	sta	argm+10
	lda	tfr3+12
	sta	argm+12
	lda	tfr3+14
	sta	argm+14
	lda	tfr3+16
	sta	argexp
	lda	tfr3+18
	sta	argsgn
	ACC08
	rts

; ldfac - load fac with a constant K stored in program memory
;
;	entry:
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		fac = K
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;-----
ldfac:
;-----
	sta	fcp		; set long pointer to K
	sty	fcp+1
	lda	#.SEG.ldfac
	sta	fcp+2
	ldx	#0
	stx	facst		; always assume valid K
	ACC16
	lda	[fcp]		; set mantissa
	sta	facm
	ldy	#2
	lda	[fcp],y
	sta	facm+2
	ldy	#4
	lda	[fcp],y
	sta	facm+4
	ldy	#6
	lda	[fcp],y
	sta	facm+6
	ldy	#8
	lda	[fcp],y
	sta	facm+8
	ldy	#10
	lda	[fcp],y
	sta	facm+10
	ldy	#12
	lda	[fcp],y
	sta	facm+12
	ldy	#14
	lda	[fcp],y
	sta	facm+14
	ldy	#16
	lda	[fcp],y
	bpl	?p
	dex
?p:	and	#$7FFF
	sta	facexp		; set exponent
	ACC08
	stx	facsgn		; set sign
	rts
	
; ldarg - load arg with a constant K stored in program memory
;
;	entry:
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		arg = K
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
ldarg:
	sta	fcp		; set long pointer to K
	sty	fcp+1
	lda	#.SEG.ldarg
	sta	fcp+2

; ldarg2 - entry if long pointer fcp was already set
ldarg2:
	ldx	#0
	stx	argst		; always assume valid K
	ACC16
	lda	[fcp]		; set mantissa
	sta	argm
	ldy	#2
	lda	[fcp],y
	sta	argm+2
	ldy	#4
	lda	[fcp],y
	sta	argm+4
	ldy	#6
	lda	[fcp],y
	sta	argm+6
	ldy	#8
	lda	[fcp],y
	sta	argm+8
	ldy	#10
	lda	[fcp],y
	sta	argm+10
	ldy	#12
	lda	[fcp],y
	sta	argm+12
	ldy	#14
	lda	[fcp],y
	sta	argm+14
	ldy	#16
	lda	[fcp],y
	bpl	?p
	dex
?p:	and	#$7FFF
	sta	argexp		; set exponent
	ACC08
	stx	argsgn		; set sign
	rts

;----------------------------------------------------------------------------
; polynomial evaluatation
;----------------------------------------------------------------------------

; peval - evaluate polynomial of degree N
;
;	entry:
;		A	= low address of coefficient C
;						      N
;
;		Y	= high address of coefficient C
;						       N
;		X	= degree (N)
;		tfr0	= x (temp. register #0)
;
;	exit:                                 2          N
;		fac	= y  =  C  + C x + C x  +...+ C x
;				 0    1     2          N
;
; Constant Cn..C0 are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine), from
; the highest order Cn to lowest order C0.
;
;-----
peval:
;-----
	stx	pdeg
	jsr	ldfac		; fac=coefficient Cn
?lp:	jsr	mvt0_a		; arg=tfr0
	jsr	fpmult		; multiplies by x
	ACC16CLC
	lda	fcp		; next coefficient
	adc	#FCSIZ
	sta	fcp
	ACC08
	jsr	fcadd		; add coefficient Ck
	dec	pdeg
	bne	?lp
	rts

; pevalp1 - evaluate polynomial of degree N+1
;
;	entry:
;		A	= low address of coefficient C
;						      N
;
;		Y	= high address of coefficient C
;						       N
;		X	= degree - 1 (N)
;		tfr0	= x (temp. register #0)
;
;	exit:                                 2          N     N+1
;		fac	= y  =  C  + C x + C x  +...+ C x  +  x
;				 0    1     2          N
;
; Constant Cn..C0 are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine), from
; the highest order Cn to lowest order C0.
;
;-------
pevalp1:
;-------
	stx	pdeg
	jsr	ldfac		; coefficient Cn
	jsr	mvt0_a		; arg=tfr0
	jsr	fpadd		; x + Cn
?lp:	jsr	mvt0_a		; loop
	jsr	fpmult		; multiplies by x
	ACC16CLC
	lda	fcp		; next coefficient
	adc	#FCSIZ
	sta	fcp
	ACC08
	jsr	fcadd		; add coefficient Ck
	dec	pdeg
	bne	?lp
	rts

;----------------------------------------------------------------------------
; utilities & helper routines
;----------------------------------------------------------------------------

; fccmp - compare fac versus a constant stored in program memory
;
;	entry:
;		fac = x
;		A = low  address of constant K
;		Y = high address of constant K
;
;	exit:
;		if fac < K: ZF=0,NF=1
;		if fac = K: ZF=1,NF=0
;		if fac > K: ZF=0,NF=0
;
; This routine is used internally and not intended for end use.
; Constant are stored unpacked, and with full size 128 bits mantissa,
; in program memory segment(the code segment that hold this routine).
;
;-----
fccmp:
;-----
	sta	fcp		; set long pointer to K
	sty	fcp+1
	lda	#.SEG.fccmp
	sta	fcp+2
	ldy	#17
	lda	[fcp],y		; K sign
	eor	facsgn		; compare with fac sign
	bpl	?same		; sign match
	lda	facsgn		; sign unmatch so return...
	bra	?sgn		; ...fac sign
?same:	ACC16
	dey
	lda	[fcp],y		; biased exponent
	and	#$7FFF		; mask off sign
	cmp	facexp
	bcc	?chk		; fac > K (CF=0)
	bne	?chk		; fac < K (CF=1)
	ldy	#14		; same exponent so now compare mantissa
	lda	[fcp],y
	cmp	facm+14
	bne	?chk		; CF=0 if fac>K else CF=1 if fac<K
	ldy	#12
	lda	[fcp],y
	cmp	facm+12
	bne	?chk
	ldy	#10
	lda	[fcp],y
	cmp	facm+10
	bne	?chk
	ldy	#8
	lda	[fcp],y
	cmp	facm+8
	bne	?chk
	ldy	#6
	lda	[fcp],y
	cmp	facm+6
	bne	?chk
	ldy	#4
	lda	[fcp],y
	cmp	facm+4
	bne	?chk
	ldy	#2
	lda	[fcp],y
	cmp	facm+2
	bne	?chk
	lda	[fcp]
	cmp	facm
?chk:	ACC08
	beq	?done		; fac=K so return ZF=1
	lda	facsgn
	bcc	?sgn		; fac>K
	eor	#$FF		; invert sign (fac<K)
?sgn:	rol	a		; CF=sign
	lda	#$FF		; NF=1 if fac<K
	bcs	?done
	lda	#1		; NF=0 if fac>K
?done:	rts

; signed multiplication 16 bit
;
;	entry:	C = multiplicand 1 16 bit
;		X = multiplicand 2 low byte
;		Y = multiplicand 2 high byte
;
;	exit:	C = result high word
;		X = result low-low byte
;		Y = result low-high byte
;
; call with A in 16 bit mode
;
;-----
imult:
;-----
	.LONGA	on
	.LONGI	off

	sta	mcand1		; store mcand1&mcand2
	stx	mcand2
	sty	mcand2+1
	eor	mcand2		; sign of the result
	sta	mcsgn
	ldx	#0
	ldy	mcand1+1
	bpl	?p1		; mcand1 is positive
	sec
	txa
	sbc	mcand1		; complement mcand1
	sta	mcand1
?p1:	ldy	mcand2+1
	bpl	?p2		; mcand2 is positive
	sec
	txa
	sbc	mcand2		; complement mcand2
	sta	mcand2
?p2:	txa			; clear high word of result
	ldx	#17		; 17 bit loop
	clc
?shr:	ror	a		; shift in any carry - high result
	ror	mcand1		; low result
	bcc	?no		; no add
	clc
	adc	mcand2
?no:	dex
	bne	?shr		; repeat
	sta	mcand2		; store result high
	bit	mcsgn		; if result is positive...
	bpl	?done		; ...done (C=result high)
	txa
	sec			; else complement result
	sbc	mcand1
	sta	mcand1
	txa
	sbc	mcand2		; C=result high word
?done:	ldx	mcand1		; X=result low-low byte
	ldy	mcand1+1	; Y=result low-high byte
	rts

	.LONGA	off

; unsigned division 16 bit
;
;	entry:	C = 16 bit dividend
;		X = 16 bit divisor
;
;	exit:	C = 16 bit quotient
;		Y = 16 bits remainder
;
;	use:	all
;
;	note:	no check for null divisor
;
;	call in 16 bit mode
;-----
udiv:
;-----
	.LONGA	on
	.LONGI	on

	stx	dvsor		; divisor	
	tay			; Y=dividend
	stz	quot		; init quotient
	txa			; C=divisor
	ldx	#1		; bit counter
?shd:	asl	a		; shift divisor: get leftmost bit
	bcs	?div		; go to division
	inx
	cpx	#17		; test all divisor bit's
	bne	?shd
?div:	ror	a		; put shifted-out bit back
	sta	dvsor
?sub:	tya			; get dividend
	sec
	sbc	dvsor
	bcc	?no		; can't subctract, retain old dividend
	tay			; Y=new dividend
?no:	rol	quot		; shift carry into quotient (1 if division)
	lsr	dvsor		; shift right divisor for next subtract
	dex
	bne	?sub		; repeat
	sty	dvsor		; store remainder
	lda	quot		; C=quotient
	rts

	.LONGA	off
	.LONGI	off

; end of file

