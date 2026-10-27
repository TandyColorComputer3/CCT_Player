*******************************************************************************
* Read-only NitrOS-9 clock-rate probe used by the PSG timing experiment.
*
* Calls F$TPS in ordinary user process context and prints its returned A/B
* bytes in hexadecimal. A `TPS!` prefix means carry was set and B is the OS-9
* error code; a failed service call is not a clock-rate measurement. No clock,
* scheduler, interrupt, or hardware state is
* changed. Entry: X is the OS-9 command tail; U is process-local data.
* Data layout: returned A/B, one error flag and a 15-byte message (18 bytes).
* F$TPS output is captured before conversion. I$Write uses A=STDOUT, X=message,
* Y=15. F$Exit releases the process normally. User process context; F$TPS,
* I$Write, and F$Exit are the only system calls; no critical section.
* Clobbers A/B/X/Y and condition codes; U remains the process data base.
*******************************************************************************

STDOUT          EQU   1
H6309           SET   1

        include os9.d

        MOD   MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
        org   0
tpsA            RMB   1
tpsB            RMB   1
tpsError        RMB   1
message         RMB   15
data_size       EQU   .

moduleName      FCS   "tpsprobe"
        FCB   1

messageTemplate FCC   "TPS A=00 B=00"
                FCB   $0D,$0A

START_EXEC
        clr   tpsError,U
        os9   F$TPS
        sta   tpsA,U
        stb   tpsB,U
        bcc   TPSPROBE_COPY_START
        inc   tpsError,U
TPSPROBE_COPY_START
        leax  messageTemplate,PCR
        leay  message,U
        ldb   #15
TPSPROBE_COPY
        lda   ,X+
        sta   ,Y+
        decb
        bne   TPSPROBE_COPY

        tst   tpsError,U
        beq   TPSPROBE_CONVERT
        lda   #'!'
        sta   message+3,U
TPSPROBE_CONVERT

        lda   tpsA,U
        lsra
        lsra
        lsra
        lsra
        lbsr  TPSPROBE_HEX_DIGIT
        sta   message+6,U
        lda   tpsA,U
        anda  #$0F
        lbsr  TPSPROBE_HEX_DIGIT
        sta   message+7,U
        lda   tpsB,U
        lsra
        lsra
        lsra
        lsra
        lbsr  TPSPROBE_HEX_DIGIT
        sta   message+11,U
        lda   tpsB,U
        anda  #$0F
        lbsr  TPSPROBE_HEX_DIGIT
        sta   message+12,U

        lda   #STDOUT
        leax  message,U
        ldy   #15
        os9   I$Write
        clrb
        os9   F$Exit

; A=0..15, returns ASCII hexadecimal in A. Clobbers condition codes only.
TPSPROBE_HEX_DIGIT
        cmpa  #10
        blo   TPSPROBE_HEX_NUMBER
        adda  #('A'-10)
        rts
TPSPROBE_HEX_NUMBER
        adda  #'0'
        rts

        EMOD
MODULE_SIZE
