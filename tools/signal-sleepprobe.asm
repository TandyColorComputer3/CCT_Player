*******************************************************************************
* Signal interruption of F$Sleep, for an isolated CoCoPSG test session.
* Ordinary user process with a 512-byte local stack reserve; no IRQ masking.
* F$Icpt installs an RTI handler, then F$Sleep requests X=6000 ticks. Send
* S$Intrpt to the displayed background PID with the preloaded cctstop helper.
* A $FF5E write tap sees $F0 before the call, $F1 on return, then saved CC,
* B, X high, X low, and finally 7. Carry in saved CC reports an OS-9 error;
* X is the returned remaining count. These writes select registers only, with
* no PSG data writes. The previous MPI selection is restored; the PSG select
* latch is left at 7. Run without another PSG user. F$Exit ends the process.
* F$Icpt has no error branch in this probe; F$Sleep's returned CC is recorded.
* Entry U is the process-local data base; clobbers A/B/X/CC.
*******************************************************************************
H6309 SET 1
        include os9.d
MPI     EQU $FF7F
SEL     EQU $FF5E
        MOD MODULE_SIZE,name,$11,$80,entry,datasize
        org 0
oldmpi  rmb 1
        rmb 512
datasize equ .
name    fcs "sigprb"
        fcb 1
entry   lda >MPI
        sta oldmpi,U
        anda #$F0
        ora #1
        sta >MPI
        leax handler,PCR
        os9 F$Icpt
        lda #$F0
        sta >SEL
        ldx #6000
        os9 F$Sleep
        pshs cc,b,x
        lda #$F1
        sta >SEL
        puls a
        sta >SEL
        puls a
        sta >SEL
        puls a
        sta >SEL
        puls a
        sta >SEL
        lda #7
        sta >SEL
        lda oldmpi,U
        sta >MPI
        clrb
        os9 F$Exit
handler rti
        EMOD
MODULE_SIZE
