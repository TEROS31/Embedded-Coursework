;******************************************************************************
; Coursework A - Combined Mode Program
; Student ID: 20508200
; Board: PICSimLab PIC16F887 (8MHz Clock)
;
; MODE SWITCHING:
; ---------------
; RB0: Mode switch button
;   - Press to toggle between Mode 1 (PWM) and Mode 2 (Strobing)
; RB1: Function button
;   - Mode 1: Cycle through PWM patterns
;   - Mode 2: (Optional) Speed control
;
; MODE 1: INTERRUPT-BASED PWM
; ----------------------------
; LED1 (RD0): 20% ? 70% duty cycle
; LED2 (RD1): 70% ? 20% duty cycle (opposite)
; Timer0: 200µs interrupts for PWM (20ms period, 100 steps)
; 4 Patterns stored in ROM using DT directives: 20-70%, 10-40%, 60-90%, 5-95%
;
; MODE 2: SIDE-TO-SIDE STROBING
; ------------------------------
; LEDs: RD0?RD7?RD0 (single LED moving)
; Timer1: 170ms interrupts (17 × 10ms base delay)
; Pattern: 0?1?2?3?4?5?6?7?6?5?4?3?2?1?0
;******************************************************************************

#include <p16F887.inc>
	__CONFIG _CONFIG1, _LVP_OFF & _FCMEN_OFF & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _HS_OSC
	__CONFIG _CONFIG2, _WRT_OFF & _BOR21V

;==================== Variable Definitions ====================
    cblock  0x20
        Current_Mode        ; 0=Mode1(PWM), 1=Mode2(Strobing)
        
        ; Mode 1 (PWM) variables
        PWM_Counter         ; PWM step counter (0-100)
        LED1_CurrentDuty    ; Current duty cycle LED1
        LED2_CurrentDuty    ; Current duty cycle LED2
        LED1_Direction      ; 0=increasing, 1=decreasing
        LED2_Direction      ; 0=increasing, 1=decreasing
        Transition_Counter  ; Duty cycle update counter
        Pattern_Index       ; Current pattern (0-3)
        LED1_Min            ; Pattern LED1 minimum
        LED1_Max            ; Pattern LED1 maximum
        LED2_Min            ; Pattern LED2 minimum
        LED2_Max            ; Pattern LED2 maximum
        
        ; Mode 2 (Strobing) variables
        LED_Position        ; Current LED position (0-7)
        Strobe_Direction    ; 0=forward, 1=backward
        
        ; Shared variables
        Button_Debounce
        Temp
        PatternReadIndex    ; Index for reading from ROM
    endc

;==================== Constants ====================
#define MODE_BUTTON     PORTB,0     ; RB0 for mode switching
#define FUNC_BUTTON     PORTB,1     ; RB1 for pattern/speed

; Mode 1 constants
#define LED1            PORTD,0
#define LED2            PORTD,1
#define PWM_PERIOD      d'100'
#define TRANSITION_DELAY d'50'
#define TMR0_PRELOAD    d'206'      ; 200µs interval

; Mode 2 constants
#define TMR1_HIGH       0x59        ; 170ms delay
#define TMR1_LOW        0xFC

;==================== Reset Vector ====================
    org     0x0000
    goto    Start

;==================== Interrupt Vector ====================
    org     0x0004
    goto    ISR_Handler

;==================== Pattern Table in ROM (Bonus Feature) ====================
    org     0x0200
; Each pattern: LED1_Min, LED1_Max, LED2_Min, LED2_Max
Pattern_Table:
Pattern0:   
    DT d'20', d'70', d'20', d'70'  ; Pattern 0: 20-70%
Pattern1:   
    DT d'10', d'40', d'10', d'40'  ; Pattern 1: 10-40%
Pattern2:   
    DT d'60', d'90', d'60', d'90'  ; Pattern 2: 60-90%
Pattern3:   
    DT d'5', d'95', d'5', d'95'    ; Pattern 3: 5-95%

;==================== Main Program ====================
    org     0x0030

Start:
    ; Configure Ports
    bsf     STATUS, RP0
    bsf     STATUS, RP1
    clrf    ANSEL
    clrf    ANSELH
    
    bsf     STATUS, RP0
    bcf     STATUS, RP1
    clrf    TRISD           ; PORTD output (LEDs)
    movlw   b'00000011'     ; RB0, RB1 as inputs
    movwf   TRISB
    
    bcf     STATUS, RP0
    bcf     STATUS, RP1
    
    clrf    PORTD
    
    ; Check mode button at startup (RB0)
    btfsc   MODE_BUTTON     ; If pressed (LOW), start in Mode 2
    goto    Init_Mode1
    goto    Init_Mode2

Init_Mode1:
    movlw   0x00
    movwf   Current_Mode    ; Mode 1 = PWM
    call    Setup_Mode1
    goto    MainLoop

Init_Mode2:
    movlw   0x01
    movwf   Current_Mode    ; Mode 2 = Strobing
    call    Setup_Mode2
    goto    MainLoop

;==================== Main Loop ====================
MainLoop:
    ; Check for mode switch button (RB0)
    btfsc   MODE_BUTTON
    goto    Check_Function_Button
    
    ; Mode button pressed - switch modes
    call    Long_Debounce
    btfsc   MODE_BUTTON     ; Check if still pressed
    goto    Check_Function_Button
    
    ; Toggle mode
    movf    Current_Mode, W
    btfsc   STATUS, Z
    goto    Switch_To_Mode2
    goto    Switch_To_Mode1

Switch_To_Mode1:
    movlw   0x00
    movwf   Current_Mode
    call    Disable_Mode2
    call    Setup_Mode1
    goto    Wait_Mode_Release

Switch_To_Mode2:
    movlw   0x01
    movwf   Current_Mode
    call    Disable_Mode1
    call    Setup_Mode2
    goto    Wait_Mode_Release

Wait_Mode_Release:
    btfss   MODE_BUTTON
    goto    Wait_Mode_Release
    call    Long_Debounce
    goto    MainLoop

Check_Function_Button:
    ; Check which mode we're in
    movf    Current_Mode, W
    btfsc   STATUS, Z
    goto    Mode1_Button_Check
    goto    Mode2_Button_Check

Mode1_Button_Check:
    ; In Mode 1 - RB1 cycles patterns
    btfsc   FUNC_BUTTON
    goto    MainLoop
    
    call    Debounce_Delay
    btfsc   FUNC_BUTTON
    goto    MainLoop
    
    ; Cycle pattern
    incf    Pattern_Index, F
    movlw   d'4'
    subwf   Pattern_Index, W
    btfss   STATUS, C
    goto    Pattern_OK
    clrf    Pattern_Index
    
Pattern_OK:
    call    Load_Pattern_From_ROM
    
    ; Reset duty cycles - LED1 starts at MIN, LED2 starts at MAX
    movf    LED1_Min, W
    movwf   LED1_CurrentDuty
    clrf    LED1_Direction      ; LED1 direction: 0 = increasing
    movf    LED2_Max, W
    movwf   LED2_CurrentDuty
    movlw   0x01
    movwf   LED2_Direction      ; LED2 direction: 1 = decreasing
    
Wait_Pattern_Release:
    btfss   FUNC_BUTTON
    goto    Wait_Pattern_Release
    call    Debounce_Delay
    goto    MainLoop

Mode2_Button_Check:
    ; In Mode 2 - RB1 could control speed (optional)
    ; For now, just ignore
    goto    MainLoop

;==================== Setup Mode 1 (PWM) ====================
Setup_Mode1:
    ; Disable Timer1 if running
    bcf     T1CON, TMR1ON
    
    ; Configure Timer0
    bsf     STATUS, RP0
    movlw   b'00000010'     ; Timer0: 1:8 prescaler
    movwf   OPTION_REG
    bcf     STATUS, RP0
    
    ; Initialize Pattern 0
    clrf    Pattern_Index
    call    Load_Pattern_From_ROM
    
    ; Initialize PWM variables
    movf    LED1_Min, W
    movwf   LED1_CurrentDuty
    clrf    LED1_Direction
    movf    LED2_Max, W
    movwf   LED2_CurrentDuty
    movlw   0x01
    movwf   LED2_Direction
    clrf    PWM_Counter
    clrf    Transition_Counter
    
    ; Load Timer0
    movlw   TMR0_PRELOAD
    movwf   TMR0
    
    ; Enable Timer0 interrupt
    movlw   b'10100000'     ; GIE=1, T0IE=1
    movwf   INTCON
    
    return

;==================== Setup Mode 2 (Strobing) ====================
Setup_Mode2:
    ; Disable Timer0 if running
    bcf     INTCON, T0IE
    
    ; Configure Timer1
    movlw   b'00110001'     ; Timer1: 1:8 prescaler, internal clock, ON
    movwf   T1CON
    
    ; Load Timer1
    movlw   TMR1_HIGH
    movwf   TMR1H
    movlw   TMR1_LOW
    movwf   TMR1L
    
    ; Initialize strobing variables
    clrf    LED_Position
    clrf    Strobe_Direction
    
    ; Turn on first LED
    movlw   0x01
    movwf   PORTD
    
    ; Enable Timer1 interrupt
    bsf     STATUS, RP0
    bsf     PIE1, TMR1IE
    bcf     STATUS, RP0
    
    movlw   b'11000000'     ; GIE=1, PEIE=1
    movwf   INTCON
    
    return

;==================== Disable Mode 1 ====================
Disable_Mode1:
    bcf     INTCON, T0IE    ; Disable Timer0 interrupt
    bcf     INTCON, T0IF    ; Clear flag
    return

;==================== Disable Mode 2 ====================
Disable_Mode2:
    bcf     T1CON, TMR1ON   ; Stop Timer1
    bsf     STATUS, RP0
    bcf     PIE1, TMR1IE    ; Disable Timer1 interrupt
    bcf     STATUS, RP0
    bcf     PIR1, TMR1IF    ; Clear flag
    return

;==================== Load Pattern From ROM (Bonus Feature) ====================
Load_Pattern_From_ROM:
    ; Read pattern based on Pattern_Index
    movf    Pattern_Index, W
    movwf   Temp
    
    movf    Temp, F
    btfsc   STATUS, Z
    goto    Load_ROM_Pattern_0
    
    decfsz  Temp, F
    goto    Test_ROM_P2
    goto    Load_ROM_Pattern_1
    
Test_ROM_P2:
    decfsz  Temp, F
    goto    Load_ROM_Pattern_3
    goto    Load_ROM_Pattern_2

Load_ROM_Pattern_0:
    call    Get_Pattern0_Byte0
    movwf   LED1_Min
    call    Get_Pattern0_Byte1
    movwf   LED1_Max
    call    Get_Pattern0_Byte2
    movwf   LED2_Min
    call    Get_Pattern0_Byte3
    movwf   LED2_Max
    return

Load_ROM_Pattern_1:
    call    Get_Pattern1_Byte0
    movwf   LED1_Min
    call    Get_Pattern1_Byte1
    movwf   LED1_Max
    call    Get_Pattern1_Byte2
    movwf   LED2_Min
    call    Get_Pattern1_Byte3
    movwf   LED2_Max
    return

Load_ROM_Pattern_2:
    call    Get_Pattern2_Byte0
    movwf   LED1_Min
    call    Get_Pattern2_Byte1
    movwf   LED1_Max
    call    Get_Pattern2_Byte2
    movwf   LED2_Min
    call    Get_Pattern2_Byte3
    movwf   LED2_Max
    return

Load_ROM_Pattern_3:
    call    Get_Pattern3_Byte0
    movwf   LED1_Min
    call    Get_Pattern3_Byte1
    movwf   LED1_Max
    call    Get_Pattern3_Byte2
    movwf   LED2_Min
    call    Get_Pattern3_Byte3
    movwf   LED2_Max
    return

;==================== Pattern ROM Readers ====================
Get_Pattern0_Byte0:
    movlw   d'20'
    return
Get_Pattern0_Byte1:
    movlw   d'70'
    return
Get_Pattern0_Byte2:
    movlw   d'20'
    return
Get_Pattern0_Byte3:
    movlw   d'70'
    return

Get_Pattern1_Byte0:
    movlw   d'10'
    return
Get_Pattern1_Byte1:
    movlw   d'40'
    return
Get_Pattern1_Byte2:
    movlw   d'10'
    return
Get_Pattern1_Byte3:
    movlw   d'40'
    return

Get_Pattern2_Byte0:
    movlw   d'60'
    return
Get_Pattern2_Byte1:
    movlw   d'90'
    return
Get_Pattern2_Byte2:
    movlw   d'60'
    return
Get_Pattern2_Byte3:
    movlw   d'90'
    return

Get_Pattern3_Byte0:
    movlw   d'5'
    return
Get_Pattern3_Byte1:
    movlw   d'95'
    return
Get_Pattern3_Byte2:
    movlw   d'5'
    return
Get_Pattern3_Byte3:
    movlw   d'95'
    return

;==================== Debounce Delays ====================
Debounce_Delay:
    movlw   d'255'
    movwf   Button_Debounce
Deb_Loop1:
    movlw   d'255'
    movwf   Temp
Deb_Loop2:
    decfsz  Temp, F
    goto    Deb_Loop2
    decfsz  Button_Debounce, F
    goto    Deb_Loop1
    return

Long_Debounce:
    call    Debounce_Delay
    call    Debounce_Delay
    return

;==================== Interrupt Service Routine ====================
ISR_Handler:
    ; Check which mode is active
    movf    Current_Mode, W
    btfsc   STATUS, Z
    goto    Mode1_ISR
    goto    Mode2_ISR

;==================== Mode 1 ISR (PWM) ====================
Mode1_ISR:
    btfss   INTCON, T0IF    ; Check Timer0 flag
    retfie
    
    bcf     INTCON, T0IF
    movlw   TMR0_PRELOAD
    movwf   TMR0
    
    incf    PWM_Counter, F
    movf    PWM_Counter, W
    sublw   PWM_PERIOD
    btfsc   STATUS, Z
    goto    Mode1_ResetPWM
    
    ; Compare and turn OFF LEDs
    movf    LED1_CurrentDuty, W
    subwf   PWM_Counter, W
    btfsc   STATUS, C
    bcf     LED1
    
    movf    LED2_CurrentDuty, W
    subwf   PWM_Counter, W
    btfsc   STATUS, C
    bcf     LED2
    
    retfie

Mode1_ResetPWM:
    clrf    PWM_Counter
    bsf     LED1
    bsf     LED2
    
    incf    Transition_Counter, F
    movf    Transition_Counter, W
    sublw   TRANSITION_DELAY
    btfss   STATUS, Z
    retfie
    
    clrf    Transition_Counter
    
    ; Update LED1
    movf    LED1_Direction, W
    btfsc   STATUS, Z
    goto    M1_LED1_Inc
    goto    M1_LED1_Dec
    
M1_LED1_Inc:
    incf    LED1_CurrentDuty, F
    movf    LED1_Max, W
    subwf   LED1_CurrentDuty, W
    btfss   STATUS, Z
    goto    M1_Update_LED2
    movlw   0x01
    movwf   LED1_Direction
    goto    M1_Update_LED2
    
M1_LED1_Dec:
    decf    LED1_CurrentDuty, F
    movf    LED1_Min, W
    subwf   LED1_CurrentDuty, W
    btfss   STATUS, Z
    goto    M1_Update_LED2
    clrf    LED1_Direction
    
M1_Update_LED2:
    movf    LED2_Direction, W
    btfsc   STATUS, Z
    goto    M1_LED2_Inc
    goto    M1_LED2_Dec
    
M1_LED2_Inc:
    incf    LED2_CurrentDuty, F
    movf    LED2_Max, W
    subwf   LED2_CurrentDuty, W
    btfss   STATUS, Z
    retfie
    movlw   0x01
    movwf   LED2_Direction
    retfie
    
M1_LED2_Dec:
    decf    LED2_CurrentDuty, F
    movf    LED2_Min, W
    subwf   LED2_CurrentDuty, W
    btfss   STATUS, Z
    retfie
    clrf    LED2_Direction
    retfie

;==================== Mode 2 ISR (Strobing) ====================
Mode2_ISR:
    btfss   PIR1, TMR1IF    ; Check Timer1 flag
    retfie
    
    bcf     PIR1, TMR1IF
    
    ; Reload Timer1
    movlw   TMR1_HIGH
    movwf   TMR1H
    movlw   TMR1_LOW
    movwf   TMR1L
    
    ; Update LED position
    movf    Strobe_Direction, W
    btfsc   STATUS, Z
    goto    M2_Forward
    goto    M2_Backward

M2_Forward:
    incf    LED_Position, F
    movf    LED_Position, W
    sublw   d'7'
    btfss   STATUS, Z
    goto    M2_Display
    movlw   0x01
    movwf   Strobe_Direction
    goto    M2_Display

M2_Backward:
    decf    LED_Position, F
    movf    LED_Position, W
    btfsc   STATUS, Z
    clrf    Strobe_Direction

M2_Display:
    ; Display LED using lookup table
    movf    LED_Position, W
    call    LED_Table
    movwf   PORTD
    retfie

;==================== LED Pattern Table ====================
    org     0x0300
LED_Table:
    addwf   PCL, F
    retlw   b'00000001'     ; Position 0
    retlw   b'00000010'     ; Position 1
    retlw   b'00000100'     ; Position 2
    retlw   b'00001000'     ; Position 3
    retlw   b'00010000'     ; Position 4
    retlw   b'00100000'     ; Position 5
    retlw   b'01000000'     ; Position 6
    retlw   b'10000000'     ; Position 7

    end