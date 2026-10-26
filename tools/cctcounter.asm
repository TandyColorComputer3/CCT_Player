*******************************************************************************
* CCT_Player multitasking test utility
* Prints a four-digit counter once per 60 EOU clock ticks.
*
* Process context: ordinary re-entrant OS-9 user process; no IRQ handler.
* F$Sleep releases the process for 60 system ticks, so the Shell and playback
* process can run. I$Write sends one complete six-byte CR/LF line to STDOUT.
* `counterText` is the six-byte process-local data record: four decimal digits,
* CR, LF. The counter wraps from 9999 to 0000.
* Entry: normal OS-9 module entry with U pointing at this process's data area.
* I$Write inputs: A=STDOUT, X=counterText, Y=6. F$Sleep input: X=60 ticks.
* The loop/helper clobber A, B, X, Y and condition codes; U remains the data base.
* No critical section is used. Output cadence is nominally one second, not a
* precision clock. I$Write/F$Sleep error exits through F$Exit; F$Exit does not return.
*******************************************************************************

STDOUT          EQU   1
H6309           SET   1

        include os9.d

        MOD   MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
        org   0
counterText     RMB   6
data_size       EQU   .

moduleName      FCS   "cctcount"
        FCB   1              ; module edition byte follows the FCS name

START_EXEC
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

        ldx   #60             ; EOU clock ticks, nominally one second on NTSC
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
