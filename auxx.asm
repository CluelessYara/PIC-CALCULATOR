;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   Project:   Complex Calculator - Final Fixed Auxiliary Processor
;   File:   auxiliary.asm
;   Date:   2025-07-04
;   -----------------------------------
;   Authors:   Sara Ewaida 1203048
;              Yara Obaid 121248
;   -----------------------------------
;   Final auxiliary processor with proper communication and division
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    PROCESSOR 16F877A
    INCLUDE "P16F877A.INC"
    
    __CONFIG 0x3731

; Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
num1_int            EQU 0x20    ; 6 bytes for number 1 integer part
num1_dec            EQU 0x26    ; 6 bytes for number 1 decimal part
num2_int            EQU 0x2C    ; 6 bytes for number 2 integer part
num2_dec            EQU 0x32    ; 6 bytes for number 2 decimal part
result_int          EQU 0x38    ; 6 bytes for result integer part
result_dec          EQU 0x3E    ; 6 bytes for result decimal part

; Working variables
dividend_high       EQU 0x44
dividend_low        EQU 0x45
divisor_high        EQU 0x46
divisor_low         EQU 0x47
quotient_high       EQU 0x48
quotient_low        EQU 0x49
remainder_high      EQU 0x4A
remainder_low       EQU 0x4B

temp_counter        EQU 0x50
temp_var1           EQU 0x51
temp_var2           EQU 0x52
comm_state          EQU 0x53
bytes_received      EQU 0x54
bytes_to_receive    EQU 0x55
delay_counter       EQU 0x56

; Program Start ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ORG 0x00
    NOP
    GOTO    init
    
; Interrupt Vector ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ORG 0x04
    NOP
    RETFIE

; Include LCD functions (even though auxiliary doesn't use LCD, for xms function)
    INCLUDE "LCDIS.INC"

; Initialize ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
init:
    ; Configure PORTC for communication
    BANKSEL TRISC
    MOVLW   0xFF
    MOVWF   TRISC               ; Start as input
    
    BANKSEL PORTC
    MOVLW   0xFF
    MOVWF   PORTC
    
    CALL    clear_all_variables
    
    BANKSEL comm_state
    CLRF    comm_state          ; Start in wait state
    
    GOTO    main_loop

; Clear Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
clear_all_variables:
    BANKSEL num1_int            ; Ensure we're in the right bank
    MOVLW   0x20
    MOVWF   FSR
clear_vars_loop:
    CLRF    INDF
    INCF    FSR, F
    MOVLW   0x57                ; Clear up to 0x56
    SUBWF   FSR, W
    BTFSS   STATUS, Z
    GOTO    clear_vars_loop
    RETURN

; Main Loop ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main_loop:
    BANKSEL comm_state
    MOVF    comm_state, W
    BTFSC   STATUS, Z
    GOTO    wait_for_master
    
    SUBLW   0x01
    BTFSC   STATUS, Z
    GOTO    receive_data_state
    
    BANKSEL comm_state
    MOVF    comm_state, W
    SUBLW   0x02
    BTFSC   STATUS, Z
    GOTO    process_division
    
    SUBLW   0x03
    BTFSC   STATUS, Z
    GOTO    send_result_state
    
    GOTO    main_loop

; Wait for Master ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
wait_for_master:
    BANKSEL PORTC
    MOVF    PORTC, W
    SUBLW   0xFF                ; Check if still idle
    BTFSC   STATUS, Z
    GOTO    main_loop
    
    ; Master sent byte count
    MOVF    PORTC, W
    BANKSEL bytes_to_receive
    MOVWF   bytes_to_receive
    
    CALL    send_acknowledgment
    
    BANKSEL comm_state
    MOVLW   0x01
    MOVWF   comm_state
    BANKSEL bytes_received
    CLRF    bytes_received
    
    GOTO    main_loop

; Receive Data ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
receive_data_state:
    CALL    wait_for_data_byte
    
    ; Store received byte
    BANKSEL bytes_received
    MOVF    bytes_received, W
    ADDLW   num1_int
    MOVWF   FSR
    
    BANKSEL PORTC
    MOVF    PORTC, W
    MOVWF   INDF
    
    CALL    send_acknowledgment
    
    BANKSEL bytes_received
    INCF    bytes_received, F
    MOVF    bytes_received, W
    SUBWF   bytes_to_receive, W
    BTFSS   STATUS, Z
    GOTO    main_loop
    
    ; All data received, proceed to calculation
    MOVLW   0x02
    MOVWF   comm_state
    GOTO    main_loop

; Process Division ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
process_division:
    CALL    convert_numbers_to_binary
    CALL    check_division_by_zero
    BTFSC   STATUS, Z
    GOTO    division_by_zero_error
    
    CALL    perform_division
    CALL    convert_result_to_bcd
    
    BANKSEL comm_state
    MOVLW   0x03
    MOVWF   comm_state
    CLRF    bytes_received
    
    GOTO    main_loop

; Send Result ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
send_result_state:
    ; Set PORTC as output
    BANKSEL TRISC
    CLRF    TRISC
    
    ; Send result byte
    BANKSEL bytes_received
    MOVF    bytes_received, W
    ADDLW   result_int
    MOVWF   FSR
    
    BANKSEL PORTC
    MOVF    INDF, W
    MOVWF   PORTC
    
    CALL    wait_for_master_ack
    
    ; Set PORTC back to input
    BANKSEL TRISC
    MOVLW   0xFF
    MOVWF   TRISC
    
    BANKSEL bytes_received
    INCF    bytes_received, F
    MOVLW   0x0C                ; 12 bytes total result
    SUBWF   bytes_received, W
    BTFSS   STATUS, Z
    GOTO    main_loop
    
    ; All result sent, go back to waiting
    BANKSEL comm_state
    CLRF    comm_state
    GOTO    main_loop

; Communication Helper Functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
send_acknowledgment:
    BANKSEL TRISC
    CLRF    TRISC               ; Set as output
    
    BANKSEL PORTC
    MOVLW   0xAA                ; ACK signal
    MOVWF   PORTC
    
    MOVLW   D'10'               ; Short delay
    CALL    delay_ms
    
    BANKSEL TRISC
    MOVLW   0xFF                ; Back to input
    MOVWF   TRISC
    
    BANKSEL PORTC
    MOVLW   0xFF
    MOVWF   PORTC
    RETURN

wait_for_data_byte:
    BANKSEL PORTC
wait_data_loop:
    MOVF    PORTC, W
    SUBLW   0xFF                ; Wait for non-idle state
    BTFSC   STATUS, Z
    GOTO    wait_data_loop
    
    SUBLW   0x55                ; Skip ACK signals (0xFF - 0xAA = 0x55)
    BTFSC   STATUS, Z
    GOTO    wait_data_loop
    
    RETURN

wait_for_master_ack:
    MOVLW   D'20'               ; Wait for master to read
    CALL    delay_ms
    RETURN

; Simple delay function ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
delay_ms:
    MOVWF   delay_counter
delay_ms_loop:
    MOVLW   D'250'              ; Approximately 1ms at 4MHz
    MOVWF   temp_counter
delay_inner:
    DECFSZ  temp_counter, F
    GOTO    delay_inner
    DECFSZ  delay_counter, F
    GOTO    delay_ms_loop
    RETURN

; Number Conversion Functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
convert_numbers_to_binary:
    CALL    convert_num1_to_binary
    CALL    convert_num2_to_binary
    RETURN

convert_num1_to_binary:
    ; Convert first digit of num1 to binary
    BANKSEL num1_int
    MOVF    num1_int, W
    MOVWF   dividend_high
    CLRF    dividend_low
    RETURN

convert_num2_to_binary:
    ; Convert first digit of num2 to binary
    BANKSEL num2_int
    MOVF    num2_int, W
    MOVWF   divisor_high
    CLRF    divisor_low
    RETURN

check_division_by_zero:
    BANKSEL divisor_high
    MOVF    divisor_high, W
    IORWF   divisor_low, W
    RETURN

division_by_zero_error:
    ; Fill result with error code (9's)
    BANKSEL result_int
    MOVLW   result_int
    MOVWF   FSR
    MOVLW   0x09
    MOVWF   temp_var1
    
    MOVLW   0x0C
    MOVWF   temp_counter
    
error_fill_loop:
    MOVF    temp_var1, W
    MOVWF   INDF
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    error_fill_loop
    
    BANKSEL comm_state
    MOVLW   0x03
    MOVWF   comm_state
    CLRF    bytes_received
    RETURN

; Division Algorithm ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
perform_division:
    CLRF    quotient_high
    CLRF    quotient_low
    CLRF    remainder_high
    CLRF    remainder_low
    
    ; Simple division algorithm
    BANKSEL dividend_high
    MOVF    dividend_high, W
    MOVWF   temp_var1
    
    BANKSEL divisor_high
    MOVF    divisor_high, W
    MOVWF   temp_var2
    
    ; Check for zero divisor
    BTFSC   STATUS, Z
    RETURN
    
    CLRF    quotient_high
    
division_loop:
    ; Check if dividend >= divisor
    MOVF    temp_var2, W
    SUBWF   temp_var1, W
    BTFSS   STATUS, C
    GOTO    division_done
    
    ; Subtract divisor from dividend
    MOVF    temp_var2, W
    SUBWF   temp_var1, F
    
    ; Increment quotient
    INCF    quotient_high, F
    
    ; Safety check - prevent infinite loop
    BANKSEL quotient_high
    MOVF    quotient_high, W
    SUBLW   0x09                ; Max result is 9
    BTFSS   STATUS, C
    GOTO    division_done
    
    GOTO    division_loop

division_done:
    ; Store remainder
    BANKSEL temp_var1
    MOVF    temp_var1, W
    MOVWF   remainder_high
    RETURN

; Result Conversion ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
convert_result_to_bcd:
    ; Clear result storage
    BANKSEL result_int
    MOVLW   result_int
    MOVWF   FSR
    
    MOVLW   0x0C
    MOVWF   temp_counter
    
clear_result_loop:
    CLRF    INDF
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    clear_result_loop
    
    ; Store quotient in first position
    BANKSEL result_int
    MOVLW   result_int
    MOVWF   FSR
    
    BANKSEL quotient_high
    MOVF    quotient_high, W
    MOVWF   INDF
    
    ; Calculate decimal part from remainder
    INCF    FSR, F
    INCF    FSR, F
    INCF    FSR, F
    INCF    FSR, F
    INCF    FSR, F
    INCF    FSR, F              ; Point to decimal part
    INCF    FSR, F              ; First decimal position
    
    ; Software multiply remainder by 10
    BANKSEL remainder_high
    MOVF    remainder_high, W
    MOVWF   temp_var1
    
    ; Multiply by 10 using shift and add: x*10 = x*8 + x*2
    BCF     STATUS, C
    RLF     temp_var1, F        ; * 2
    MOVF    temp_var1, W        ; Save *2
    MOVWF   temp_var2
    RLF     temp_var1, F        ; * 4
    RLF     temp_var1, F        ; * 8
    
    ; Add *2 to *8 to get *10
    MOVF    temp_var2, W
    ADDWF   temp_var1, F
    
    ; Divide by divisor for first decimal place
    BANKSEL divisor_high
    MOVF    divisor_high, W
    MOVWF   temp_var2
    
    BANKSEL temp_counter
    CLRF    temp_counter
decimal_div_loop:
    BANKSEL temp_var2
    MOVF    temp_var2, W
    SUBWF   temp_var1, W
    BTFSS   STATUS, C
    GOTO    store_decimal
    
    MOVF    temp_var2, W
    SUBWF   temp_var1, F
    BANKSEL temp_counter
    INCF    temp_counter, F
    
    MOVF    temp_counter, W
    SUBLW   0x09
    BTFSS   STATUS, C
    GOTO    store_decimal
    
    GOTO    decimal_div_loop

store_decimal:
    BANKSEL temp_counter
    MOVF    temp_counter, W
    MOVWF   INDF
    
    RETURN

    END