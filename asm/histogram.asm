    LDI R0, 1
    LDI R4, 0 ; When to stop printing asterisks

LINES:
    LDI R2, MAX_ASTERISKS 
    LD R2, R2
    CMP R0, R2
    
    LDI R1, END
    JGT R1
    
    ; Calculate the number of asterisks to print out
    LDI R3, 0
    ADD R3, R0

    ; Load asterisk character into R2
    LDI R1, ASTERISKS
    LDI R2, ASTERISK
    LD R2, R2
ASTERISKS:
    PRA R2
    DEC R3
    CMP R3, R4
    JGT R1

    ; Double i
    LDI R2, 2
    MUL R0, R2
    
    LDI R1, LINES

    ; Print newline
    LDI R2, NEWLINE
    LD R2, R2
    PRA R2
    
    JMP R1

END:
    HLT

MAX_ASTERISKS: db 16
ASTERISK: ds *
NEWLINE: db 0x0A
