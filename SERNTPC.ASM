.model small
.stack 100h

.data
    sendStr DB '#GETTIME#', 0DH   ; COMMAND + RT
    sendLen EQU $ - sendStr

    recvBuf DB 14 DUP(?)          ; Get time data / YYYYMMDDHHMMSS
    recvLen EQU 14

    msgSend DB 13,10,'Sending: #GETTIME#',13,10,'$'
    msgRecv DB 13,10,'Received:',13,10,'$'
    doneMsg DB 13,10,'[DONE]',13,10,'$'

    ; -------------------------------
    ; DOS command string
    ; -------------------------------
    cmdDate db 'C:\COMMAND.COM', 0, '/C DATE ', '00-00-00', 0
    cmdTime db 'C:\COMMAND.COM', 0, '/C TIME ', '00:00:00', 0
    ;cmdBuffer DB 20 DUP(?)        

.code
main:
    MOV AX, @data
    MOV DS, AX

    ; Init Serial port COM1: 9600,8N1
    MOV DX, 3FBh        ; LCR
    MOV AL, 80h         ; DLAB=1
    OUT DX, AL

    MOV DX, 3F8h        ; divided by Low bits
    MOV AL, 0Ch         ; 9600 = 115200/12
    OUT DX, AL

    MOV DX, 3F9h        ; divided by High bits
    MOV AL, 00h
    OUT DX, AL

    MOV DX, 3FBh        ; LCR
    MOV AL, 03h         ; DLAB=0, 8N1
    OUT DX, AL

    ; Print Send Prompt
    MOV DX, OFFSET msgSend
    MOV AH, 09h
    INT 21h

    ; Send Command
    MOV SI, OFFSET sendStr
    MOV CX, sendLen
SendLoop:
    CALL SendChar
    LOOP SendLoop

    ; Clear Reveive Buffer
    CALL ClearRecvBuf

    ; Waiting for ESP32
    CALL Delay
    CALL Delay

    ; Print Received Prompt
    MOV DX, OFFSET msgRecv
    MOV AH, 09h
    INT 21h

    ; Receive First 14 bytes
    MOV DI, OFFSET recvBuf
    MOV CX, recvLen
RecvLoop:
    CALL RecvChar
    MOV [DI], AL
    INC DI
    LOOP RecvLoop

    ; Print Received Message
    MOV SI, OFFSET recvBuf
    MOV CX, recvLen
ShowLoop:
    MOV AL, [SI]
    CALL ShowChar
    INC SI
    LOOP ShowLoop

    ; Set system date and time
    CALL FormatAndSetTime

    ; Print Done Message
    MOV DX, OFFSET doneMsg
    MOV AH, 09h
    INT 21h

    ; Exit
    MOV AH, 4Ch
    INT 21h

; ------------------------------
; Sub Program: SendChar
; ------------------------------
SendChar:
    PUSH DX
WaitSend:
    MOV DX, 3FDh        ; Line Status
    IN AL, DX
    TEST AL, 20h        ; Writeable?
    JZ WaitSend
    MOV DX, 3F8h
    MOV AL, [SI]
    OUT DX, AL
    INC SI
    CALL Delay
    POP DX
    RET

; ------------------------------
; Sub Program: RecvChar → AL
; ------------------------------
RecvChar:
    PUSH DX
WaitRecv:
    MOV DX, 3FDh
    IN AL, DX
    TEST AL, 01h        ; have data?
    JZ WaitRecv
    MOV DX, 3F8h
    IN AL, DX
    POP DX
    RET

; ------------------------------
; Sub Program: Display AL as Character
; ------------------------------
ShowChar:
    PUSH AX
    MOV DL, AL
    MOV AH, 02H
    INT 21H
    POP AX
    RET

; ------------------------------
; Sub Program: Simple Delay
; ------------------------------
Delay:
    PUSH CX
    MOV CX, 3000
DelayLoop:
    NOP
    LOOP DelayLoop
    POP CX
    RET

; ------------------------------
; Sub Program: Clear Receive Buffer
; ------------------------------
ClearRecvBuf:
    PUSH DX
ClrLoop:
    MOV DX, 3FDh
    IN AL, DX
    TEST AL, 01h
    JZ ClrDone
    MOV DX, 3F8h
    IN AL, DX
    JMP ClrLoop
ClrDone:
    POP DX
    RET

; ------------------------------
; Sub Program: Setting System Date and Time
; ------------------------------
FormatAndSetTime:
    ; Set Date - Using INT 21h/2Ah and 2Bh functions
    ; String to Value
    ; Date Part (YYYYMMDD)
    MOV SI, OFFSET recvBuf    ; Point to YYYYMMDDHHMMSS
    
    ; Parse Year (CX=YYYY)
    CALL AsciiToWord          ; AX=Year
    MOV CX, AX
    
    ; Parse Month (DH=MM)
    CALL AsciiToByte
    MOV DH, AL
    
    ; Parse Day (DL=DD)
    CALL AsciiToByte
    MOV DL, AL
    
    ; Set Date (AH=2Bh, CX=Year, DH=Month, DL=Day)
    MOV AH, 2Bh
    INT 21h    

    ; Set Time - Using INT 21h/2Ch and 2Dh functions
    MOV SI, OFFSET recvBuf + 8
    CALL AtoI            ; Hour
    MOV BH, AL           ; Hour
    CALL AtoI            ; Minute
    MOV BL, AL           ; Minute
    CALL AtoI            ; Second
    MOV DH, AL           ; Second
    MOV DL, 0            ; 1/100 Sec
    
    ; Set Time (CH=Hour, CL=Minute, DH=Second, DL=1/100s)
    MOV CX, BX           ; Hour and Minute
    MOV AH, 2Dh
    INT 21h
    
    RET
; ------------------------------
; Sub Program: Convert the 2-byte ASCII pointed to by SI to a byte (AL)
; Input: SI points to two ASCII characters (such as "25")
; Output: AL = decimal value (such as 25)
; Side effects: SI is incremented by 2
; ------------------------------
AsciiToByte:
    LODSB               ; Read first char 
    SUB AL, '0'         ; trans to number
    MOV AH, AL          ; Save tens digit
    LODSB               ; Read second char
    SUB AL, '0'         ; trans to number
    AAD                 ; AL = AH*10 + AL
    RET
; ------------------------------
; Sub Program: Convert 4-byte ASCII pointed to by SI to word (AX=YYYY)
; Input: SI points to 4-byte ASCII (such as "2025")
; Output: AX=year (such as 2025)
; Side effect: SI increments by 4
; ------------------------------
AsciiToWord:
    PUSH BX
    CALL AsciiToByte    ; Trans first two chars to number (such as "20"→20)
    MOV BL, 100
    MUL BL              ; AX = 20 * 100 = 2000
    MOV BX, AX          ; Save result
    CALL AsciiToByte    ; Trans last two chars to number (such as "25"→25)
    ADD AX, BX          ; AX = 2000 +25 =2025
    POP BX
    RET
; ------------------------------    
; Sub Program: Convert the 2-character ASCII number pointed to by SI to a binary value (AL)
; ------------------------------
AtoI:
    LODSB
    SUB AL, '0'
    MOV AH, AL
    LODSB
    SUB AL, '0'
    AAD                 ; AH*10 + AL -> AL
    RET
    
END main
