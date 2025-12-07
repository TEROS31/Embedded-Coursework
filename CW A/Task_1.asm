;******************************************************************************
; Coursework A - Fixed Mode 2 (D0/D1 Only)
; Student ID: 20508200
; Board: PICSimLab PIC16F887 (8MHz Clock)
;******************************************************************************

#include <p16F887.inc>
    __CONFIG _CONFIG1, _LVP_OFF & _FCMEN_OFF & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _HS_OSC
    __CONFIG _CONFIG2, _WRT_OFF & _BOR21V

;==================== Shared Memory ====================
    cblock 0x70
        w_temp 
        status_temp
        pclath_temp
    endc

;==================== User Variables ====================
    cblock  0x20
        Current_Mode        ; 0=Mode1, 1=Mode2
        PWM_Counter
        LED1_CurrentDuty
        LED2_CurrentDuty
        LED1_Direction
        LED2_Direction
        Transition_Counter
        Pattern_Index
        LED1_Min
        LED1_Max
        LED2_Min
        LED2_Max
        Button_Debounce
        Temp
    endc

;==================== Constants ====================
#define MODE_BUTTON     PORTB,0     ; RB0: Switch Modes
#define FUNC_BUTTON     PORTB,1     ; RB1: Change Pattern (Mode 1 only)
#define LED1            PORTD,0
#define LED2            PORTD,1

#define PWM_PERIOD      d'100'
#define TRANSITION_DELAY d'50'
#define TMR0_PRELOAD    d'206'
; Timer 1 Speed for Mode 2 Strobe
#define TMR1_HIGH       0x0B        ; Slower speed for visible strobe
#define TMR1_LOW        0xDC

;==================== Vectors ====================
    org     0x0000
    goto    Start

    org     0x0004
    goto    ISR_Handler

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
    clrf    TRISD           ; PORTD as Output
    movlw   b'00000011'     ; RB0, RB1 as Input
    movwf   TRISB
    
    bcf     STATUS, RP0
    bcf     STATUS, RP1
    clrf    PORTD
    
    ; Initial Mode Check
    btfsc   MODE_BUTTON
    goto    Init_Mode1
    goto    Init_Mode2

Init_Mode1:
    movlw   0x00
    movwf   Current_Mode
    call    Setup_Mode1
    goto    MainLoop

Init_Mode2:
    movlw   0x01
    movwf   Current_Mode
    call    Setup_Mode2
    goto    MainLoop

MainLoop:
    ; Check Mode Switch Button (RB0)
    btfsc   MODE_BUTTON
    goto    Check_Function_Button
    
    call    Long_Debounce
    btfsc   MODE_BUTTON
    goto    Check_Function_Button
    
    ; Switch Mode Logic
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
    ; Check Function Button (RB1) - Only Active in Mode 1
    movf    Current_Mode, W
    btfss   STATUS, Z   ; If Mode 1 (0), Skip. If Mode 2 (1), goto Loop
    goto    MainLoop

    ; Mode 1 Button Logic
    btfsc   FUNC_BUTTON
    goto    MainLoop
    call    Debounce_Delay
    btfsc   FUNC_BUTTON
    goto    MainLoop
    
    ; Cycle Pattern
    incf    Pattern_Index, F
    movlw   d'4'
    subwf   Pattern_Index, W
    btfss   STATUS, C
    goto    Pattern_OK
    clrf    Pattern_Index
    
Pattern_OK:
    call    Load_Pattern_From_ROM
    movf    LED1_Min, W
    movwf   LED1_CurrentDuty
    clrf    LED1_Direction
    movf    LED2_Max, W
    movwf   LED2_CurrentDuty
    movlw   0x01
    movwf   LED2_Direction
    
Wait_Pattern_Release:
    btfss   FUNC_BUTTON
    goto    Wait_Pattern_Release
    call    Debounce_Delay
    goto    MainLoop

;==================== ISR Handler ====================
ISR_Handler:
    ; 1. Context Save
    movwf   w_temp
    swapf   STATUS, W
    movwf   status_temp
    movf    PCLATH, W
    movwf   pclath_temp
    
    ; 2. Safety
    bcf     STATUS, RP0
    bcf     STATUS, RP1
    clrf    PCLATH

    ; 3. ISR Logic
    movf    Current_Mode, W
    btfsc   STATUS, Z
    goto    Mode1_ISR
    goto    Mode2_ISR

; ---------------- MODE 1: PWM ----------------
Mode1_ISR:
    btfss   INTCON, T0IF
    goto    ISR_Exit
    bcf     INTCON, T0IF
    movlw   TMR0_PRELOAD
    movwf   TMR0
    
    incf    PWM_Counter, F
    movf    PWM_Counter, W
    sublw   PWM_PERIOD
    btfsc   STATUS, Z
    goto    Mode1_ResetPWM
    
    movf    LED1_CurrentDuty, W
    subwf   PWM_Counter, W
    btfsc   STATUS, C
    bcf     LED1
    movf    LED2_CurrentDuty, W
    subwf   PWM_Counter, W
    btfsc   STATUS, C
    bcf     LED2
    goto    ISR_Exit

Mode1_ResetPWM:
    clrf    PWM_Counter
    bsf     LED1
    bsf     LED2
    incf    Transition_Counter, F
    movf    Transition_Counter, W
    sublw   TRANSITION_DELAY
    btfss   STATUS, Z
    goto    ISR_Exit
    clrf    Transition_Counter
    
    ; LED Update Logic (Fading)
    movf    LED1_Direction, W
    btfsc   STATUS, Z
    goto    M1_LED1_Inc
    decf    LED1_CurrentDuty, F
    movf    LED1_Min, W
    subwf   LED1_CurrentDuty, W
    btfss   STATUS, Z
    goto    M1_Update_LED2
    clrf    LED1_Direction
    goto    M1_Update_LED2
M1_LED1_Inc:
    incf    LED1_CurrentDuty, F
    movf    LED1_Max, W
    subwf   LED1_CurrentDuty, W
    btfss   STATUS, Z
    goto    M1_Update_LED2
    movlw   0x01
    movwf   LED1_Direction

M1_Update_LED2:
    movf    LED2_Direction, W
    btfsc   STATUS, Z
    goto    M1_LED2_Inc
    decf    LED2_CurrentDuty, F
    movf    LED2_Min, W
    subwf   LED2_CurrentDuty, W
    btfss   STATUS, Z
    goto    ISR_Exit
    clrf    LED2_Direction
    goto    ISR_Exit
M1_LED2_Inc:
    incf    LED2_CurrentDuty, F
    movf    LED2_Max, W
    subwf   LED2_CurrentDuty, W
    btfss   STATUS, Z
    goto    ISR_Exit
    movlw   0x01
    movwf   LED2_Direction
    goto    ISR_Exit

; ---------------- MODE 2: STROBE (D0 <-> D1) ----------------
Mode2_ISR:
    btfss   PIR1, TMR1IF
    goto    ISR_Exit
    bcf     PIR1, TMR1IF
    movlw   TMR1_HIGH
    movwf   TMR1H
    movlw   TMR1_LOW
    movwf   TMR1L
    
    ; STRICT TOGGLE LOGIC:
    ; Check if D0 is currently ON.
    btfsc   PORTD, 0
    goto    Turn_On_D1
    goto    Turn_On_D0

Turn_On_D0:
    movlw   b'00000001'     ; Only D0 ON, Force D3 OFF
    movwf   PORTD
    goto    ISR_Exit

Turn_On_D1:
    movlw   b'00000010'     ; Only D1 ON, Force D3 OFF
    movwf   PORTD
    goto    ISR_Exit

ISR_Exit:
    movf    pclath_temp, W
    movwf   PCLATH
    swapf   status_temp, W
    movwf   STATUS
    swapf   w_temp, F
    swapf   w_temp, W
    retfie

;==================== Setup Subroutines ====================
Setup_Mode1:
    bcf     T1CON, TMR1ON   ; Stop Timer1
    clrf    PORTD           ; Clear ghosting
    
    bsf     STATUS, RP0
    movlw   b'00000010'
    movwf   OPTION_REG
    bcf     STATUS, RP0
    clrf    Pattern_Index
    call    Load_Pattern_From_ROM
    movf    LED1_Min, W
    movwf   LED1_CurrentDuty
    clrf    LED1_Direction
    movf    LED2_Max, W
    movwf   LED2_CurrentDuty
    movlw   0x01
    movwf   LED2_Direction
    clrf    PWM_Counter
    clrf    Transition_Counter
    movlw   TMR0_PRELOAD
    movwf   TMR0
    movlw   b'10100000'
    movwf   INTCON
    return

Setup_Mode2:
    bcf     INTCON, T0IE    ; Stop Timer0
    clrf    PORTD           ; Wipe LEDs
    
    movlw   b'00110001'     ; Timer 1 Prescaler 1:8
    movwf   T1CON
    movlw   TMR1_HIGH
    movwf   TMR1H
    movlw   TMR1_LOW
    movwf   TMR1L
    
    movlw   b'00000001'     ; Start with D0 ON
    movwf   PORTD
    
    bsf     STATUS, RP0
    bsf     PIE1, TMR1IE
    bcf     STATUS, RP0
    movlw   b'11000000'     ; GIE + PEIE
    movwf   INTCON
    return

Disable_Mode1:
    bcf     INTCON, T0IE
    bcf     INTCON, T0IF
    return

Disable_Mode2:
    bcf     T1CON, TMR1ON
    bsf     STATUS, RP0
    bcf     PIE1, TMR1IE
    bcf     STATUS, RP0
    bcf     PIR1, TMR1IF
    return

;==================== ROM Patterns & Delays ====================
; (Pattern Data is unchanged from previous working version)
Load_Pattern_From_ROM:
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

Get_Pattern0_Byte0: movlw d'20'
    return
Get_Pattern0_Byte1: movlw d'70'
    return
Get_Pattern0_Byte2: movlw d'20'
    return
Get_Pattern0_Byte3: movlw d'70'
    return
Get_Pattern1_Byte0: movlw d'10'
    return
Get_Pattern1_Byte1: movlw d'40'
    return
Get_Pattern1_Byte2: movlw d'10'
    return
Get_Pattern1_Byte3: movlw d'40'
    return
Get_Pattern2_Byte0: movlw d'60'
    return
Get_Pattern2_Byte1: movlw d'90'
    return
Get_Pattern2_Byte2: movlw d'60'
    return
Get_Pattern2_Byte3: movlw d'90'
    return
Get_Pattern3_Byte0: movlw d'5'
    return
Get_Pattern3_Byte1: movlw d'95'
    return
Get_Pattern3_Byte2: movlw d'5'
    return
Get_Pattern3_Byte3: movlw d'95'
    return

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

    end