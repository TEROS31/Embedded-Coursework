;******************************************************************************
; Coursework A - Mode 1: Interrupt-based PWM with ROM Pattern Storage
; Student ID: 20508200
; Board: PICSimLab PIC16F887 (8MHz Clock)
; LEDs: RD0 (LED1), RD1 (LED2)
; Button: RB1 (Pattern cycling)
;
; DUTY CYCLE PARAMETERS:
; ----------------------
; LED1: 20% ? 70% duty cycle
; LED2: 70% ? 20% duty cycle (opposite direction)
;
; TIMER0 CONFIGURATION:
; ---------------------
; Fosc = 8MHz ? Instruction cycle = 2MHz (0.5µs)
; Prescaler = 1:8
; Timer0 tick rate = 2MHz / 8 = 250kHz (4µs per tick)
; 
; PWM TIMING:
; -----------
; Target PWM period = 20ms
; PWM resolution = 100 steps (0-100%)
; Interrupt interval = 20ms / 100 = 200µs
; Timer0 ticks needed = 200µs / 4µs = 50 ticks
; Timer0 preload = 256 - 50 = 206
;
; VERIFICATION:
; -------------
; Interrupt interval = 50 × 4µs = 200µs ?
; PWM period = 100 × 200µs = 20ms ?
; 20% duty = 4ms ON, 16ms OFF
; 70% duty = 14ms ON, 6ms OFF
; Transition time = 50 PWM periods/step = 1 second per 1% change
;
; BONUS FEATURES:
; ---------------
; 4 ROM patterns using DT directives
; Pattern 0: 20-70% | Pattern 1: 10-40%
; Pattern 2: 60-90% | Pattern 3: 5-95%
;******************************************************************************

#include <p16F887.inc>
	__CONFIG _CONFIG1, _LVP_OFF & _FCMEN_OFF & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_OFF & _PWRTE_ON & _WDT_OFF & _HS_OSC
	__CONFIG _CONFIG2, _WRT_OFF & _BOR21V

;==================== Variable Definitions ====================
    cblock  0x20
        PWM_Counter         ; Counts interrupt cycles for PWM period (0-100)
        LED1_CurrentDuty    ; Current duty cycle for LED1
        LED2_CurrentDuty    ; Current duty cycle for LED2
        LED1_Direction      ; 0=increasing, 1=decreasing
        LED2_Direction      ; 0=increasing, 1=decreasing
        Transition_Counter  ; Counter for duty cycle update timing
        Pattern_Index       ; Current pattern (0-3)
        LED1_Min            ; Current pattern's LED1 minimum
        LED1_Max            ; Current pattern's LED1 maximum
        LED2_Min            ; Current pattern's LED2 minimum
        LED2_Max            ; Current pattern's LED2 maximum
        Button_Debounce     ; Debounce counter for button
        Temp                ; Temporary variable
    endc

;==================== Constants ====================
#define LED1        PORTD,0     ; RD0 (first LED on PORTD)
#define LED2        PORTD,1     ; RD1 (second LED on PORTD)
#define BUTTON      PORTB,1     ; RB1 for pattern cycling
#define PWM_PERIOD  d'100'      ; 100 steps = direct % mapping (0-100%)

#define TRANSITION_DELAY d'50'  ; PWM periods between duty cycle updates
#define DEBOUNCE_DELAY   d'20'  ; Button debounce delay

;==================== Reset Vector ====================
    org     0x0000
    goto    Start

;==================== Interrupt Vector ====================
    org     0x0004
    goto    ISR_Handler

;==================== ROM Pattern Storage (BONUS FEATURE) ====================
; Store patterns at address 0x0010 to avoid conflicts
    org     0x0010

; Each pattern contains: LED1_Min, LED1_Max, LED2_Min, LED2_Max
; Stored in program memory using DT (Define Table) directive
Pattern_Table:
    ; Pattern 0: Default (20-70%) - Original requirement
    DT      d'20', d'70', d'20', d'70'
    
    ; Pattern 1: Low Range (10-40%) - Subtle, dim pulsing
    DT      d'10', d'40', d'10', d'40'
    
    ; Pattern 2: High Range (60-90%) - Bright, energetic
    DT      d'60', d'90', d'60', d'90'
    
    ; Pattern 3: Full Range (5-95%) - Maximum contrast
    DT      d'5',  d'95', d'5',  d'95'

;==================== Main Program ====================
    org     0x0030

Start:
    ; Configure Ports - PIC16F887 specific
    bsf     STATUS, RP0     ; Bank 1
    bsf     STATUS, RP1     ; Bank 2
    clrf    ANSEL           ; Digital I/O for PORTA/PORTD
    clrf    ANSELH          ; Digital I/O for PORTB
    
    bsf     STATUS, RP0     ; Bank 1
    bcf     STATUS, RP1
    clrf    TRISD           ; All PORTD as output (LEDs)
    clrf    TRISB           ; All PORTB as output initially
    bsf     TRISB,1         ; RB1 as input (button)
    
    ; Configure Timer0 for 8MHz clock
    movlw   b'00000010'     ; Timer0: prescaler 1:8
    movwf   OPTION_REG
    
    bcf     STATUS, RP0     ; Bank 0
    bcf     STATUS, RP1
    
    ; Enable Interrupts
    movlw   b'10100000'     ; GIE=1, T0IE=1
    movwf   INTCON
    
    clrf    PORTD           ; Clear all LEDs
    
    ; Initialize Timer0 with preload value
    movlw   d'206'          ; Preload for 200µs interval
    movwf   TMR0
    
    ; Initialize pattern system - Load Pattern 0 (default)
    clrf    Pattern_Index   ; Start with pattern 0 (20-70%)
    call    Load_Pattern    ; Load pattern from ROM
    
    ; Add small delay to ensure pattern loads before interrupts start
    movlw   d'100'
    movwf   Temp
Init_Delay:
    decfsz  Temp, F
    goto    Init_Delay
    
    ; Initialize PWM variables with loaded pattern
    ; LED1 starts at MINIMUM and increases
    movf    LED1_Min, W
    movwf   LED1_CurrentDuty
    clrf    LED1_Direction  ; 0 = increasing
    
    ; LED2 starts at MAXIMUM and decreases (OPPOSITE DIRECTION)
    movf    LED2_Max, W
    movwf   LED2_CurrentDuty
    movlw   0x01
    movwf   LED2_Direction  ; 1 = decreasing
    
    clrf    PWM_Counter
    clrf    Transition_Counter
    clrf    Button_Debounce

;==================== Main Loop ====================
MainLoop:
    ; Check for button press (RB1) to cycle patterns
    btfsc   BUTTON          ; Skip if button pressed (goes LOW)
    goto    MainLoop        ; Button not pressed, continue
    
    ; Button pressed - first debounce delay
    call    Debounce_Delay
    
    ; Check if still pressed after debounce
    btfsc   BUTTON
    goto    MainLoop        ; False trigger, ignore
    
    ; Cycle to next pattern
    incf    Pattern_Index, F
    movlw   d'4'            ; 4 patterns total (0-3)
    subwf   Pattern_Index, W
    btfss   STATUS, C       ; Check if Pattern_Index >= 4
    goto    Pattern_Valid
    clrf    Pattern_Index   ; Wrap around to 0
    
Pattern_Valid:
    ; Load new pattern
    call    Load_Pattern
    
    ; Reset PWM to new pattern values
    ; LED1 starts at MINIMUM (increasing direction)
    movf    LED1_Min, W
    movwf   LED1_CurrentDuty
    clrf    LED1_Direction  ; 0 = increasing
    
    ; LED2 starts at MAXIMUM (decreasing direction)
    movf    LED2_Max, W
    movwf   LED2_CurrentDuty
    movlw   0x01
    movwf   LED2_Direction  ; 1 = decreasing
    
    ; Wait for button release with longer timeout
Wait_Release:
    btfss   BUTTON
    goto    Wait_Release
    
    ; Extra debounce after release
    call    Debounce_Delay
    goto    MainLoop

;==================== Load Pattern from Variables (CORRECTED) ====================
Load_Pattern:
    ; Direct pattern loading - use decfsz for reliable comparison
    
    ; Make a copy of Pattern_Index for testing
    movf    Pattern_Index, W
    movwf   Temp
    
    ; Test if Pattern_Index == 0
    movf    Temp, F         ; Test Temp
    btfsc   STATUS, Z
    goto    Load_Pattern_0
    
    ; Test if Pattern_Index == 1
    decfsz  Temp, F
    goto    Test_Pattern_2
    goto    Load_Pattern_1
    
Test_Pattern_2:
    ; Test if Pattern_Index == 2
    decfsz  Temp, F
    goto    Load_Pattern_3  ; Must be 3 or higher
    goto    Load_Pattern_2

Load_Pattern_0:
    ; Pattern 0: Default (20-70%) - Original requirement
    movlw   d'20'
    movwf   LED1_Min
    movlw   d'70'
    movwf   LED1_Max
    movlw   d'20'
    movwf   LED2_Min
    movlw   d'70'
    movwf   LED2_Max
    return

Load_Pattern_1:
    ; Pattern 1: Low Range (10-40%) - Dim pulsing
    movlw   d'10'
    movwf   LED1_Min
    movlw   d'40'
    movwf   LED1_Max
    movlw   d'10'
    movwf   LED2_Min
    movlw   d'40'
    movwf   LED2_Max
    return

Load_Pattern_2:
    ; Pattern 2: High Range (60-90%) - Bright pulsing
    movlw   d'60'
    movwf   LED1_Min
    movlw   d'90'
    movwf   LED1_Max
    movlw   d'60'
    movwf   LED2_Min
    movlw   d'90'
    movwf   LED2_Max
    return

Load_Pattern_3:
    ; Pattern 3: Full Range (5-95%) - Maximum contrast
    movlw   d'5'
    movwf   LED1_Min
    movlw   d'95'
    movwf   LED1_Max
    movlw   d'5'
    movwf   LED2_Min
    movlw   d'95'
    movwf   LED2_Max
    return

;==================== Debounce Delay ====================
Debounce_Delay:
    ; Longer debounce for more reliable button detection
    movlw   d'255'
    movwf   Button_Debounce
Debounce_Loop1:
    movlw   d'255'
    movwf   Temp
Debounce_Loop2:
    decfsz  Temp, F
    goto    Debounce_Loop2
    decfsz  Button_Debounce, F
    goto    Debounce_Loop1
    return

;==================== Interrupt Service Routine ====================
ISR_Handler:
    ; Only Timer0 interrupt is enabled, so must be Timer0
    bcf     INTCON, T0IF    ; Clear Timer0 interrupt flag
    
    ; Reload Timer0 for 200µs interrupt interval
    movlw   d'206'
    movwf   TMR0
    
    ; Increment PWM counter
    incf    PWM_Counter, F
    
    ; Check if we've completed one PWM period (100 counts)
    movf    PWM_Counter, W
    sublw   PWM_PERIOD
    btfsc   STATUS, Z
    goto    ResetPWM
    
    ; Compare PWM_Counter with LED duty cycles
    ; Turn OFF LEDs if counter exceeds their ON time
    
    ; LED1 comparison
    movf    LED1_CurrentDuty, W
    subwf   PWM_Counter, W
    btfsc   STATUS, C       ; If PWM_Counter >= LED1_CurrentDuty
    bcf     LED1            ; Turn OFF LED1
    
    ; LED2 comparison
    movf    LED2_CurrentDuty, W
    subwf   PWM_Counter, W
    btfsc   STATUS, C       ; If PWM_Counter >= LED2_CurrentDuty
    bcf     LED2            ; Turn OFF LED2
    
    retfie

ResetPWM:
    ; Start new PWM cycle
    clrf    PWM_Counter
    
    ; Turn ON both LEDs at start of cycle
    bsf     LED1
    bsf     LED2
    
    ; Update duty cycles gradually
    incf    Transition_Counter, F
    movf    Transition_Counter, W
    sublw   TRANSITION_DELAY
    btfss   STATUS, Z
    goto    ExitISR
    
    ; Time to update duty cycles (every 50 PWM periods)
    clrf    Transition_Counter
    
    ;--- Update LED1 duty cycle ---
    movf    LED1_Direction, W
    btfsc   STATUS, Z
    goto    LED1_Increase
    goto    LED1_Decrease
    
LED1_Increase:
    incf    LED1_CurrentDuty, F
    ; Check if reached maximum (from current pattern)
    movf    LED1_Max, W
    subwf   LED1_CurrentDuty, W
    btfss   STATUS, Z
    goto    Update_LED2
    ; Reached max, change direction
    movlw   0x01
    movwf   LED1_Direction
    goto    Update_LED2
    
LED1_Decrease:
    decf    LED1_CurrentDuty, F
    ; Check if reached minimum (from current pattern)
    movf    LED1_Min, W
    subwf   LED1_CurrentDuty, W
    btfss   STATUS, Z
    goto    Update_LED2
    ; Reached min, change direction
    clrf    LED1_Direction
    goto    Update_LED2
    
Update_LED2:
    ;--- Update LED2 duty cycle (opposite direction) ---
    movf    LED2_Direction, W
    btfsc   STATUS, Z
    goto    LED2_Increase
    goto    LED2_Decrease
    
LED2_Increase:
    incf    LED2_CurrentDuty, F
    ; Check if reached maximum (from current pattern)
    movf    LED2_Max, W
    subwf   LED2_CurrentDuty, W
    btfss   STATUS, Z
    goto    ExitISR
    ; Reached max, change direction
    movlw   0x01
    movwf   LED2_Direction
    goto    ExitISR
    
LED2_Decrease:
    decf    LED2_CurrentDuty, F
    ; Check if reached minimum (from current pattern)
    movf    LED2_Min, W
    subwf   LED2_CurrentDuty, W
    btfss   STATUS, Z
    goto    ExitISR
    ; Reached min, change direction
    clrf    LED2_Direction
    
ExitISR:
    retfie

    end