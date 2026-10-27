*******************************************************************************
* F$Sleep timing probe for an isolated CoCoPSG test session.
* Ordinary user process; U is its local data base. No interrupt mask is used.
* Select MPI slot 2, then request X=1,2,3,4,10,61 ticks five times each.
* A write tap on $FF5E sees, per call: $10+index before F$Sleep, $20+index
* after it, and the low byte of returned X. $FE marks a system-call error.
* These are register selections only; no $FF5F data is written. The previous
* MPI selection is restored; the PSG register-select latch is left at 7.
* Run without another PSG user. F$Sleep may be interrupted by a signal; this
* probe has no intercept. F$Exit terminates normally. Clobbers A/B/X/CC.
*******************************************************************************
H6309 SET 1
        include os9.d
MPI     EQU $FF7F
SEL     EQU $FF5E
        MOD MODULE_SIZE,name,$11,$80,entry,datasize
        org 0
oldmpi  rmb 1
index   rmb 1
repeat  rmb 1
datasize equ .
name    fcs "sleepprb"
        fcb 1
ticks   fdb 1,2,3,4,10,61
entry   lda >MPI
        sta oldmpi,U
        anda #$F0
        ora #1
        sta >MPI
        lda #5
        sta repeat,U
outer   clr index,U
next    lda index,U
        adda #$10
        sta >SEL
        lda index,U
        lsla
        leax ticks,PCR
        ldx a,x
        os9 F$Sleep
        bcs error
        lda index,U
        adda #$20
        sta >SEL
        tfr x,d
        stb >SEL
        inc index,U
        lda index,U
        cmpa #6
        blo next
        dec repeat,U
        bne outer
        bra done
error   lda #$FE
        sta >SEL
done    lda #7
        sta >SEL
        lda oldmpi,U
        sta >MPI
        clrb
        os9 F$Exit
        EMOD
MODULE_SIZE
