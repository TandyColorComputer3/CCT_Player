; Ordinary user process; predecoded, generated test stream only.
; Opens exclusive /psgq, appends each four-byte constant via register values,
; starts and polls at ~1-second intervals. No hardware or kernel memory access.
; F$Icpt intercept only latches a stop byte; ordinary cleanup closes the path.
; OS-9 forced termination also closes the owned path, invoking driver SS.Close.
; Inputs X=command tail,U=private data; D/X/Y/CC scratch. Exit propagates errors.
H6309 equ 1
        include os9.d
        mod End,Name,Prgrm+Objct,ReEnt,Start,MemSize
        org 0
Path    rmb 1
StopReq rmb 1
Cursor  rmb 2
Remain  rmb 2
MemSize equ .
        ifdef IRQ_BURST
Name    fcs "irqburst"
        else
        ifdef IRQ_UNDER
Name    fcs "irqunder"
        else
        ifdef IRQ_OVER
Name    fcs "irqover"
        else
Name    fcs "irqprobe"
        endc
        endc
        endc
        fcb 1
Device  fcc "/psgq"
        fcb 13
Message fcc "IRQPROBE COMPLETE"
        fcb 13
MsgLen  equ *-Message
Start   clr StopReq,u
        leax Intercept,pcr
        os9 F$Icpt
        bcs Exit
        leax Device,pcr
        lda #UPDAT.+SHARE.
        os9 I$Open
        bcs Exit
        sta Path,u
        leax Events,pcr
        stx Cursor,u
        ldd #EventCount
        std Remain,u
Append  tst StopReq,u
        bne CloseOK
        ldx Cursor,u
        ldy 2,x
        ldx ,x
        lda Path,u
        ldb #$80
        os9 I$SetStt
        bcs Close
        ldd Cursor,u
        addd #4
        std Cursor,u
        ldd Remain,u
        subd #1
        std Remain,u
        bne Append
        lda Path,u
        ldb #$81
        os9 I$SetStt
        bcs Close
Wait    tst StopReq,u
        bne CloseOK
        lda Path,u
        ldb #$80
        os9 I$GetStt
        bcs Close
        cmpx #1
        bne Finished
        ldx #61
        os9 F$Sleep
        bcs Close
        bra Wait
Finished
        ifdef IRQ_UNDER
        cmpx #3
        else
        cmpx #2
        endc
        bne Failed
        lda #1
        leax Message,pcr
        ldy #MsgLen
        os9 I$WritLn
CloseOK clrb
Close   pshs b,cc
        lda Path,u
        os9 I$Close
        puls cc,b
Exit    os9 F$Exit
Failed  ldb #1
        bra Close
Intercept
        inc StopReq,u
        rti
Events
        ifdef IRQ_BURST
        include build/irq-burst.inc
        else
        ifdef IRQ_UNDER
        include build/irq-under.inc
        else
        ifdef IRQ_OVER
        include build/irq-over.inc
        else
        include build/irq-events.inc
        endc
        endc
        endc
EventCount equ (*-Events)/4
        emod
End     equ *
