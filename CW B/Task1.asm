; Student ID parameters
; ----------------------
;  Student ID: 20508200  (Last two digits = 00)
;  A = 0 use 5  
;  B = 0 use 6  
;  C = A + B = 5 + 6 = 11
;  TH1 = A × 30
;      = 5 × 30
;      = 150
;  TH2 = TH1 + (B × 30)
;      = 150 + (6 × 30)
;      = 150 + 180
;      = 330
;  TH3 = TH2 + (C × 15)
;      = 330 + (11 × 15)
;      = 330 + 165
;      = 495
;  Voltage = (ADC / 1023) × 5V
;     TH1 Voltage = (150 / 1023) × 5 = 0.73 V
;     TH2 Voltage = (330 / 1023) × 5  = 1.61 V
;     TH3 Voltage = (495 / 1023) × 5  = 2.42 V



;  FINAL VALUES
;  ------------
;  A = 5
;  B = 6
;  C = 11
;  TH1 = 150
;  TH2 = 330
;  TH3 = 495
;  Voltage ranges:
;     STATE 1: 0   - 150   (0.00V - 0.73V)
;     STATE 2: 150 - 330   (0.73V - 1.61V)
;     STATE 3: 330 - 495   (1.61V - 2.42V)
;     STATE 4: 495 - 1023  (2.42V - 5.00V)
;  8-bit ADRESH thresholds (TH/4):
;     TH1_8bit = 150/4 = 37
;     TH2_8bit = 330/4 = 82
;     TH3_8bit = 495/4 = 123



; CONNECTIONS
; -----------
;  Potentiometer: RA0 (AN0)
;  LEDs: RB4, RB5, RB6, RB7 (PORTB upper 4 bits)
;  START Button: RB0 (Active LOW)
;  STOP Button: RB1 (Active LOW)
;  7-Segment Display: RD0-RD6, PORTD

; -----------------------------------------------------------------------------------------------------------------------------------------------------------------------



        LIST        P=16F887
        #include    <P16F887.inc>
        __CONFIG    _CONFIG1, _FOSC_INTRC_NOCLKOUT & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _CPD_OFF & _BOREN_ON & _IESO_OFF & _FCMEN_OFF
        __CONFIG    _CONFIG2, _WRT_OFF & _BOR40V & _LVP_OFF


        CBLOCK      0x20
            ADC_VALUE      
            DELAY_COUNT1
            DELAY_COUNT2
            DELAY_COUNT3
        ENDC

        ORG         0x0000
        GOTO        INIT

; INITIALIZATION
; ---------------
INIT:
        ; TRIS = 0, OUTPUT (Display, etc) 
		; TRIS = 1, INPUT (Read, etc)
		
		; Conf portD: Set as display (7-segment)
        BANKSEL     TRISD
        CLRF        TRISD
         
		; Conf portB: RB0-RB1 input (Buttons), RB4-RB7 output (LEDs)
        BANKSEL     TRISB
        MOVLW       b'00001111'     ; RB0-RB3 input, RB4-RB7 output
        MOVWF       TRISB
          
        ; Conf RA0: Read RA0 as input
        BANKSEL     TRISA
        BSF         TRISA,0         
        
		; ANSEL = 1 (Analog); ANSEL = 0 (Digital)
		; ANSEL (RA7 - RA0)
		
        ; Conf RA0: Set as analog		
        BANKSEL     ANSEL
        MOVLW       b'00001101'     ; Set RA0 (Somehow setting this makes it use 1 LED display only)
        MOVWF       ANSEL
        
        BANKSEL     ANSELH
        CLRF        ANSELH
        
        ; Conf ADCON1 
		; ADFM 0 = Left justified, 8-bit result in ADRESH (bit 7)
        ; Unused 0 bit
		; VCFG1 & VCFG0 = 00, Use power supply voltage 
		; Unused 0000
        BANKSEL     ADCON1
        MOVLW       b'00000000'     ; 0-0-00-0000
        MOVWF       ADCON1

		; Conf ADCON0
		; ADCS1 ADCS0 = 10 = Fosc/32 (bits 7-6)
        ; CHS3-CHS0 = 0000 = AN0 selected (bits 5-2)
        ; GO/DONE   = 0 = Not started (bit 1)
        ; ADON      = 1 = ADC enabled (bit 0)
        BANKSEL     ADCON0
        MOVLW       b'10000001'     ; 10-0000-0-1   
        MOVWF       ADCON0
        
        CALL        DELAY_50MS
        
        ; Clear PORTD
        BANKSEL     PORTD
        CLRF        PORTD
        
        ; Clear PORTB upper bits (LEDs)
        BANKSEL     PORTB
        MOVLW       b'00001111'
        ANDWF       PORTB,F
        
        GOTO        STATE0

; STATE 0
; --------
STATE0:
        ; Clear PORTB LEDs (RB4-RB7 OFF)
        BANKSEL     PORTB
        MOVLW       b'00001111'
        ANDWF       PORTB,F
        
        ; Display '0' on 7-segment
        BANKSEL     PORTD
        CALL        DISPLAY_0
        
WAIT_START:
        BANKSEL     PORTB
        BTFSS       PORTB,0         ; Check if RB0 is HIGH (not pressed)
        GOTO        BUTTON_PRESSED  ; Button pressed (LOW), debounce and start
        GOTO        WAIT_START      ; Not pressed, keep waiting

BUTTON_PRESSED:
        ; Button pressed - debounce delay
        CALL        DELAY_50MS
        
        ; Check if still pressed
        BANKSEL     PORTB
        BTFSS       PORTB,0
        GOTO        STATE1          ; Still pressed, proceed to STATE1
        GOTO        WAIT_START      ; Was noise, go back to waiting

; STATE 1 - LOW, 0-150
; ---------------------
STATE1:
        ; Start ADC conversion
        BANKSEL     ADCON0
        BSF         ADCON0,GO
        
WAIT_ADC1:
        BTFSC       ADCON0,GO       ; Wait for conversion to complete
        GOTO        WAIT_ADC1
        
        ; Add delay
        CALL        DELAY_50MS
        
        ; Read 8-bit result from ADRESH
        BANKSEL     ADRESH
        MOVF        ADRESH,W
        MOVWF       ADC_VALUE
        
        ; Set LED pattern: RB4 = ON, others OFF
        BANKSEL     PORTB
        MOVLW       b'00001111'     ; Clear LED bits
        ANDWF       PORTB,F
        MOVLW       b'00010000'     ; Set RB4
        IORWF       PORTB,F
        
        ; Display '1' on 7-segment
        BANKSEL     PORTD
        CALL        DISPLAY_1
        
        ; Check if ADC >= 37 (TH1)
        MOVF        ADC_VALUE,W		; LOAD ADC_VALUE into W
        SUBLW       .37             ; Literal - W = 37 - ADC VALUE
        BTFSS       STATUS,C        ; Positive C = 0, Negative C = 1
        GOTO        STATE2          
        
STAY_STATE1:
        ; Check STOP button (RB1)
        BANKSEL     PORTB
        BTFSS       PORTB,1         ; Check if RB1 is HIGH (not pressed)
        GOTO        STATE0          ; Button pressed (LOW), return to IDLE
        
        ; Delay B × 100ms = 600ms
        CALL        DELAY_600MS
        GOTO        STATE1


; STATE 2 - MEDIUM RANGE, 150-330
; --------------------------------

STATE2:
        ; Start ADC conversion
        BANKSEL     ADCON0
        BSF         ADCON0,GO
        
WAIT_ADC2:
        BTFSC       ADCON0,GO
        GOTO        WAIT_ADC2
        
        ; Add acquisition delay
        CALL        DELAY_50MS
        
        ; Read result
        BANKSEL     ADRESH
        MOVF        ADRESH,W
        MOVWF       ADC_VALUE
        
        ; Set LED pattern: RB5 = ON
        BANKSEL     PORTB
        MOVLW       b'00001111'     ; Clear LED bits
        ANDWF       PORTB,F
        MOVLW       b'00100000'     ; Set RB5
        IORWF       PORTB,F
        
        ; Display '2' on 7-segment
        BANKSEL     PORTD
        CALL        DISPLAY_2
        
        ; Check if ADC < 37 (below TH1)
        MOVF        ADC_VALUE,W
        SUBLW       .37
        BTFSC       STATUS,C
        GOTO        STATE1          ; Drop to STATE1
        
        ; Check if ADC >= 82 (TH2)
        MOVF        ADC_VALUE,W
        SUBLW       .82
        BTFSS       STATUS,C
        GOTO        STATE3          ; Move to STATE3
        
STAY_STATE2:
        ; Check STOP button (RB1)
        BANKSEL     PORTB
        BTFSS       PORTB,1
        GOTO        STATE0
        
        CALL        DELAY_600MS
        GOTO        STATE2

; STATE 3 - HIGH RANGE, 330 - 495
; --------------------------------
STATE3:
        ; Start ADC conversion
        BANKSEL     ADCON0
        BSF         ADCON0,GO
        
WAIT_ADC3:
        BTFSC       ADCON0,GO
        GOTO        WAIT_ADC3
        
        ; Add acquisition delay
        CALL        DELAY_50MS
        
        ; Read result
        BANKSEL     ADRESH
        MOVF        ADRESH,W
        MOVWF       ADC_VALUE
        
        ; Set LED pattern: RB6 = ON
        BANKSEL     PORTB
        MOVLW       b'00001111'     ; Clear LED bits
        ANDWF       PORTB,F
        MOVLW       b'01000000'     ; Set RB6
        IORWF       PORTB,F
        
        ; Display '3' on 7-segment
        BANKSEL     PORTD
        CALL        DISPLAY_3
        
        ; Check if ADC < 82 (below TH2)
        MOVF        ADC_VALUE,W
        SUBLW       .82
        BTFSC       STATUS,C
        GOTO        STATE2          ; Drop to STATE2
        
        ; Check if ADC >= 123 (TH3)
        MOVF        ADC_VALUE,W
        SUBLW       .123
        BTFSS       STATUS,C
        GOTO        STATE4          ; Move to STATE4
        
STAY_STATE3:
        ; Check STOP button (RB1)
        BANKSEL     PORTB
        BTFSS       PORTB,1
        GOTO        STATE0
        
        CALL        DELAY_600MS
        GOTO        STATE3

; STATE 4 - MAXIMUM RANGE, 495-1023
; ---------------------------------

STATE4:
        ; Start ADC conversion
        BANKSEL     ADCON0
        BSF         ADCON0,GO
        
WAIT_ADC4:
        BTFSC       ADCON0,GO
        GOTO        WAIT_ADC4
        
        ; Add acquisition delay
        CALL        DELAY_50MS
        
        ; Read result
        BANKSEL     ADRESH
        MOVF        ADRESH,W
        MOVWF       ADC_VALUE
        
        ; Set LED pattern: RB7 ON
        BANKSEL     PORTB
        MOVLW       b'00001111'     ; Clear LED bits
        ANDWF       PORTB,F
        MOVLW       b'10000000'     ; Set RB7
        IORWF       PORTB,F
        
        ; Display '4' on 7-segment
        BANKSEL     PORTD
        CALL        DISPLAY_4
        
        ; Check if ADC < 123 (below TH3)
        MOVF        ADC_VALUE,W
        SUBLW       .123
        BTFSC       STATUS,C
        GOTO        STATE3          ; Drop to STATE3
        
        ; Stay in STATE4
        ; Check STOP button (RB1)
        BANKSEL     PORTB
        BTFSS       PORTB,1
        GOTO        STATE0
        
        CALL        DELAY_600MS
        GOTO        STATE4


; 7 - SEGMENT DISPLAY
; ----------------------

DISPLAY_0:
        MOVLW       b'00111111'     ; Display '0'
        MOVWF       PORTD
        RETURN

DISPLAY_1:
        MOVLW       b'00000110'     ; Display '1'
        MOVWF       PORTD
        RETURN

DISPLAY_2:
        MOVLW       b'01011011'     ; Display '2'
        MOVWF       PORTD
        RETURN

DISPLAY_3:
        MOVLW       b'01001111'     ; Display '3'
        MOVWF       PORTD
        RETURN

DISPLAY_4:
        MOVLW       b'01100110'     ; Display '4'
        MOVWF       PORTD
        RETURN
	
; Delay subroutines
; -----------------
	DELAY_50MS:
	    MOVLW   .66			 ; 1 us
	    MOVWF   DELAY_COUNT1 ; 1 us
	    	
	DELAY_50_OUTER:
	    MOVLW   .250		 ; 1 us
	    MOVWF   DELAY_COUNT2 ; 1 us
	    
	DELAY_50_INNER:
	    DECFSZ  DELAY_COUNT2,F ; 2 us
	    GOTO    DELAY_50_INNER ; 1 us
	    
	    DECFSZ  DELAY_COUNT1,F ; 2 us
	    GOTO    DELAY_50_OUTER ; 1 us
	    RETURN
	
	DELAY_100MS:
	    MOVLW   .133			; 1 us
	    MOVWF   DELAY_COUNT1 	; 1 us
	    
	DELAY_100_OUTER:
	    MOVLW   .250
	    MOVWF   DELAY_COUNT2
	    
	DELAY_100_INNER:
	    DECFSZ  DELAY_COUNT2,F
	    GOTO    DELAY_100_INNER
	    
	    DECFSZ  DELAY_COUNT1,F
	    GOTO    DELAY_100_OUTER
	    RETURN
	
	DELAY_600MS:
	    MOVLW   .6
	    MOVWF   DELAY_COUNT3
	    
	DELAY_600_LOOP:
	    CALL    DELAY_100MS
	    DECFSZ  DELAY_COUNT3,F
	    GOTO    DELAY_600_LOOP
	    RETURN
	
	END;