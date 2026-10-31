* Test-only foreground supervisor: cctnice PRIORITY <cctpark arguments>.
* X=command tail,U=private data. Parse 128..160; D/X/Y/CC scratch.
* F$Fork copies the remaining CR-terminated arguments and returns child PID A.
* F$SPrior changes only that returned child, never Shell or this supervisor.
* F$Wait reaps it and propagates status. On priority error, request graceful
* child interrupt, reap and report original error. No direct hardware/masks.
* Run foreground for benchmarks. To stop playback, identify and signal the
* child cctpark process; this test helper does not forward parent signals.
H6309 SET 1
        include os9.d
        MOD endmod,name,$11,$80,start,data_size
        org 0
priority RMB 1
child RMB 1
error RMB 1
data_size EQU .
name    FCS "cctnice"
        FCB 1
player  FCS "cctpark"
start   clrb
skip    lda ,x+
        cmpa #32
        beq skip
parse   suba #'0'
        cmpa #9
        bhi invalid
        pshs a
        lda #10
        mul
        addb ,s+
        adca #0
        bne invalid
        lda ,x+
        cmpa #32
        bne parse
        cmpb #128
        blo invalid
        cmpb #160
        bhi invalid
        stb priority,u
        tfr x,y
length  lda ,y+
        cmpa #13
        bne length
        pshs x
        tfr y,d
        subd ,s++
        tfr d,y
        pshs u
        tfr x,u
        leax player,pcr
        ldd #$1100
        os9 F$Fork
        puls u
        bcs exit
        sta child,u
        ldb priority,u
        os9 F$SPrior
        bcs stop_child
        os9 F$Wait
        bcs exit
        cmpa child,u
        bne invalid
exit    os9 F$Exit
stop_child
        stb error,u
        lda child,u
        ldb #S$Intrpt
        os9 F$Send
        os9 F$Wait
        ldb error,u
        bra exit
invalid ldb #1
        bra exit
        EMOD
endmod
