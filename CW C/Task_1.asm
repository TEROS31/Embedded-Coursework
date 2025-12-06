#include <p16F887.inc>

    __CONFIG _CONFIG1, _LVP_OFF & _FCMEN_OFF & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
    __CONFIG _CONFIG2, _WRT_OFF & _BOR21V

    org 0

start:
    BSF     STATUS, RP0          ; Bank 1
    MOVLW   b'11111111'          ; PORTB = inputs (buttons)
    MOVWF   TRISB
    CLRF    TRISD                ; PORTD = outputs (7-seg)
    BCF     STATUS, RP0          ; Back to Bank 0

check:
    BTFSS   PORTB, 0            ; RB0 pressed? (active-low)
    GOTO    yes_button
    BTFSS   PORTB, 1             ; RB1 pressed? (active-low)
    GOTO    no_button
    GOTO    check                ; nothing pressed ? keep last display


yes_button:
    MOVLW   b'01101101'          ; pattern for "5"
    MOVWF   PORTD
    GOTO    check


no_button:
    MOVLW   b'01111101'          ; pattern for "6"
    MOVWF   PORTD
    GOTO    check


    END
