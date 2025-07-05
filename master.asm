;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;   Project:   Division Calculator - 6 DIGITS PER PART
;   File:   master.asm
;   Date:   2025-07-04
;   -----------------------------------
;   Authors:   Sara Ewaida 1203048
;              Yara Obaid  1212482
;   -----------------------------------
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   	   
    PROCESSOR 16F877A
    INCLUDE "P16F877A.INC"
    
	__CONFIG 0x3731

; Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Core system variables
current_digit       EQU 0x20    ; Current digit being edited (0-9)
digit_pos           EQU 0x21    ; Position within current section (0-5 for 6 digits)
timeout_counter     EQU 0x22    ; Counter for 1-second timeout
state               EQU 0x23    ; System state
number_mode         EQU 0x24    ; 0=number1, 1=number2
input_mode          EQU 0x25    ; 0=integer part, 1=decimal part
result_mode         EQU 0x26    ; 0=result, 1=num1, 2=num2
display_offset      EQU 0x27    ; Offset for scrolling display

; Button handling
last_button         EQU 0x28    ; Last button state for debouncing
button_timer        EQU 0x29    ; Timer for double-click detection
click_count         EQU 0x2A    ; Number of clicks detected
auto_fill_flag      EQU 0x2B    ; Flag to prevent immediate auto-fill

; Working variables
temp_w              EQU 0x2C    ; Temporary W storage
temp_status         EQU 0x2D    ; Temporary STATUS storage
temp_var            EQU 0x2E    ; General purpose temp
temp_counter        EQU 0x2F    ; General purpose counter
cursor_pos          EQU 0x30    ; LCD cursor position

; Number storage - 12 digits each (6 integer + 6 decimal)
num1_int            EQU 0x31    ; Number 1 integer part (6 bytes)
num1_dec            EQU 0x37    ; Number 1 decimal part (6 bytes)
num2_int            EQU 0x3D    ; Number 2 integer part (6 bytes)
num2_dec            EQU 0x43    ; Number 2 decimal part (6 bytes)
result_int          EQU 0x49    ; Result integer part (6 bytes)
result_dec          EQU 0x4F    ; Result decimal part (6 bytes)

; Communication variables
comm_state          EQU 0x55    ; Communication state
bytes_sent          EQU 0x56    ; Bytes sent counter
section_complete    EQU 0x57    ; Section completion flag

; Program Start ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ORG	0x00
    GOTO    start

; Interrupt Vector ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ORG	0x04
interrupt_handler:
    ; Save context
    MOVWF   temp_w
    SWAPF   STATUS, W
    MOVWF   temp_status
    
    ; Check interrupt source
    BTFSC   INTCON, INTF
    GOTO    handle_button_interrupt
    
    BTFSC   INTCON, T0IF
    GOTO    handle_timer_interrupt
    
    GOTO    exit_interrupt

handle_button_interrupt:
    ; Button debouncing - minimal version
    BTFSC   PORTB, 0
    GOTO    clear_button_flag
    
    ; Valid button press - increment digit
    INCF    current_digit, F
    MOVLW   0x0A
    SUBWF   current_digit, W
    BTFSS   STATUS, Z
    GOTO    store_digit_simple
    CLRF    current_digit

store_digit_simple:
    ; Store digit in memory - bounds check
    MOVF    digit_pos, W
    SUBLW   0x05
    BTFSS   STATUS, C
    GOTO    clear_button_flag
    
    ; Calculate memory address
    MOVLW   num1_int
    BTFSC   number_mode, 0
    MOVLW   num2_int
    BTFSC   input_mode, 0
    ADDLW   0x06
    ADDWF   digit_pos, W
    MOVWF   FSR
    
    ; Store the digit
    MOVF    current_digit, W
    MOVWF   INDF
    
    ; Set flag for main loop to update display (don't do it in interrupt)
    MOVLW   0x01
    MOVWF   section_complete    ; Reuse this flag as update flag
    
    ; Reset timeout counter
    MOVLW   0x3C
    MOVWF   timeout_counter
    CLRF    auto_fill_flag

clear_button_flag:
    BCF     INTCON, INTF
    GOTO    exit_interrupt

handle_timer_interrupt:
    ; Decrement timeout counter
    MOVF    timeout_counter, F
    BTFSC   STATUS, Z
    GOTO    check_button_timer
    
    DECF    timeout_counter, F
    BTFSS   STATUS, Z
    GOTO    check_button_timer
    
    ; Timeout occurred - set auto-fill flag
    MOVLW   0x01
    MOVWF   auto_fill_flag

check_button_timer:
    ; Handle double-click timer
    MOVF    button_timer, F
    BTFSC   STATUS, Z
    GOTO    clear_timer_flag
    DECF    button_timer, F

clear_timer_flag:
    BCF     INTCON, T0IF

exit_interrupt:
    ; Restore context
    SWAPF   temp_status, W
    MOVWF   STATUS
    SWAPF   temp_w, F
    SWAPF   temp_w, W
    RETFIE

; Include LCD library
    INCLUDE "LCDIS.INC"

; Main Program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
start:
    ; Initialize hardware
    BANKSEL TRISB
    BSF     TRISB, 0            ; RB0 input for button
    CLRF    TRISD               ; PORTD output for LCD
    CLRF    TRISC               ; PORTC output for communication
    
    ; Switch to Bank 0 for PORT registers
    BANKSEL PORTD
    CLRF    PORTD
    CLRF    PORTC
    
    ; Initialize LCD
    CALL    inid
    
    ; Initialize variables
    CALL    init_variables
    
    ; Show welcome sequence
    CALL    welcome_sequence
    
    ; Start main program
    GOTO    main_program

; Initialize all variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
init_variables:
    ; Clear all control variables
    CLRF    current_digit
    CLRF    digit_pos
    CLRF    timeout_counter
    CLRF    state
    CLRF    number_mode
    CLRF    input_mode
    CLRF    result_mode
    CLRF    display_offset
    CLRF    last_button
    CLRF    button_timer
    CLRF    click_count
    CLRF    auto_fill_flag
    CLRF    section_complete
    
    ; Clear number storage (24 bytes total for 6+6 digits per number)
    MOVLW   0x30                ; 48 bytes to clear (4 numbers ? 12 bytes each)
    MOVWF   temp_counter
    MOVLW   num1_int
    MOVWF   FSR
    
clear_numbers:
    CLRF    INDF
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    clear_numbers
    
    RETURN

; Welcome sequence ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
welcome_sequence:
    MOVLW   0x03
    MOVWF   temp_counter
    
blink_loop:
    ; Show welcome message
    BCF     Select, RS
    MOVLW   0x01
    CALL    send
    MOVLW   0x80
    CALL    send
    
    BSF     Select, RS
    CALL    send_welcome_text
    
    ; Wait 0.5 seconds
    MOVLW   D'250'
    CALL    xms
    MOVLW   D'250'
    CALL    xms
    
    ; Clear display
    BCF     Select, RS
    MOVLW   0x01
    CALL    send
    
    ; Wait 0.5 seconds
    MOVLW   D'250'
    CALL    xms
    MOVLW   D'250'
    CALL    xms
    
    DECFSZ  temp_counter, F
    GOTO    blink_loop
    
    ; Wait 2 seconds
    MOVLW   0x02
    CALL    xseconds
    
    RETURN

send_welcome_text:
    ; Line 1: "Welcome to"
    MOVLW   'W'
    CALL    send
    MOVLW   'e'
    CALL    send
    MOVLW   'l'
    CALL    send
    MOVLW   'c'
    CALL    send
    MOVLW   'o'
    CALL    send
    MOVLW   'm'
    CALL    send
    MOVLW   'e'
    CALL    send
    MOVLW   ' '
    CALL    send
    MOVLW   't'
    CALL    send
    MOVLW   'o'
    CALL    send
    
    ; Line 2: "Division"
    BCF     Select, RS
    MOVLW   0xC0
    CALL    send
    BSF     Select, RS
    
    MOVLW   'D'
    CALL    send
    MOVLW   'i'
    CALL    send
    MOVLW   'v'
    CALL    send
    MOVLW   'i'
    CALL    send
    MOVLW   's'
    CALL    send
    MOVLW   'i'
    CALL    send
    MOVLW   'o'
    CALL    send
    MOVLW   'n'
    CALL    send
    
    RETURN

; Main program loop ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main_program:
    ; Setup interrupts
    BANKSEL INTCON
    BSF     INTCON, GIE
    BSF     INTCON, INTE
    BSF     INTCON, T0IE
    
    BANKSEL OPTION_REG
    MOVLW   b'00000101'         ; Timer0 prescaler 1:64
    MOVWF   OPTION_REG
    
    ; Return to Bank 0 for main operations
    BANKSEL PORTD
    
    ; Start with number 1 input
    CALL    display_number_input
    
program_loop:
    ; Main state machine
    MOVF    state, W
    BTFSC   STATUS, Z
    GOTO    normal_input_mode
    
    SUBLW   0x10
    BTFSC   STATUS, Z
    GOTO    next_number_mode
    
    MOVF    state, W
    SUBLW   0x20
    BTFSC   STATUS, Z
    GOTO    calculation_mode
    
    MOVF    state, W
    SUBLW   0x40
    BTFSC   STATUS, Z
    GOTO    result_mode_handler
    
    GOTO    program_loop

normal_input_mode:
    ; Check for display update flag (set by interrupt)
    MOVF    section_complete, F
    BTFSS   STATUS, Z
    GOTO    update_display_now
    
    ; Check for auto-fill condition
    MOVF    auto_fill_flag, F
    BTFSC   STATUS, Z
    GOTO    program_loop
    
    ; Auto-fill timeout occurred
    CLRF    auto_fill_flag
    CALL    handle_auto_fill
    GOTO    program_loop

update_display_now:
    ; Clear the update flag
    CLRF    section_complete
    
    ; Update display safely in main loop (not interrupt)
    CALL    display_current_number
    CALL    position_cursor
    
    GOTO    program_loop

next_number_mode:
    ; Handle transition to next number/section
    CALL    handle_section_transition
    GOTO    program_loop

calculation_mode:
    ; Handle calculation and result
    CALL    handle_calculation
    GOTO    program_loop

result_mode_handler:
    ; Handle result display
    CALL    handle_result_mode
    GOTO    program_loop

; Display number input screen ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
display_number_input:
    ; Clear display
    BCF     Select, RS
    MOVLW   0x01
    CALL    send
    
    ; Add small delay after clear
    MOVLW   D'10'
    CALL    xms
    
    ; Display "Number X"
    MOVLW   0x80
    CALL    send
    BSF     Select, RS
    
    MOVLW   'N'
    CALL    send
    MOVLW   'u'
    CALL    send
    MOVLW   'm'
    CALL    send
    MOVLW   'b'
    CALL    send
    MOVLW   'e'
    CALL    send
    MOVLW   'r'
    CALL    send
    MOVLW   ' '
    CALL    send
    
    ; Display number (1 or 2)
    MOVF    number_mode, W
    ADDLW   0x31
    CALL    send
    
    ; Display current number with scrolling
    CALL    display_current_number
    
    ; Position cursor
    CALL    position_cursor
    
    ; Reset state and start timeout
    CLRF    state
    CLRF    auto_fill_flag
    MOVLW   0x3C                ; Start timeout counter
    MOVWF   timeout_counter
    
    RETURN

; Display current number with 6+6 format (same as result display) ;;;;;;;;;;;;;;;;;;
display_current_number:
    ; Position at line 2
    BCF     Select, RS
    MOVLW   0xC0
    CALL    send
    BSF     Select, RS
    
    ; Get base address for current number
    MOVLW   num1_int
    BTFSC   number_mode, 0
    MOVLW   num2_int
    MOVWF   FSR
    
    ; Show 6 integer digits (exactly like result display)
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    
    ; Display decimal point
    MOVLW   '.'
    CALL    send
    
    ; Show 6 decimal digits (exactly like result display)
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    
    RETURN

; Position cursor for 6-digit input (simplified and fixed) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
position_cursor:
    ; Calculate cursor position for format: XXXXXX.XXXXXX
    ; Total format is 13 characters: 6 integers + 1 decimal point + 6 decimals
    
    MOVLW   0xC0                ; Start of line 2
    MOVWF   cursor_pos
    
    BTFSC   input_mode, 0
    GOTO    position_decimal_cursor
    
    ; Integer mode: cursor at positions 0, 1, 2, 3, 4, 5
    MOVF    digit_pos, W
    ADDWF   cursor_pos, F
    GOTO    set_cursor

position_decimal_cursor:
    ; Decimal mode: cursor at positions 7, 8, 9, 10, 11, 12
    ; Skip 6 integer digits + 1 decimal point = 7 positions
    MOVLW   0x07
    ADDWF   cursor_pos, F
    MOVF    digit_pos, W
    ADDWF   cursor_pos, F

set_cursor:
    ; Set cursor position
    BCF     Select, RS
    MOVF    cursor_pos, W
    CALL    send
    
    ; Enable cursor blink
    MOVLW   0x0F
    CALL    send
    
    RETURN

; Update display digit (stack-safe version) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
update_display_digit:
    ; Reduce CALL nesting to prevent stack overflow
    ; Just refresh the display and position cursor
    BCF     Select, RS
    MOVLW   0xC0
    CALL    send
    BSF     Select, RS
    
    ; Get base address for current number
    MOVLW   num1_int
    BTFSC   number_mode, 0
    MOVLW   num2_int
    MOVWF   FSR
    
    ; Display 6 integer digits
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    
    ; Display decimal point
    MOVLW   '.'
    CALL    send
    
    ; Display 6 decimal digits
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    
    ; Position cursor directly
    MOVLW   0xC0
    MOVWF   cursor_pos
    
    BTFSC   input_mode, 0
    GOTO    pos_decimal_cursor
    
    ; Integer mode cursor
    MOVF    digit_pos, W
    ADDWF   cursor_pos, F
    GOTO    set_cursor_direct

pos_decimal_cursor:
    ; Decimal mode cursor
    MOVLW   0x07
    ADDWF   cursor_pos, F
    MOVF    digit_pos, W
    ADDWF   cursor_pos, F

set_cursor_direct:
    ; Set cursor position
    BCF     Select, RS
    MOVF    cursor_pos, W
    CALL    send
    MOVLW   0x0F
    CALL    send
    
    RETURN

; Handle auto-fill for 6 digits (stack-safe version) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
handle_auto_fill:
    ; Get current digit value to fill with
    MOVF    current_digit, W
    MOVWF   temp_var
    
    ; Fill remaining positions in current section
    MOVF    digit_pos, W
    ADDLW   0x01
    MOVWF   temp_counter
    
auto_fill_loop:
    ; Check if we've reached end of section (6 digits total)
    MOVF    temp_counter, W
    SUBLW   0x05                ; Compare with 5 (positions 0-5)
    BTFSS   STATUS, C           ; If temp_counter > 5, we're done
    GOTO    auto_fill_complete
    
    ; Calculate memory address for current position
    MOVLW   num1_int
    BTFSC   number_mode, 0
    MOVLW   num2_int
    BTFSC   input_mode, 0
    ADDLW   0x06                ; Add 6 for decimal part
    ADDWF   temp_counter, W
    MOVWF   FSR
    
    ; Store the fill value
    MOVF    temp_var, W
    MOVWF   INDF
    
    INCF    temp_counter, F
    GOTO    auto_fill_loop

auto_fill_complete:
    ; Update display directly (no CALL to prevent stack overflow)
    GOTO    inline_display_update

inline_display_update:
    ; Inline display update to prevent stack overflow
    BCF     Select, RS
    MOVLW   0xC0
    CALL    send
    BSF     Select, RS
    
    ; Get base address for current number
    MOVLW   num1_int
    BTFSC   number_mode, 0
    MOVLW   num2_int
    MOVWF   FSR
    
    ; Display all digits inline
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    MOVLW   '.'
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    
    ; Move to next digit position for manual adjustment
    INCF    digit_pos, F
    MOVF    digit_pos, W
    SUBLW   0x05                ; Check if we've reached position 5 (last digit)
    BTFSS   STATUS, C           ; If digit_pos > 5, section is complete
    GOTO    section_finished
    
    ; Position cursor inline
    MOVLW   0xC0
    MOVWF   cursor_pos
    BTFSC   input_mode, 0
    GOTO    pos_dec_cursor
    MOVF    digit_pos, W
    ADDWF   cursor_pos, F
    GOTO    set_cursor_inline

pos_dec_cursor:
    MOVLW   0x07
    ADDWF   cursor_pos, F
    MOVF    digit_pos, W
    ADDWF   cursor_pos, F

set_cursor_inline:
    BCF     Select, RS
    MOVF    cursor_pos, W
    CALL    send
    MOVLW   0x0F
    CALL    send
    
    ; Reset timeout for next digit
    MOVLW   0x3C
    MOVWF   timeout_counter
    
    RETURN

section_finished:
    ; Current section is complete - set digit_pos to 5 (last position)
    MOVLW   0x05
    MOVWF   digit_pos
    MOVLW   0x10
    MOVWF   state
    RETURN

; Handle section transitions (back to working version) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
handle_section_transition:
    ; Check which section just completed
    BTFSC   input_mode, 0
    GOTO    decimal_section_done
    
    ; Integer section done - move to decimal
    MOVLW   0x01
    MOVWF   input_mode
    CLRF    digit_pos
    CLRF    current_digit
    CLRF    state
    CLRF    auto_fill_flag
    CALL    display_number_input
    RETURN

decimal_section_done:
    ; Decimal section done - check which number
    BTFSC   number_mode, 0
    GOTO    both_numbers_done
    
    ; Number 1 done - move to number 2
    CALL    show_number_2_transition
    
    MOVLW   0x01
    MOVWF   number_mode
    CLRF    input_mode
    CLRF    digit_pos
    CLRF    current_digit
    CLRF    state
    CLRF    auto_fill_flag
    CALL    display_number_input
    RETURN

both_numbers_done:
    ; Both numbers complete - start calculation immediately
    CALL    handle_calculation
    RETURN

show_number_2_transition:
    ; Clear display
    BCF     Select, RS
    MOVLW   0x01
    CALL    send
    
    ; Display "Number 2"
    MOVLW   0x80
    CALL    send
    BSF     Select, RS
    
    MOVLW   'N'
    CALL    send
    MOVLW   'u'
    CALL    send
    MOVLW   'm'
    CALL    send
    MOVLW   'b'
    CALL    send
    MOVLW   'e'
    CALL    send
    MOVLW   'r'
    CALL    send
    MOVLW   ' '
    CALL    send
    MOVLW   '2'
    CALL    send
    
    ; Wait exactly 1 second
    MOVLW   0x01
    CALL    xseconds
    
    RETURN

; Handle calculation and result ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
handle_calculation:
    ; Disable interrupts during calculation
    BANKSEL INTCON
    BCF     INTCON, GIE
    
    BANKSEL PORTD
    
    ; Show equals sign
    BCF     Select, RS
    MOVLW   0x01
    CALL    send
    
    ; Add delay after clear
    MOVLW   D'10'
    CALL    xms
    
    MOVLW   0x80
    CALL    send
    
    BSF     Select, RS
    MOVLW   '='
    CALL    send
    
    ; Wait briefly to show equals
    MOVLW   D'250'
    CALL    xms
    MOVLW   D'250'
    CALL    xms
    
    ; Send data to co-processor
    CALL    send_to_coprocessor
    
    ; Perform simple calculation (using first digits)
    CALL    simple_division
    
    ; Show result immediately
    CALL    show_result_display
    
    ; Re-enable interrupts for result mode
    BANKSEL INTCON
    BSF     INTCON, GIE
    
    BANKSEL PORTD
    
    ; Enter result mode
    MOVLW   0x40
    MOVWF   state
    RETURN

; Communication with co-processor ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
send_to_coprocessor:
    ; Send byte count first (24 bytes total for 6+6 digits per number)
    MOVLW   0x18                ; 24 bytes
    MOVWF   PORTC
    CALL    wait_for_ack
    
    ; Send number 1 (12 bytes)
    MOVLW   num1_int
    MOVWF   FSR
    MOVLW   0x0C
    MOVWF   temp_counter
    
send_num1_loop:
    MOVF    INDF, W
    MOVWF   PORTC
    CALL    wait_for_ack
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    send_num1_loop
    
    ; Send number 2 (12 bytes)
    MOVLW   num2_int
    MOVWF   FSR
    MOVLW   0x0C
    MOVWF   temp_counter
    
send_num2_loop:
    MOVF    INDF, W
    MOVWF   PORTC
    CALL    wait_for_ack
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    send_num2_loop
    
    RETURN

wait_for_ack:
    ; Wait for acknowledgment from co-processor
    MOVLW   D'10'
    CALL    xms
    RETURN

; Simple division using first digits ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
simple_division:
    ; Get first digits for simple division
    MOVLW   num1_int
    MOVWF   FSR
    MOVF    INDF, W
    MOVWF   temp_var            ; Dividend
    
    MOVLW   num2_int
    MOVWF   FSR
    MOVF    INDF, W
    MOVWF   temp_counter        ; Divisor
    
    ; Check division by zero
    BTFSC   STATUS, Z
    GOTO    div_by_zero
    
    ; Perform division
    MOVLW   result_int
    MOVWF   FSR
    CLRF    INDF
    
div_loop:
    MOVF    temp_counter, W
    SUBWF   temp_var, W
    BTFSS   STATUS, C
    GOTO    div_done
    
    MOVF    temp_counter, W
    SUBWF   temp_var, F
    INCF    INDF, F
    
    MOVF    INDF, W
    SUBLW   0x09
    BTFSS   STATUS, C
    GOTO    div_done
    
    GOTO    div_loop

div_by_zero:
    MOVLW   result_int
    MOVWF   FSR
    MOVLW   0x09
    MOVWF   INDF

div_done:
    RETURN

; Show result display with proper 6-digit format ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
show_result_display:
    ; Clear display
    BCF     Select, RS
    MOVLW   0x01
    CALL    send
    
    ; Add delay after clear
    MOVLW   D'10'
    CALL    xms
    
    ; Show "Result"
    MOVLW   0x80
    CALL    send
    BSF     Select, RS
    
    MOVLW   'R'
    CALL    send
    MOVLW   'e'
    CALL    send
    MOVLW   's'
    CALL    send
    MOVLW   'u'
    CALL    send
    MOVLW   'l'
    CALL    send
    MOVLW   't'
    CALL    send
    
    ; Show result value in proper 6-digit format
    BCF     Select, RS
    MOVLW   0xC0
    CALL    send
    BSF     Select, RS
    
    ; Display 6 integer digits
    MOVLW   result_int
    MOVWF   FSR
    MOVLW   0x06
    MOVWF   temp_counter
    
display_result_int:
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    display_result_int
    
    ; Display decimal point
    MOVLW   '.'
    CALL    send
    
    ; Display 6 decimal digits
    MOVLW   0x06
    MOVWF   temp_counter
    
display_result_dec:
    MOVF    INDF, W
    ADDLW   0x30
    CALL    send
    INCF    FSR, F
    DECFSZ  temp_counter, F
    GOTO    display_result_dec
    
    RETURN

; Handle result mode ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
handle_result_mode:
    ; For now, just stay in result mode
    ; This could be enhanced later for button cycling
    GOTO    program_loop

    END