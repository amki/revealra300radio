;+----------------------------------------------------------------------+
;| Title         : Radioreveal					                        |
;+----------------------------------------------------------------------+
;| Funktion      :		                                                |
;| Schaltung     :		                                                |
;+----------------------------------------------------------------------+
;| Processor     : ATmega32A                                            |
;| Language      : Assembler                                            |
;| Datum         :		                                                |
;| Version       :		                                                |
;| Autors        : amki (amki@amki.eu) & Caradas (caradas@caradas.info) |
;+----------------------------------------------------------------------+
;include	""
;------------------------------------------------------------------------
;Reset and Interrupt vector             ;VNr.  Beschreibung
begin:		rjmp	main		;1   POWER ON RESET
		
;------------------------------------------------------------------------
; Notes
; D-Latch is a LS273
; PLL synth is a LM7000
; Vol amplifier is a LC7534
;
; D-Latch is between ISA bus and PLL/amp to keep random data from reconfiguring the card. 
;
; AtMega32A Pins:
; PA0: Init, PA1: not(VolUp), PA2: not(VolDn)
; PC0-7 Data 0-7
; PD0: Addr; PD1: AEN; PD2: IOR 
; We separated the address pins since that was easier, the address of the card can either be 0x20C or 0x30C (which is 1 bit difference)
; Skip the first two LSB bits since the card does not use them (0x20C == 0x20D == 0x20E == 0x20F for this card)
; IOR must be HIGH to enable D-Latch reading data (also cycle AEN)
; PLL Register 24 bit long
; 14-bit Frequency
;  2-bit For LSI test (?)		-> send 0s
;  4-bit Band data (Display?)	-> send 0s
;  3-bit Reference frequency		-> 010 (25kHz)
;  1-bit FM/AM Selector			-> 1 (FM)/0 (AM)
;
; Calculate Frequency:
; With 25kHz reference frequency (see PLL datasheet) (need other mulitplier for other reference):
; TargetFreq*40 + 0x1AC
;
; To switch radio on, send to PLL:
; Calculated frequency 14-bit SERIAL
; 0xA0 -> 1010 0000 10-bit SERIAL (values see PLL datasheet, picks AM/FM, reference freq etc.)
; 0xC8 -> 1100 1000 => Enable Sound (NOT serial)
;
; RADIO OFF
; Calculated frequency 14-bit SERIAL
; 0xA0 -> 1010 0000 10-bit SERIAL (values see PLL datasheet, picks AM/FM, reference freq etc.)
; 0xC0 -> 1100 1000 => Disable Sound (NOT serial)
;
;  0  0  0  0  0  0  0  0 <- 8-bit ISA bus
;  d7 d6 d5 d4 d3 d2 d1 d0
; d0: PLL Chip_Enable
; d1: PLL Clock
; d2: PLL DATA
; d3: VOL Chip_Enable
; d4: PLL STRQ (Auto-Tuning) [undiscovered]
; d5: empty
; d6: not(VOL up)
; d7: not(VOL down)
;
; Calculate Frequency:
; With 25kHz reference frequency (see PLL datasheet):
; TargetFreq*40 + 0x1AC
;
; Volume UP Code: 10001000 ; 11001000
;                 ^^  ^      ^^  ^   
; Volume DN Code: 01001000 ; 11001000
;                 ^^  ^      ^^  ^   
; No idea why 11001000, seems to enable tuner output
;
; Push values to the PLL shift register:
;
; Serial 0:       00000001 00000011
;                    ^ ^^^    ^ ^^^
; Serial 1:       00000101 00000111
;                    ^ ^^^    ^ ^^^
;   (put value on d2, clock d1, d0 is PLL enable, keep 1)
; Pass (!!!)EDGE-TRIGGERED(!!!) D-Latch:
; To make the D-Latch accept your values and put them through to VOL and PLL
; cycle AEN (this cycles D-Latch's CP) and remember to keep not(MR) to high (MR -> low is master reset) (see LS273 datasheet)
;
; Offset to add to frequency at 25kHz to compensate auto tuning circuit (10,7Mhz, see PLL datasheet):
; 0x1AC -> 428 -> (10.7 * 40)
;
;
;Start, Power ON, Reset
;
main:		ldi	r16, low(RAMEND)
		out	SPL, r16	
		ldi	r16, high(RAMEND)
		out	SPH, r16

		; Init z pointer
		ldi ZL, low(freqtab*2)
		ldi ZH, high(freqtab*2)
		
		ldi r16, 0xff
		out ddrd, r16
		out ddrc, r16
		ldi r16, 0x00
		out portc, r16
		out portd, r16

;------------------------------------------------------------------------
mainloop: ; This keeps running until a button press triggers a call
sbis pina,0
call init
sbis pina,1
call vup
sbis pina,2
call vdn
ldi r16, 0x00
out portc, r16
	
rjmp mainloop
;------------------------------------------------------------------------

;------------------------------------------------------------------------
init: ; Tune to the next frequency in freqtab
call carden ; Make the card listen to our data
call pickfreq ; Picks the next frequency in freqtab to tune to
call sendfreq ; Sends the frequency picked to the card
call sendstatic ; Sends data needed to configure the card (see datasheet)
call vup ; Needed to activate sound output (just 11001000 + clock is needed)
ret
;------------------------------------------------------------------------

;------------------------------------------------------------------------
vup: ; Ups the volume one step
call carden ; make the card listen
ldi r18, 0b10001000
out portc, r18
call lclock
call wait ; wait to keep audible clicks away
ldi r18, 0b11001000
out portc, r18 ; Stop volume increase
call lclock
ret
;------------------------------------------------------------------------

;------------------------------------------------------------------------
vdn: ; Downs the volume one step
call carden ; make the card listen
ldi r18, 0b01001000
out portc, r18
call lclock
call wait ; wait to keep audible clicks away
ldi r18, 0b11001000
out portc, r18 ; Stop volume decrease
call lclock
ret
;------------------------------------------------------------------------

;------------------------------------------------------------------------
sendfreq: ; Send the frequency serially to the PLL
ldi r18, 0x00
;ldi r19, 0x30 Leave this alone, pickfreq fills these
;ldi r20, 0x11
sendfreq1: ; sendfreq loop, DO NOT RESET r18 (counter)
cpi r18 ,0x08
breq sendfreq2 ; continue to send
sbrs r19, 0
call reg0 ; send a 0 to the PLL
sbrc r19, 0
call reg1 ; send a 1 to the PLL
ror r19        ;
inc r18        ; loop stuff
jmp sendfreq1  ;

sendfreq2: ; send rest of frequency to PLL
cpi r18, 0x0E
breq sendfreqend
sbrs r20,0
call reg0
sbrc r20,0
call reg1
ror r20
inc r18
jmp sendfreq2

sendfreqend:
ret
;------------------------------------------------------------------------

; Sends T0,T1,B0,B1,B2,TB
;------------------------------------------------------------------------
sendstatic: ; Send some stuff _we_ didn't want to change to PLL (FM/AM switch etc.)
ldi r18, 0x00
sendstatic1:
cpi r18, 0x06
breq sendstatic2
call reg0
inc r18
jmp sendstatic1

; Sends R0, R1, R2, S
sendstatic2: ; continue sending static stuff
call reg0
call reg1
call reg0
call reg1
ret
;------------------------------------------------------------------------

;------------------------------------------------------------------------
reg0: ; Sends a serial 0 into the PLL's shift register
ldi r16, 0x01
ldi r17, 0x03
out portc, r16
call lclock ; don't forget to clock it into the shift register!
out portc, r17
call lclock ; don't forget to clock it into the shift register!
ret
;------------------------------------------------------------------------
reg1: ; Sends a serial 1 into the PLL's shift register
ldi r16, 0x05
ldi r17, 0x07
out portc, r16
call lclock ; don't forget to clock it into the shift register!
out portc, r17
call lclock ; don't forget to clock it into the shift register!
ret
;------------------------------------------------------------------------

; Pins: 1
; PC0-7 Data 0-7
; PD0, Addr; PD1, AEN; PD2, IOW; PD3,IOR;
;------------------------------------------------------------------------
carden:
; Set      00000011 Address + AEN
ldi r18, 0b00000011
out portd, r18
; Set      00000101 Address + not(AEN) + IOwrite
ldi r18, 0b00000101 ;Port C,1 AEN ior
out portd, r18
ret
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
wait:
ret
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
lclock: ;Clock AEN to make D-latch repeat our value to PLL/VOL
sbi portd, 1
nop
cbi portd, 1
ret
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
pickfreq: ; load lsbs to r19 and msbs to r20
lpm r20, Z+ ; It's not like we actually need the stack, do we? :P
lpm r19, Z+
cpi ZL, low(freqend*2) ; Compare if freqend low byte is same as Z low byte
breq comparehigh ; compare the high bytes if true
dn:
ret

restartz: ; Resets the Z pointer to freqtab
; Init z pointer
ldi ZL, low(freqtab*2)
ldi ZH, high(freqtab*2)
jmp dn

comparehigh: ; Compares the high byte of z to freqend high byte
cpi ZH, high(freqend*2)
breq restartz ; If this is ALSO true, reset Z pointer
jmp dn ; If not do nothing

freqtab:
.db 0x0F,0x48 ;87,1 SWR1						 87,1 * 40 = 3484 + 428 = 3912 -> 0x0F48
.db 0x0F,0xF4 ;91,4 Bayern1						 91,4 * 40 = 3656 + 428 = 4084 -> 0x0FF4
.db 0x10,0x3C ;93,2 Bayern 2					 93,2 * 40 = 3728 + 428 = 4156 -> 0x103C
.db 0x11,0x30 ;99,3 Bayern 3					 99,3 * 40 = 3972 + 428 = 4400 -> 0x1130
.db 0x11,0x40 ;99,7 SWR 3						 99,7 * 40 = 3988 + 428 = 4416 -> 0x1140
.db 0x11,0x50 ;100,1 Hitradio Antenne1			100,1 * 40 = 4004 + 428 = 4432 -> 0x1150
.db 0x11,0x88 ;101,5 Antenne Bayern(Schrott)	101,5 * 40 = 4060 + 428 = 4488 -> 0x1188
.db 0x11,0xA0 ;102,1 Sunshine Live				102,1 * 40 = 4084 + 428 = 4512 -> 0x11A0
.db 0x11,0xDB ;103,5 Radio Ton					103,5 * 40 = 4140 + 428 = 4568 -> 0x11D8
.db 0x12,0x60 ;106,9 Gong						106,9 * 40 = 4276 + 428 = 4704 -> 0x1260
freqend: