;  Data

;  InputData  = 0x55 (01010101)(85)
;  Mask1   = 0xAA (10101010)(170)
;  Stage1Result = 0xFF (11111111)(255)



        LIST    P=16F887
        #include <P16F887.inc>
		
		; Address
        CBLOCK 0x20
		
		; Stage 1
        InputData ; 0x20 
        Mask1 ; 0x21
        Stage1Result ; 0x22
		
		; Stage 2
		Temp ; 0x23
		BitCount ; 0x24
		Stage2Result ; 0x25
		LoopCount ; 0x26

		; Stage 3
		Mask2 ; 0x27  
		Stage3Result ; 0x28     

		; Stage 4
		Mask3 ; 0x29
		Stage4Result ;0x2A
		
        ENDC

        ORG 0x0000

main:

; Stage 1

        BSF STATUS, RP0 ; use bank1 for functions
        CLRF TRISD		; ALL PORTD pins output
        BCF STATUS, RP0 ; go back bank0 for normal data operations

        MOVLW 0x55 		; 0x55 to w
        MOVWF InputData ; w -- inputData
        MOVLW 0xAA		; 0xAA -- w
        MOVWF Mask1		; w -- Mask1 

        MOVFW InputData	; inputData -- w
        XORWF Mask1, W ; xor w with fileReg (Mask1 and inputdata), then store to w
        MOVWF Stage1Result ; w -- stage1result (1111 1111 = 255)

; Stage 2

; Key1 = 5 (0101)

; a) Count number of 1 bits
; b) Determine even or odd count
		
		MOVFW Stage1Result ; Stage1Result -- w 
		MOVWF Temp ; w -- Temp 	(255)
		CLRF BitCount
		MOVLW D'8'      
		MOVWF LoopCount

		CountFunction:
			BTFSC Temp, 0 ; Start from 0 (LSB) of temp, if 0 then skip next line
			INCF  BitCount, F ; Add 1 store back to bitcount (bitcount = 8)
			RRF Temp, F ; Shift all bits in lsb of temp by 1 into carry flag, then carry flag pushes in from msb
			DECFSZ LoopCount, F ; from 8 keep decrement by 1
			GOTO CountFunction
			
		BTFSC BitCount, 0 ; Check if the lsb is 0, if yes then skip nxt
		GOTO  OddNum
				
		EvenNum:
			MOVLW D'5'
			MOVWF Temp
		RotateLeft:
			RLF Stage1Result, F
			DECFSZ Temp, F
			GOTO RotateLeft
			GOTO StoreResult

		OddNum:
			MOVLW D'5'
			MOVWF Temp
		RotateRight:
			RRF Stage1Result, F
			DECFSZ Temp, F
			GOTO RotateRight

		StoreResult:
			MOVFW Stage1Result
			MOVWF Stage2Result
			MOVFW Stage2Result

Stage3:
	MOVLW B'00001111'  
	MOVWF Mask2 ; Store to Mask2
	MOVFW Stage2Result;
	XORWF Mask2, w
	MOVWF Stage3Result; 1111 0000 = 240
	
Stage4:
; Key 2 = 255 - (31 + 8) = 216 (1101 1000)
	MOVLW B'11011000'
	MOVWF Mask3 ; Store to Mask3
	MOVFW Stage3Result;
	XORWF Mask3, w
	MOVWF Stage4Result ; (00101000) 40 decimal



		HOLD:
			GOTO HOLD
		

        END
