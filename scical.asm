; ============================================================
;  GROUP OF CHOA PRESENTS:
;  SCIENTIFIC CALCULATOR - TASM (Turbo Assembler) 16-bit DOS
;  32-bit arithmetic using DX:AX / register pairs
;
;  Supports: + - * / ^ (Exponent) % (Percent of) ! (Factorial)
;  Number range: 0 to ~2,147,483,647 (signed 32-bit)
;
;  Assemble : TASM SCICALC.ASM
;  Link     : TLINK SCICALC.OBJ
;  Run      : SCICALC.EXE
; ============================================================

.MODEL SMALL
.STACK 400h

.DATA

banner   DB 13,10
         DB "  ============================================",13,10
         DB "       SCIENTIFIC CALCULATOR  v1.0           ",13,10
         DB "  ============================================",13,10
         DB "  Ops : + - * / ^(Exponent) %(Percent of) !(Factorial)  ",13,10
         DB "  Factorial only needs first number.         ",13,10
         DB "  Type EXIT to quit.                         ",13,10
         DB "  ============================================",13,10,'$'

pr1      DB 13,10,"  First number  : $"
prop     DB "  Operator      : $"
pr2      DB "  Second number : $"
pr_res   DB 13,10,"  Result = $"
pr_sep   DB 13,10,"  ----------------------------------------",13,10,'$'
pr_bye   DB 13,10,"  Goodbye!",13,10,'$'
pr_ediv  DB 13,10,"  ERROR: Division by zero!$"
pr_eneg  DB 13,10,"  ERROR: Factorial of negative!$"
pr_eop   DB 13,10,"  ERROR: Unknown operator!$"
pr_minus DB "-$"

; DOS buffered input: [max][actual][data...]
inbuf    DB 20, 0, 20 DUP(0)

; 32-bit operands and result (stored lo-word first)
N1L      DW 0          ; num1 low  word
N1H      DW 0          ; num1 high word
N2L      DW 0
N2H      DW 0
RL       DW 0          ; result low
RH       DW 0          ; result high

N1NEG    DB 0          ; 1 = num1 is negative
N2NEG    DB 0
RNEG     DB 0          ; 1 = result is negative
OP       DB 0
EXITF    DB 0

.CODE

; ============================================================
MAIN PROC
    MOV  AX, @DATA
    MOV  DS, AX

    LEA  DX, banner
    MOV  AH, 09h
    INT  21h

; ============================================================
LOOP_TOP:
    ; ---- read first number ----
    LEA  DX, pr1
    MOV  AH, 09h
    INT  21h

    CALL READ_LINE
    CALL CHK_EXIT
    CMP  EXITF, 1
    JNE  L_NOEXIT
    JMP  L_DONE
L_NOEXIT:
    CALL PARSE32           ; -> N1L, N1H, N1NEG

    ; ---- read operator ----
    LEA  DX, prop
    MOV  AH, 09h
    INT  21h

    CALL READ_LINE
    LEA  SI, inbuf+2
    MOV  AL, [SI]
    MOV  OP, AL

    ; factorial skips second number
    CMP  AL, '!'
    JNE  L_NEED2
    JMP  DO_FACT
L_NEED2:

    ; ---- read second number ----
    LEA  DX, pr2
    MOV  AH, 09h
    INT  21h

    CALL READ_LINE
    CALL PARSE32_2         ; -> N2L, N2H, N2NEG

    ; ---- dispatch ----
    MOV  AL, OP
    CMP  AL, '+'
    JNE  D_NOT_ADD
    JMP  DO_ADD
D_NOT_ADD:
    CMP  AL, '-'
    JNE  D_NOT_SUB
    JMP  DO_SUB
D_NOT_SUB:
    CMP  AL, '*'
    JNE  D_NOT_MUL
    JMP  DO_MUL
D_NOT_MUL:
    CMP  AL, '/'
    JNE  D_NOT_DIV
    JMP  DO_DIV
D_NOT_DIV:
    CMP  AL, '^'
    JNE  D_NOT_POW
    JMP  DO_POW
D_NOT_POW:
    CMP  AL, '%'
    JNE  D_NOT_PCT
    JMP  DO_PCT
D_NOT_PCT:
    LEA  DX, pr_eop
    MOV  AH, 09h
    INT  21h
    JMP  NEXT_CALC

; ============================================================
; ADDITION  num1 + num2
; ============================================================
DO_ADD:
    ; Handle signs: if both same sign, add magnitudes.
    ; If different signs, subtract smaller from larger.
    MOV  AL, N1NEG
    CMP  AL, N2NEG
    JNE  ADD_DIFF_SIGN

    ; Same sign: add magnitudes
    MOV  AX, N1L
    MOV  DX, N1H
    ADD  AX, N2L
    ADC  DX, N2H
    MOV  RL, AX
    MOV  RH, DX
    MOV  AL, N1NEG
    MOV  RNEG, AL          ; result sign = common sign
    JMP  SHOW_RESULT

ADD_DIFF_SIGN:
    ; Different signs: result = larger_mag - smaller_mag
    ; Compare magnitudes: N1H:N1L vs N2H:N2L
    MOV  AX, N1H
    CMP  AX, N2H
    JA   ADD_N1_BIGGER
    JB   ADD_N2_BIGGER
    MOV  AX, N1L
    CMP  AX, N2L
    JAE  ADD_N1_BIGGER
    ; else N2 bigger

ADD_N2_BIGGER:
    ; result = N2 - N1, sign = N2NEG
    MOV  AX, N2L
    MOV  DX, N2H
    SUB  AX, N1L
    SBB  DX, N1H
    MOV  RL, AX
    MOV  RH, DX
    MOV  AL, N2NEG
    MOV  RNEG, AL
    JMP  SHOW_RESULT

ADD_N1_BIGGER:
    ; result = N1 - N2, sign = N1NEG
    MOV  AX, N1L
    MOV  DX, N1H
    SUB  AX, N2L
    SBB  DX, N2H
    MOV  RL, AX
    MOV  RH, DX
    MOV  AL, N1NEG
    MOV  RNEG, AL
    JMP  SHOW_RESULT

; ============================================================
; SUBTRACTION  num1 - num2  (flip num2 sign, then add)
; ============================================================
DO_SUB:
    ; Negate num2 sign and reuse ADD logic
    MOV  AL, N2NEG
    XOR  AL, 1
    MOV  N2NEG, AL
    JMP  DO_ADD

; ============================================================
; MULTIPLICATION  num1 * num2  (32-bit magnitudes)
; ============================================================
DO_MUL:
    ; Product sign
    MOV  AL, N1NEG
    XOR  AL, N2NEG
    MOV  RNEG, AL

    ; Full 32x32 -> 32 (low 32 bits only)
    ; Use: (N1H*65536 + N1L) * (N2H*65536 + N2L)
    ; Keep only lo 32 bits:
    ;   N1L*N2L            -> contributes to bits 0-31
    ;   N1L*N2H (<<16)     -> contributes to bits 16-31
    ;   N1H*N2L (<<16)     -> contributes to bits 16-31

    ; Step 1: N1L * N2L -> DX:AX
    MOV  AX, N1L
    MUL  N2L               ; DX:AX = N1L * N2L
    MOV  RL, AX
    MOV  RH, DX

    ; Step 2: N1L * N2H -> AX (add into RH)
    MOV  AX, N1L
    MUL  N2H               ; AX = low word of N1L*N2H
    ADD  RH, AX

    ; Step 3: N1H * N2L -> AX (add into RH)
    MOV  AX, N1H
    MUL  N2L
    ADD  RH, AX

    JMP  SHOW_RESULT

; ============================================================
; DIVISION  num1 / num2  (32-bit / 32-bit -> 32-bit)
; Uses 32-bit by 16-bit DIV twice (N2H assumed 0 for simplicity;
; for large divisors we use repeated subtraction is too slow;
; instead we support divisors that fit in 16 bits, i.e. <=65535)
; ============================================================
DO_DIV:
    ; Check divide by zero
    MOV  AX, N2L
    OR   AX, N2H
    JNZ  DIV_OK
    LEA  DX, pr_ediv
    MOV  AH, 09h
    INT  21h
    JMP  NEXT_CALC

DIV_OK:
    ; Result sign
    MOV  AL, N1NEG
    XOR  AL, N2NEG
    MOV  RNEG, AL

    ; 32-bit dividend (N1H:N1L) / 16-bit divisor (N2L)
    ; Step 1: divide high word
    MOV  AX, N1H
    MOV  DX, 0
    DIV  N2L               ; AX = high quotient, DX = remainder
    MOV  RH, AX
    ; Step 2: remainder:N1L / divisor
    MOV  AX, N1L
    DIV  N2L               ; AX = low quotient, DX = remainder (discarded)
    MOV  RL, AX

    JMP  SHOW_RESULT

; ============================================================
; POWER  num1 ^ num2
; Repeated multiply: acc=1, multiply by num1, num2 times
; ============================================================
DO_POW:
    MOV  RNEG, 0

    ; exponent = N2L (assume small enough to loop)
    MOV  CX, N2L
    JCXZ POW_ZERO          ; if exponent=0, result=1

    ; acc lo/hi in BX/BP
    MOV  BX, 1
    MOV  BP, 0

POW_LOOP:
    ; acc(BP:BX) = acc * N1(N1H:N1L)
    ; low 32 bits only
    ; BX * N1L -> DX:AX
    MOV  AX, BX
    MUL  N1L
    MOV  DI, AX            ; partial lo
    PUSH DX                ; partial mid

    ; BP * N1L -> AX (-> high word)
    MOV  AX, BP
    MUL  N1L
    MOV  SI, AX            ; partial hi

    ; BX * N1H -> AX (-> high word)
    MOV  AX, BX
    MUL  N1H
    ADD  SI, AX

    POP  AX                ; mid from BX*N1L
    ADD  SI, AX

    MOV  BX, DI
    MOV  BP, SI

    LOOP POW_LOOP
    JMP  POW_DONE

POW_ZERO:
    MOV  BX, 1
    MOV  BP, 0

POW_DONE:
    MOV  RL, BX
    MOV  RH, BP
    JMP  SHOW_RESULT

; ============================================================
; PERCENTAGE  num1 percent of num2  = (num1 * num2) / 100
; ============================================================
DO_PCT:
    MOV  RNEG, 0

    ; (N1L * N2L) / 100  -- keep to 32-bit intermediate
    MOV  AX, N1L
    MUL  N2L               ; DX:AX = product
    ; divide DX:AX by 100
    MOV  BX, 100
    ; Step 1: high / 100
    MOV  AX, DX
    MOV  DX, 0
    DIV  BX
    PUSH AX                ; high quotient
    ; Step 2: rem:original_low / 100
    ; DX still has remainder from step 1? No—we need the original low.
    ; Redo properly:
    POP  AX                ; discard; redo below

    ; Proper 32/16 division:
    MOV  AX, N1L
    MUL  N2L               ; DX:AX = N1L * N2L
    ; divide DX:AX by 100
    MOV  CX, DX            ; save high word of product
    MOV  DX, 0
    ; Step 1: CX / 100
    MOV  AX, CX
    DIV  BX                ; AX = high_q, DX = high_rem
    MOV  RH, AX
    ; Step 2: high_rem : low_product / 100
    ; DX = remainder from step1, AX needs to be low product
    MOV  AX, N1L
    MUL  N2L               ; redo multiply to get low word fresh in AX
    ; AX = low word, DX = high word (we already used high)
    ; We want DX=remainder_from_step1 : AX=low_product
    ; Save the low word
    PUSH AX
    ; Get the remainder: redo step 1 cleanly
    MOV  AX, N1L
    MUL  N2L
    ; DX:AX = product. Save.
    MOV  SI, AX            ; SI = product low
    MOV  DI, DX            ; DI = product high
    ; Step 1: DI / 100
    MOV  AX, DI
    MOV  DX, 0
    DIV  BX                ; AX = high_q, DX = rem
    MOV  RH, AX
    ; Step 2: DX:SI / 100
    MOV  AX, SI
    DIV  BX                ; AX = low_q, DX = remainder
    MOV  RL, AX
    POP  AX                ; clean stack

    JMP  SHOW_RESULT

; ============================================================
; FACTORIAL  num1!
; Iterative multiply: acc=1, acc*=2, acc*=3, ... acc*=n
; 32-bit accumulator in BP:BX
; ============================================================
DO_FACT:
    ; Negative check
    CMP  N1NEG, 1
    JNE  FACT_NOTNEG
    LEA  DX, pr_eneg
    MOV  AH, 09h
    INT  21h
    JMP  NEXT_CALC
FACT_NOTNEG:

    ; Zero check: 0! = 1
    MOV  AX, N1L
    OR   AX, N1H
    JNZ  FACT_START
    MOV  RL, 1
    MOV  RH, 0
    MOV  RNEG, 0
    JMP  SHOW_RESULT

FACT_START:
    MOV  RNEG, 0
    MOV  BX, 1             ; acc_lo
    MOV  BP, 0             ; acc_hi
    MOV  CX, N1L          ; loop n times (multiplier goes 2..n)
    MOV  DI, 2             ; current multiplier

FACT_LOOP:
    CMP  DI, CX
    JA   FACT_DONE         ; done when multiplier > n

    ; acc(BP:BX) = acc * DI  (DI is 16-bit multiplier)
    MOV  AX, BX
    MUL  DI                ; DX:AX = acc_lo * DI
    PUSH DX                ; save carry
    PUSH AX                ; save lo result

    MOV  AX, BP
    MUL  DI                ; AX = acc_hi * DI (low word only)
    MOV  SI, AX

    POP  AX                ; lo result
    POP  DX                ; carry from lo
    ADD  SI, DX            ; combine into hi

    MOV  BX, AX
    MOV  BP, SI

    INC  DI
    JMP  FACT_LOOP

FACT_DONE:
    MOV  RL, BX
    MOV  RH, BP
    JMP  SHOW_RESULT

; ============================================================
; SHOW RESULT
; ============================================================
SHOW_RESULT:
    LEA  DX, pr_res
    MOV  AH, 09h
    INT  21h

    CMP  RNEG, 1
    JNE  SR_POS
    LEA  DX, pr_minus
    MOV  AH, 09h
    INT  21h
SR_POS:
    MOV  AX, RL
    MOV  DX, RH
    CALL PRINT32           ; print DX:AX as unsigned decimal

NEXT_CALC:
    LEA  DX, pr_sep
    MOV  AH, 09h
    INT  21h
    JMP  LOOP_TOP

L_DONE:
    LEA  DX, pr_bye
    MOV  AH, 09h
    INT  21h
    MOV  AX, 4C00h
    INT  21h

MAIN ENDP

; ============================================================
;  READ_LINE  -- DOS buffered keyboard input into inbuf
; ============================================================
READ_LINE PROC
    LEA  DX, inbuf
    MOV  AH, 0Ah
    INT  21h
    MOV  DL, 13
    MOV  AH, 02h
    INT  21h
    MOV  DL, 10
    MOV  AH, 02h
    INT  21h
    RET
READ_LINE ENDP

; ============================================================
;  CHK_EXIT  -- sets EXITF=1 if input is "EXIT" (any case)
; ============================================================
CHK_EXIT PROC
    MOV  EXITF, 0
    LEA  SI, inbuf+2
    MOV  AL, [SI]
    AND  AL, 0DFh
    CMP  AL, 'E'
    JNE  CX_NO
    INC  SI
    MOV  AL, [SI]
    AND  AL, 0DFh
    CMP  AL, 'X'
    JNE  CX_NO
    INC  SI
    MOV  AL, [SI]
    AND  AL, 0DFh
    CMP  AL, 'I'
    JNE  CX_NO
    INC  SI
    MOV  AL, [SI]
    AND  AL, 0DFh
    CMP  AL, 'T'
    JNE  CX_NO
    MOV  EXITF, 1
CX_NO:
    RET
CHK_EXIT ENDP

; ============================================================
;  PARSE32  -- parse inbuf+2 into N1L, N1H, N1NEG
; ============================================================
PARSE32 PROC
    LEA  SI, inbuf+2
    MOV  N1NEG, 0
    MOV  BX, 0
    MOV  DI, 0
    ; check minus
    MOV  AL, [SI]
    CMP  AL, '-'
    JNE  P32_1_NEXT
    MOV  N1NEG, 1
    INC  SI
P32_1_LOOP:
P32_1_NEXT:
    MOV  AL, [SI]
    CMP  AL, 0Dh
    JE   P32_1_DONE
    CMP  AL, 0
    JE   P32_1_DONE
    CMP  AL, '0'
    JB   P32_1_DONE
    CMP  AL, '9'
    JA   P32_1_DONE

    ; digit = AL - '0'
    SUB  AL, '0'
    MOV  AH, 0             ; AX = digit

    ; DI:BX = DI:BX * 10 + digit
    PUSH AX
    ; BX * 10
    MOV  AX, BX
    MOV  DX, 0
    MOV  CX, 10
    MUL  CX                ; DX:AX = BX*10
    MOV  BX, AX
    PUSH DX                ; carry into high
    ; DI * 10
    MOV  AX, DI
    MUL  CX
    POP  CX                ; carry from BX*10
    ADD  AX, CX
    MOV  DI, AX
    ; add digit
    POP  AX
    ADD  BX, AX
    ADC  DI, 0

    INC  SI
    JMP  P32_1_NEXT

P32_1_DONE:
    MOV  N1L, BX
    MOV  N1H, DI
    RET
PARSE32 ENDP

; ============================================================
;  PARSE32_2  -- same as PARSE32 but fills N2L, N2H, N2NEG
; ============================================================
PARSE32_2 PROC
    LEA  SI, inbuf+2
    MOV  N2NEG, 0
    MOV  BX, 0
    MOV  DI, 0
    MOV  AL, [SI]
    CMP  AL, '-'
    JNE  P32_2_NEXT
    MOV  N2NEG, 1
    INC  SI
P32_2_LOOP:
P32_2_NEXT:
    MOV  AL, [SI]
    CMP  AL, 0Dh
    JE   P32_2_DONE
    CMP  AL, 0
    JE   P32_2_DONE
    CMP  AL, '0'
    JB   P32_2_DONE
    CMP  AL, '9'
    JA   P32_2_DONE

    SUB  AL, '0'
    MOV  AH, 0

    PUSH AX
    MOV  AX, BX
    MOV  DX, 0
    MOV  CX, 10
    MUL  CX
    MOV  BX, AX
    PUSH DX
    MOV  AX, DI
    MUL  CX
    POP  CX
    ADD  AX, CX
    MOV  DI, AX
    POP  AX
    ADD  BX, AX
    ADC  DI, 0

    INC  SI
    JMP  P32_2_NEXT

P32_2_DONE:
    MOV  N2L, BX
    MOV  N2H, DI
    RET
PARSE32_2 ENDP

; ============================================================
;  PRINT32  -- print 32-bit unsigned value in DX:AX
;  Method: repeatedly divide DX:AX by 10, push remainders,
;          then pop and print.
; ============================================================
PRINT32 PROC
    ; Save value into SI:DI
    MOV  SI, DX            ; high
    MOV  DI, AX            ; low

    ; Special case: zero
    MOV  AX, DI
    OR   AX, SI
    JNZ  PR32_NONZERO
    MOV  DL, '0'
    MOV  AH, 02h
    INT  21h
    RET

PR32_NONZERO:
    MOV  CX, 0             ; digit count

PR32_DIV:
    ; Check if SI:DI == 0
    MOV  AX, DI
    OR   AX, SI
    JZ   PR32_PRINT

    ; Divide SI:DI by 10
    ; Step 1: SI / 10
    MOV  AX, SI
    MOV  DX, 0
    MOV  BX, 10
    DIV  BX                ; AX = SI/10, DX = SI%10
    MOV  SI, AX            ; update high quotient
    ; Step 2: (DX remainder):DI / 10
    MOV  AX, DI
    DIV  BX                ; AX = new low quotient, DX = final remainder (digit)
    MOV  DI, AX

    ADD  DL, '0'
    PUSH DX
    INC  CX
    JMP  PR32_DIV

PR32_PRINT:
    JCXZ PR32_DONE
    POP  DX
    MOV  AH, 02h
    INT  21h
    DEC  CX
    JMP  PR32_PRINT

PR32_DONE:
    RET
PRINT32 ENDP

END MAIN