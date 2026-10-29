; User-process /ctclock probe. Repeats 600 sleeps of X=2 (one tick after
; phase adjustment). Before/after snapshots are exported as select-only PSG
; markers: F2, tick bytes Xhi,Xlo,Yhi,Ylo, F3. No sound register data write.
; Never run during playback. Preserves MPI and incoming CC per marker group.
; Errors close the owned path and exit with the failing OS-9 error code.
H6309  equ 1
        include os9.d
        mod End,Name,Prgrm+Objct,ReEnt,Start,MemSize
        org 0
Path    rmb 1
Count   rmb 2
MemSize equ .
Name    fcs "clkprobe"
        fcb 1
Device  fcc "/ctclock"
        fcb 13
Start   leax Device,pcr
        lda #UPDAT.
        os9 I$Open
        bcs Exit
        sta Path,u
        lbsr Sample
        bcs Close
        ldd #600
        std Count,u
Loop    ldx #2
        os9 F$Sleep
        bcs Close
        ldd Count,u
        subd #1
        std Count,u
        bne Loop
        lbsr Sample
Close   pshs b,cc
        lda Path,u
        os9 I$Close
        puls cc,b
        bcs Exit
        clrb
Exit    os9 F$Exit
Sample  lda Path,u
        ldb #$80
        os9 I$GetStt
        bcs Done
        pshs cc
        orcc #$50
        lda >$FF7F
        pshs a
        anda #$FC
        ora #1
        sta >$FF7F
        lda #$F2
        sta >$FF5E
        tfr x,d
        sta >$FF5E
        stb >$FF5E
        tfr y,d
        sta >$FF5E
        stb >$FF5E
        lda #$F3
        sta >$FF5E
        puls a
        sta >$FF7F
        puls cc
        clrb
Done    rts
        emod
End     equ *
