;
; **** Note **** to use this code you need to patch the floating point rom
;
;=============================
;Floating Point Patch (#Dxxx):
;=============================
;
;Original                     Patch
;-------------------------    -------------------------
;D4AF: Ad 04 E0  LDA #E004    D4AF: AD 11 B0  LDA #B011
;D4B2: C9 BF     CMP @#BF     D4B2: C9 40     CMP @#BF
;D4B4: F0 0A     BEQ #D4C0    D4B4: F0 0A     BEQ #D4C0
;D4B6: AD 00 A0  LDA #A000    D4B6: AD 01 A0  LDA #A001
;D4B9: C9 40     CMP @#40     D4B9: C9 BF     CMP @#BF
;D4BB: D0 83     BNE #D440    D4BB: D0 83     BNE #D440
;D4BD: 4C 01 A0  JMP #A002    D4BD: 4C 02 A0  JMP #A002
;D4C0: 4C 05 E0  JMP #E005    D4C3: 4C 12 B0  JMP #B012

; Part 1 is $0202 bytes $B010-B211
; Part 2 is $028f bytes $B410-B69e
; Workspace is $00C2 bytes long


; *** Options ***

LATCH           = $BFFF
; SHADOW        = $FD           ; If $BFFF is write only otherwise SHADOW =$BFFF
SHADOW          = $BFFF
MAX             = $8
ZPBASE          = $90
ZPLENGTH        = $10

; *** Workarea ***

BASE            = $B300
BRKLOW          = BASE
BRKHIGH         = BRKLOW+1
BRKROM          = BRKHIGH+1
STARTROM        = BRKROM+1
TEMP            = STARTROM+1
VECTOR          = TEMP
DUMP            = TEMP+1
VECT            = MAX*ZPLENGTH
VECTAB          = VECT+DUMP+1
SUB_ACCU        = VECTAB+1+15*3
SUB_STATUS      = SUB_ACCU+1
SUB_Y           = SUB_STATUS+1
SUB_X           = SUB_Y+1
STACKPOINTER    = SUB_X
SUBVECTOR       = SUB_X+1
INTVECTOR       = SUBVECTOR+2
INT_ACCU        = INTVECTOR+2
INT_STATUS1     = INT_ACCU+1
INT_STATUS2     = INT_STATUS1+1
INT_X           = INT_STATUS2+1
INT_Y           = INT_X+1
OPT_PCHARME     = INT_Y+1
FREE            = OPT_PCHARME+1

; *** Constants ***

BRKVEC          = $202
TEXT            = $F7D1
CR              = $D
LF              = $A
DELIM           = $EA

.macro STA___LATCH
.if (SHADOW <> LATCH)
   sta   LATCH
.endif
.endmacro

.SEGMENT "PAD1"

.SEGMENT "BRAN1"

; *** Start of assembly ***

        .BYTE $40,$bf           ; ROM entry

; *** Entry in system ***

entry:
   lda   6                      ; test directmode
   cmp   #1
   bne   label8

   bit   $b001                  ; test shift
   bmi   label8

   ldx   #0                     ; test return
   lda   (5,x)
   cmp   #CR
   bne   label8

   jmp   unlock+3               ; if shift-return, unlock roms

label8:
   bit   SHADOW                 ; rom locked?
   bvc   not_locked
   jmp   locked

; *** not locked search ***

not_locked:
   lda   SHADOW                 ; save current rom nr
   sta   STARTROM
   jsr   update_vectors         ; save current vectors
   jsr   switch_context_out     ; store zeropage

   lda   BRKVEC+1               ; check if breakvector is changed
   cmp   #>handler
   beq   label1                 ; if not, change it
   sta   BRKHIGH
   lda   BRKVEC
   sta   BRKLOW

   lda   SHADOW                 ; save lastrom
   sta   BRKROM
label1:
   jmp   switch

; ***  try next box ***

next_box:
   inc   SHADOW                 ; switch to next rom
   lda   SHADOW
   STA___LATCH

   cmp   #MAX                   ; if last reached, switch to rom 0
   bne   label2
   lda   #0
   sta   SHADOW
   STA___LATCH
label2:
   jsr   switch_context_in      ; restore zeropage

   lda   SHADOW                 ; check if all roms entered
   cmp   STARTROM
   bne   switch
   jmp   not_found              ; command not found in roms, try table

; *** replace break vector and enter rom ***

switch:
   lda   #>handler              ; replace breakvector
   sta   BRKVEC+1
   lda   #<handler
   sta   BRKVEC

   lda   $a000                  ; check if new rom is legal
   cmp   #$40
   bne   next_box
   lda   $a001
   cmp   #$bf
   bne   next_box
   jmp   $a002                  ; is legal, enter rom

; *** central break handler ***

handler:
   pla  
   sta   TEMP                   ; save high byte error
   pla  
   sta   0                      ; save low byte error

   bit   SHADOW                 ; rom locked?
   bvc   not_locked_error
   jmp   locked_error

; *** error with rom not locked ***

not_locked_error:
   cmp   #94                    ; error 94?
   bne   not_error_94

   ldy   $5e                    ; check if command is abreviated
   lda   (5),y
   cmp   #'.'
   bne   label99
   jmp   not_found              ; command not found in roms, try table
label99:
   ldx   #$ff                   ; reset STACKPOINTER
   txs  
   jmp   next_box               ; check next rom

; *** function check ***

not_error_94:
   lda   BRKLOW                 ; set breakpointer
   sta   BRKVEC
   lda   BRKHIGH
   sta   BRKVEC+1

   lda   0                      ; get error nr
   cmp   #174                   ; error 174?
   beq   install

   cmp   #29                    ; error 29?
   bne   not_install

; *** install fake caller ***

install:
   tsx                          ; save STACKPOINTER
   stx   STACKPOINTER

   ldx   #$ff
lb1:
   lda   $100,x
   cpx   STACKPOINTER
   bcc   not_install
   beq   not_install

   dex  
   dex  
   and   #$f0
   cmp   #$a0
   beq   lb1

   cpx   #$fd                   ; no a-block?
   beq   not_install

   txa  
   clc  
   adc   #3
   sta   STACKPOINTER
   pha  
   pha  
   pha  
   tsx  
lb2:
   lda   $103,x
   sta   $100,x
   inx  
   cpx   STACKPOINTER
   bne   lb2

   lda   STACKPOINTER
   tax  
   dex  
   lda   SHADOW
   sta   $100,x
   dex  
   lda   #>(switch_back-1)
   sta   $100,x
   lda   #<(switch_back-1)
   dex  
   sta   $100,x

not_install:
   jsr   switch_context_out     ; store zeropage
   jsr   update_vectors         ; save vectors

   lda   BRKROM                 ; set start rom nr
   sta   SHADOW
   STA___LATCH

   jsr   switch_context_in      ; restore zeropage

; *** terminate search ***

   lda   0                      ; get lb return address
   pha                          ; push on stack
   lda   TEMP                   ; get hb return address
   pha                          ; push on stack
   jmp   (BRKVEC)               ; return

; *** error with rom locked ***

locked_error:
   lda   SHADOW                 ; set start rom nr
   sta   BRKROM

   lda   0                      ; get error nr
   cmp   #94                    ; error 94?
   beq   label3
   jmp   not_error_94

label3:
   ldx   #$ff                   ; reset STACKPOINTER
   txs  
   jmp   not_found              ; command not found in roms, try table

; *** store zeropage (always #91-#98) ***

switch_context_out:
   lda   SHADOW                 ; get rom nr
   and   #$f                    ; filter to 0-15
   tax  
   inx  

   lda   #0

label4:
   clc                          ; dump pointer = romnr * ZPLENGTH-1
   adc   #ZPLENGTH
   dex  
   bne   label4

   ldx   #(ZPLENGTH-1)          ; set ZPBASE pointer
   tay  
   dey  

label5:
   lda   ZPBASE,x               ; save zeropage
   sta   DUMP,y
   dey  
   dex  
   bpl   label5
   rts  

; *** restore zeropage (always #91-#98) ***

switch_context_in:
   lda   SHADOW                 ; get rom nr
   and   #$f                    ; filter to 0-15
   tax  
   inx  

   lda   #0

label6:
   clc                          ; dump pointer = romnr * ZPLENGTH-1
   adc   #ZPLENGTH
   dex  
   bne   label6

   ldx   #(ZPLENGTH-1)          ; set ZPBASE pointer
   tay  
   dey  

label7:
   lda   DUMP,y                 ; restore zeropage
   sta   ZPBASE,x
   dey  
   dex  
   bpl   label7
   rts  

; *** start search locked ***

locked:
   lda   BRKVEC+1               ; check if break handler switched
   cmp   #>handler
   beq   label21

   sta   BRKHIGH                ; if not, save break handler
   lda   BRKVEC
   sta   BRKLOW

   lda   #>handler              ; replace break handler
   sta   BRKVEC+1
   lda   #<handler
   sta   BRKVEC

   lda   SHADOW                 ; set start rom nr
   sta   BRKROM

label21:
   lda   $a000                  ; check if legal rom
   cmp   #$40
   bne   trap_error
   lda   $a001
   cmp   #$bf
   bne   trap_error
   jmp   $a002                  ; if legal, enter rom

trap_error:
   jmp   $c558                  ; no legal rom, return

; *** not found in boxes ***
;     try own table
;     if not found in table
;     try by original BRKVEC

not_found:
   lda   BRKLOW                 ; reset break handler
   sta   BRKVEC
   lda   BRKHIGH
   sta   BRKVEC+1

   jsr   switch_context_out     ; store zeropage

   lda   BRKROM                 ; reset rom nr
   sta   SHADOW
   STA___LATCH

   jsr   switch_context_in      ; restore zeropage
   ldx   #$ff

next_statement:
   ldy   $5e
   lda   (5),y
   cmp   #'.'
   bne   label54

trap_error_94:
   jmp   $c558

label54:
   dey  

next_char:
   inx  
   iny  

label12:
   lda   table,x
   cmp   #$ff
   beq   trap_error_94

label15:
   cmp   #$fe
   beq   label14
   cmp   (5),y
   beq   next_char
   dex  
   lda   (5),y
   cmp   #'.'
   beq   label100

label13:
   inx  
   lda   table,x
   cmp   #$fe
   bne   label13
   inx  
   inx  
   jmp   next_statement

label100:
   inx  
   lda   table,x
   cmp   #$fe
   bne   label100
   iny  

label14:
   lda   table+1,x
   sta   $53
   lda   table+2,x
   sta   $52
   sty   3
   ldx   4
   jmp   ($0052)

.SEGMENT "PAD2"

.SEGMENT "BRAN2"

; *** own commands ***

rom:
   jsr   $c4e1
   jsr   update_vectors
   ldx   4
   dex  
   stx   4
   lda   $16,x
   and   #$f
   ora   #$40
   sta   SHADOW
   STA___LATCH

   lda   $a000
   cmp   #$40
   bne   label9
   lda   $a001
   cmp   #$bf
   beq   label20

label9:
   jsr   TEXT
   .byte "NO ROM AVAILABLE"
   .byte CR,LF,DELIM

label20:
   lda   BRKROM
   ora   #$40
   cmp   SHADOW
   beq   label60

   lda   #$d8                   ; install original brk handler
   sta   BRKVEC
   lda   #$c9
   sta   BRKVEC+1

label60:
   jmp   $c55b

unlock:
   jsr   $c4e4
   lda   SHADOW
   and   #$f
   sta   SHADOW
   STA___LATCH
   jmp   $c55b

; *** table of commands ***

table:
   .byte "ROM",$fe
   .byte >rom,<rom
   .byte "UNLOCK",$fe
   .byte >unlock,<unlock

   .byte $ff

; *** check vectors ***
; if vector point to #axxx,
; save it with corresponding rom nr
; and replace vector

update_vectors:
   php  
   sei  

   ldx   #0                     ; reset pointers
   ldy   #0

label30:
   lda   $201,x                 ; check if vector points to #axxx
   and   #$f0
   cmp   #$a0
   bne   label31
   cpx   #2                     ; skip brk vector
   beq   label31

   lda   $200,x                 ; save vector
   sta   VECTAB+1,y
   lda   $201,x
   sta   VECTAB,y
   lda   SHADOW                 ; save rom nr
   sta   VECTAB+2,y

   txa                          ; replace vector
   asl   a
   asl   a
   clc  
   adc   #<vecentry
   sta   $200,x
   lda   #>vecentry
   adc   #0
   sta   $201,x

label31:
   inx                          ; point to next vector
   inx  

   iny  
   iny  
   iny  

   cpx   #$1c                   ; check end of vectors
   bne   label30

   lda   $3ff                   ; check if plot vector points at #axxx (screen rom)
   and   #$f0
   cmp   #$a0
   bne   label32

   lda   $3ff                   ; save plot vector
   sta   VECTAB,y
   lda   $3fe
   sta   VECTAB+1,y
   lda   #>(vecentry+14*8)      ; replace plot vector
   sta   $3ff
   lda   #<(vecentry+14*8)
   sta   $3fe

   lda   SHADOW                 ; save rom nr
   sta   VECTAB+2,y

label32:
   plp  
   rts  

; *** entry vector pathways ***

vecentry:
   jsr   isave                  ; $200, nmi vector
   ldx   #0
   jmp   ijob

   nop                          ; $202, brk vector
   nop  
   nop  
   nop  
   nop  
   jmp   $c558

   jsr   isave                  ; $204, irq vector
   ldx   #6
   jmp   ijob

   jsr   save                   ; $206, *com vector
   ldx   #9
   jmp   job

   jsr   save                   ; $208, write vector
   ldx   #12
   jmp   job

   jsr   save                   ; $20a, read vector
   ldx   #15
   jmp   job

   jsr   save                   ; $20c, load vector
   ldx   #18
   jmp   job

   jsr   save                   ; $20e, save vector
   ldx   #21
   jmp   job

   jsr   save                   ; $210,  vector
   ldx   #24
   jmp   job

   jsr   save                   ; $212,  vector
   ldx   #27
   jmp   job

   jsr   save                   ; $214, get byte vector
   ldx   #30
   jmp   job

   jsr   save                   ; $216, put byte vector
   ldx   #33
   jmp   job

   jsr   save                   ; $218, print message vector
   ldx   #36
   jmp   job

   jsr   save                   ; $21a, shut vector
   ldx   #39
   jmp   job

   jsr   save                   ; $3ff, plot vector
   ldx   #42
   jmp   job

; *** save normal processor/registers ***

save:
   php                          ; save processor status
   sta   SUB_ACCU               ; save accu
   pla  
   sta   SUB_STATUS             ; save status
   stx   SUB_X                  ; save x-reg
   sty   SUB_Y                  ; save y-reg
   rts  

; *** save interrupt processor/registers ***

isave:
   php                          ; save processor status
   sta   INT_ACCU               ; save accu
   pla  
   sta   INT_STATUS1            ; save status
   stx   INT_X                  ; save x-reg
   sty   INT_Y                  ; save y-reg
   rts  

; *** reset normal processor/registers ***

load:
   ldy   SUB_Y                  ; reset y-reg
   ldx   SUB_X                  ; reset x-reg
   lda   SUB_STATUS             ; reset status
   pha  
   lda   SUB_ACCU               ; reset accu
   plp                          ; reset processor status
   rts  

; *** reset interrupt processor/registers ***

iload:
   ldx   INT_X                  ; reset y-reg
   ldy   INT_Y                  ; reset x-reg
   lda   INT_STATUS1            ; reset status
   pha  
   lda   INT_ACCU               ; reset accu
   plp                          ; reset processor status
   rts  

; *** interrupt switching pathway ***

ijob:
   pla  
   sta   INT_ACCU
   pla  
   pha  
   sta   INT_STATUS2

   lda   SHADOW                 ; save rom nr
   pha  

   lda   VECTAB+2,x             ; reset rom nr
   sta   SHADOW
   STA___LATCH

   lda   VECTAB,x               ; reset nmi/irq vector
   sta   INTVECTOR+1
   lda   VECTAB+1,x
   sta   INTVECTOR

   lda   #>ientry               ; replace nmi/irq vector
   pha  
   lda   #<ientry
   pha  
   lda   INT_STATUS2
   pha  
   lda   INT_ACCU
   pha  
   jsr   iload
   jmp   (INTVECTOR)            ; jump interrupt vector


; *** nmi/irq entry ***

ientry:
   jsr   isave                  ; save processor/register values
   pla  
   sta   SHADOW
   STA___LATCH
   plp  
   lda   INT_STATUS2
   pha  
   jsr   iload                  ; load processor/register values
   rti                          ; return from interrupt

; *** non interrupt switching pathway ***

job:
   stx   VECTOR
   txa  
   pha  

   lda   $60                    ; save option pcharm
   sta   OPT_PCHARME            ;**!!**

   lda   VECTAB+2,x
   cmp   SHADOW
   beq   short_execution
   cpx   #21                    ; save file
   bne   label40

   jsr   update_vectors         ;**!!**
   ldx   VECTOR

label40:
   cpx   #30                    ; get byte
   beq   short_execution
   cpx   #33                    ; put byte
   beq   short_execution
   jsr   switch_context_out     ; store zeropage
   ldx   VECTOR
   lda   SHADOW
   pha  
   lda   VECTAB+1,x
   sta   SUBVECTOR
   lda   VECTAB,x
   sta   SUBVECTOR+1
   lda   VECTAB+2,x
   sta   SHADOW
   STA___LATCH
   jsr   switch_context_in      ; restore zeropage
   jsr   load
   jsr   lb50
   jmp   lb51

lb50:
   jmp   (SUBVECTOR)

lb51:
   jsr   save
   jsr   switch_context_out     ; store zeropage
   pla  
   sta   SHADOW
   STA___LATCH
   jsr   switch_context_in      ; restore zeropage

   lda   OPT_PCHARME            ;**!!**
   sta   $60

   pla  
   cmp   #21                    ; save file
   bne   lb10
   lda   VECTAB+13
   cmp   #$ce                   ; ed64 outchar?
   bne   lb10

   lda   #$ce                   ;**!!**
   sta   $208
   lda   #$ac
   sta   $209

lb10:
   jmp   load

; *** no swith pathway ***

short_execution:
   pla  
   ldx   VECTOR
   lda   SHADOW
   pha  
   lda   VECTAB+2,x
   sta   SHADOW
   STA___LATCH
   lda   VECTAB,x
   sta   SUBVECTOR+1
   lda   VECTAB+1,x
   sta   SUBVECTOR
   jsr   load
   jsr   lb60
   jmp   lb61

lb60:
   jmp   (SUBVECTOR)

lb61:
   jsr   save
   pla  
   sta   SHADOW
   STA___LATCH

   lda   OPT_PCHARME            ;**!!**
   sta   $60
   jmp   load

; *** fake expression caller ***

switch_back:
   jsr   save
   jsr   switch_context_out     ; store zeropage
   pla  
   sta   SHADOW
   STA___LATCH
   jsr   switch_context_in      ; restore zeropage
   lda   #>handler              ; reinit break handler
   sta   BRKVEC+1
   lda   #<handler
   sta   BRKVEC
   jmp   load
