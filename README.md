revealra300radio
================

ATMega32A program to control a Reveal RA 300 ISA soundcard

This code should work as long as you keep our wiring scheme:

PINA0: Init
PINA1: not(VolUp)
PINA2: not(VolDn)

PINC0-7 Data 0-7

PIND0: Addr
PIND1: AEN
PIND2: IOR 

If you want to change it you need to change the labels too.

If you encounter any problems message amki (amki@amki.eu) or Caradas (caradas@caradas.info)