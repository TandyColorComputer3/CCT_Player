*******************************************************************************
* Bounded timing workload: 60 counter lines, then exit naturally.
* Ordinary OS-9 user process; same I$Write/F$Sleep pattern as cctcount.
* U is process data, no signal handler, no IRQ mask, no hardware writes.
* Each iteration writes one six-byte CR/LF record and sleeps 61 ticks; the
* final write exits without sleeping. F$Sleep/I$Write errors exit immediately.
* This self-terminating helper avoids signaling another process after tests.
*******************************************************************************

STDOUT          EQU   1
H6309           SET   1

        include os9.d

        MOD   MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
        org   0
counterText     RMB   6
remaining       RMB   1
data_size       EQU   .

moduleName      FCS   "timeload"
        FCB   1              ; module edition byte follows the FCS name

START_EXEC
        lda   #60
        sta   remaining,U
        ldd   #$3030
        std   counterText,U
        std   counterText+2,U
        lda   #$0D
        sta   counterText+4,U
        lda   #$0A
        sta   counterText+5,U

CCTCOUNTER_LOOP
        lda   #STDOUT
        leax  counterText,U
        ldy   #6
        os9   I$Write
        bcs   CCTCOUNTER_EXIT
        dec   remaining,U
        bne   TIMELOAD_SLEEP
        clrb                    ; normal finite completion status is zero
        bra   CCTCOUNTER_EXIT
TIMELOAD_SLEEP
        ldx   #61             ; EOU queues after X-1 ticks: 60 ~= one NTSC second
        os9   F$Sleep         ; suspends this process; other tasks keep running
        bcs   CCTCOUNTER_EXIT
        lbsr  CCTCOUNTER_INCREMENT
        bra   CCTCOUNTER_LOOP

CCTCOUNTER_INCREMENT
        leax  counterText+3,U
        ldb   #4
CCTCOUNTER_INCREMENT_DIGIT
        inc   ,X
        lda   ,X
        cmpa  #$3A            ; carry when the digit advanced past '9'
        blo   CCTCOUNTER_INCREMENT_DONE
        lda   #$30
        sta   ,X
        leax  -1,X
        decb
        bne   CCTCOUNTER_INCREMENT_DIGIT
CCTCOUNTER_INCREMENT_DONE
        rts

CCTCOUNTER_EXIT
        os9   F$Exit

        EMOD
MODULE_SIZE
